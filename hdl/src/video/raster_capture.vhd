-- raster_capture: HDMI IN active lines -> pixel ring + line descriptors
-- (issue 0023, ADR 0005 section 8 raster format v1).
--
-- Pixel clock side (pclk):
--   * Sync polarities are learnt like video_meas (the level seen while DE is
--     high is the inactive level).
--   * Line numbering: an active line (DE run) is line 0 when a VSYNC was seen
--     since the previous active line; the frame counter increments there.
--     Other active lines count up. Lines are captured only after the first
--     line 0 since enable (before that their numbers are unknown).
--   * hs_start / hs_end: HSYNC edge positions counted from the first active
--     pixel (= 0) of the preceding line (stable from line to line).
--   * Each accepted line's RGB888 pixels go to a dual-clock pixel ring
--     (2**RING_AW pixels x 24 bit, block RAM); at the end of the DE run the
--     line is committed: a descriptor (start, count, frame, line, flags,
--     drops, hs_start, hs_end) enters a 2**DESC_AW-entry dual-clock FIFO.
--   * A line is accepted only when, at its first pixel, the ring has room for
--     MAX_LINE_PX pixels and the descriptor FIFO has room; otherwise it is
--     dropped whole and counted; the next committed descriptor carries the
--     count (flag b5, "lines dropped since the previous packet sent").
--     Pixels beyond MAX_LINE_PX per line are not stored (active_count is
--     capped): MAX_LINE_PX is the per-datagram pixel limit (owner decision:
--     one datagram per whole line, ADR 0005 v1; 1024 = ADR maximum).
--   * Blanking lines are not captured.
--
-- clk_sys side: desc_valid / desc (stable while valid) / desc_pop (one cycle;
-- the consumer must not pop again before desc_valid has been re-evaluated,
-- i.e. leave one idle cycle). Popping frees the line's pixels. The pixel ring
-- read port has one cycle latency.
--
-- CDC: descriptor write pointer as Gray code (increments by one); the ring
-- and descriptor read pointers go back to pclk with a req/ack handshake over
-- a held bus (pclk sees a conservative, older value).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.raster_pkg.all;

entity raster_capture is
  generic (
    RING_AW     : positive := 13;    -- 8192 pixels (24 KiB)
    DESC_AW     : positive := 4;     -- 16 line descriptors
    MAX_LINE_PX : positive := 1024   -- pixels stored per line / per datagram
  );
  port (
    -- pixel clock domain
    pclk       : in  std_logic;
    de, hs, vs : in  std_logic;
    rgb        : in  std_logic_vector(23 downto 0);   -- R & G & B
    locked     : in  std_logic;      -- source locked (any domain, synchronised)
    -- clk_sys domain
    clk        : in  std_logic;
    enable     : in  std_logic;      -- capture on (synchronised to pclk)
    desc_valid : out std_logic;
    desc       : out rast_desc_t;
    desc_pop   : in  std_logic;
    ring_addr  : in  unsigned(RING_AW - 1 downto 0);
    ring_data  : out std_logic_vector(23 downto 0)
  );
end entity;

architecture rtl of raster_capture is
  constant DEPTH : natural := 2 ** RING_AW;
  subtype rptr_t is unsigned(RING_AW downto 0);
  subtype dptr_t is unsigned(DESC_AW downto 0);

  function bin2gray(b : unsigned) return std_logic_vector is
  begin
    return std_logic_vector(b xor shift_right(b, 1));
  end function;
  function gray2bin(g : std_logic_vector) return unsigned is
    variable b : std_logic_vector(g'range);
  begin
    b(g'high) := g(g'high);
    for i in g'high - 1 downto g'low loop
      b(i) := b(i + 1) xor g(i);
    end loop;
    return unsigned(b);
  end function;

  -- descriptor FIFO (distributed RAM: pclk write, asynchronous read)
  type dmem_t is array (0 to 2 ** DESC_AW - 1) of std_logic_vector(RAST_DESC_W - 1 downto 0);
  signal dmem : dmem_t := (others => (others => '0'));

  ---------------------------------------------------------------- pclk
  signal en_s, lk_s : std_logic_vector(1 downto 0) := "00";
  signal de_r, hs_r, vs_r, de_d : std_logic := '0';
  signal rgb_r : std_logic_vector(23 downto 0) := (others => '0');
  signal hpol, vpol : std_logic := '0';          -- active levels
  signal hs_ad : std_logic := '0';
  signal vs_seen, synced : std_logic := '0';
  signal xpos : unsigned(15 downto 0) := (others => '0');
  signal line_de : std_logic := '0';
  signal hs_st, hs_en : unsigned(15 downto 0) := (others => '0');
  signal frame : unsigned(31 downto 0) := (others => '0');
  signal line  : unsigned(15 downto 0) := (others => '0');
  signal wr_act : std_logic := '0';
  signal wp : rptr_t := (others => '0');
  signal cur : rast_desc_t := RAST_DESC_NONE;
  signal drops : unsigned(7 downto 0) := (others => '0');
  signal pw_we : std_logic := '0';
  signal pw_addr : unsigned(RING_AW - 1 downto 0) := (others => '0');
  signal pw_data : std_logic_vector(23 downto 0) := (others => '0');
  signal dwp : dptr_t := (others => '0');
  signal dwp_g : std_logic_vector(DESC_AW downto 0) := (others => '0');
  signal req_s : std_logic_vector(2 downto 0) := "000";
  signal ack_t : std_logic := '0';
  signal rp_p : rptr_t := (others => '0');      -- ring release pointer seen in pclk
  signal drp_p : dptr_t := (others => '0');

  ---------------------------------------------------------------- clk_sys
  signal dwp_s1, dwp_s2 : std_logic_vector(DESC_AW downto 0) := (others => '0');
  signal drp : dptr_t := (others => '0');
  signal rp  : rptr_t := (others => '0');
  signal valid_r : std_logic := '0';
  signal desc_q : rast_desc_t := RAST_DESC_NONE;
  signal pub_rp : rptr_t := (others => '0');
  signal pub_drp : dptr_t := (others => '0');
  signal req_t : std_logic := '0';
  signal ack_s : std_logic_vector(2 downto 0) := "000";

  attribute ram_style : string;
  attribute ram_style of dmem : signal is "distributed";
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of en_s, lk_s, req_s, dwp_s1, dwp_s2, ack_s : signal is "TRUE";
begin
  ring : entity work.dpram generic map (RING_AW, 24)
    port map (clk_a => pclk, we_a => pw_we, addr_a => pw_addr, din_a => pw_data,
              clk_b => clk, addr_b => ring_addr, dout_b => ring_data);

  ---------------------------------------------------------------- pclk side
  process (pclk)
    variable hs_a, vs_a, rise : std_logic;
    variable p : unsigned(15 downto 0);
    variable used : rptr_t;
    variable ln : unsigned(15 downto 0);
    variable fr : unsigned(31 downto 0);
    variable l0, ok : boolean;
    variable d : rast_desc_t;
  begin
    if rising_edge(pclk) then
      en_s <= en_s(0) & enable;
      lk_s <= lk_s(0) & locked;
      de_r <= de; hs_r <= hs; vs_r <= vs; rgb_r <= rgb;
      de_d <= de_r;
      pw_we <= '0';

      -- read pointers from clk_sys (held bus, req/ack toggles)
      req_s <= req_s(1 downto 0) & req_t;
      if req_s(2) /= req_s(1) then
        rp_p  <= pub_rp;
        drp_p <= pub_drp;
        ack_t <= req_s(1);
      end if;
      dwp_g <= bin2gray(dwp);

      if de_r = '1' then hpol <= not hs_r; vpol <= not vs_r; end if;
      hs_a := hs_r xnor hpol;
      vs_a := vs_r xnor vpol;
      hs_ad <= hs_a;
      if vs_a = '1' then vs_seen <= '1'; end if;
      rise := de_r and not de_d;

      -- position from the first active pixel; HSYNC edges after an active line
      if rise = '1' then p := (others => '0');
      elsif xpos /= x"FFFF" then p := xpos + 1;
      else p := xpos; end if;
      xpos <= p;
      if rise = '1' then line_de <= '1'; end if;
      if line_de = '1' and hs_a = '1' and hs_ad = '0' then hs_st <= p; end if;
      if line_de = '1' and hs_a = '0' and hs_ad = '1' then
        hs_en <= p;
        line_de <= '0';
      end if;

      if en_s(1) = '0' or lk_s(1) = '0' then
        synced <= '0';
      end if;

      if rise = '1' then
        -- line start: number it, then accept or drop it
        l0 := vs_seen = '1';
        if l0 then
          ln := (others => '0');
          fr := frame + 1;
          vs_seen <= '0';
        else
          ln := line + 1;
          fr := frame;
        end if;
        line  <= ln;
        frame <= fr;
        used := wp - rp_p;
        ok := used <= DEPTH - MAX_LINE_PX and dwp - drp_p < 2 ** DESC_AW;
        if en_s(1) = '1' and lk_s(1) = '1' and (synced = '1' or l0) then
          synced <= '1';
          if ok then
            wr_act <= '1';
            d.start := resize(wp(RING_AW - 1 downto 0), 16);
            d.count := to_unsigned(1, 11);
            d.frame := fr;
            d.line  := ln;
            d.flags := (others => '0');
            d.flags(RF_VSYNC)  := vs_a;
            d.flags(RF_VPOL)   := vpol;
            d.flags(RF_HPOL)   := hpol;
            d.flags(RF_ACTIVE) := '1';
            if l0 then d.flags(RF_FIRST) := '1'; end if;
            d.flags(RF_LOCKED) := '1';
            d.drops := drops;
            if drops /= 0 then d.flags(RF_DROPPED) := '1'; end if;
            d.hs_start := hs_st;
            d.hs_end   := hs_en;
            cur <= d;
            drops <= (others => '0');
            pw_we   <= '1';
            pw_addr <= wp(RING_AW - 1 downto 0);
            pw_data <= rgb_r;
            wp <= wp + 1;
          else
            wr_act <= '0';
            if drops /= x"FF" then drops <= drops + 1; end if;
          end if;
        else
          wr_act <= '0';
        end if;
      elsif de_r = '1' then
        if wr_act = '1' and cur.count < MAX_LINE_PX then
          pw_we   <= '1';
          pw_addr <= wp(RING_AW - 1 downto 0);
          pw_data <= rgb_r;
          wp <= wp + 1;
          cur.count <= cur.count + 1;
        end if;
      elsif de_d = '1' and wr_act = '1' then
        -- end of the DE run: commit the line
        dmem(to_integer(dwp(DESC_AW - 1 downto 0))) <= to_slv(cur);
        dwp <= dwp + 1;
        wr_act <= '0';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- clk_sys side
  process (clk)
    variable n : dptr_t;
  begin
    if rising_edge(clk) then
      dwp_s1 <= dwp_g;
      dwp_s2 <= dwp_s1;
      desc_q <= to_desc(dmem(to_integer(drp(DESC_AW - 1 downto 0))));
      n := drp;
      if desc_pop = '1' then
        n := drp + 1;
        rp <= rp + resize(desc_q.count, RING_AW + 1);   -- committed lines are contiguous
        valid_r <= '0';
      elsif gray2bin(dwp_s2) /= drp then
        valid_r <= '1';
      else
        valid_r <= '0';
      end if;
      drp <= n;
      -- publish the read pointers to pclk (one at a time, held until acked)
      ack_s <= ack_s(1 downto 0) & ack_t;
      if ack_s(2) = req_t and (pub_rp /= rp or pub_drp /= drp) then
        pub_rp  <= rp;
        pub_drp <= drp;
        req_t   <= not req_t;
      end if;
    end if;
  end process;
  desc_valid <= valid_r;
  desc <= desc_q;
end architecture;
