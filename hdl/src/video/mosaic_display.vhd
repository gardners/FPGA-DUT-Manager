-- mosaic_display: thumbnail layer of the live select screen (issue 0036).
--
-- Reads the latest thumbnail of each selectable machine (0..9) from the
-- DDR3 frame store (mem_pkg port, clk_sys) into a two-line buffer and
-- renders the 720x480 layer on clk_pix; text_display composites it under
-- the select screen wherever the text colour is MOS_KEY (pure green).
--
-- Layout (mosaic_pkg), chosen once per frame: 2x2 tiles of 320x200 when no
-- machine 4..9 is in use (seen or slots), else 4x3 tiles of 160x100. The
-- frame store holds each machine's tile already scaled for the current
-- layout (issue 0038: scale(k) = '1' quarter scale, 160x100); both layouts
-- read 80 RGB888 words (640 px) per display line, 1:1.
-- Tile content per machine k:
--   fresh(k) and scale(k) matches the layout -> thumbnail, buffer cur_buf(k)
--   otherwise seen(k) or slots(k)            -> procedural colour bars
--   otherwise                                -> frown on dark grey
-- Machines 10, 11 (last two 4x3 tiles) and everything outside the block are
-- black. enable = '0' (DDR3 not calibrated, or not on the select screen):
-- no memory traffic, layer black, mos_on = '0'.
--
-- Line protocol: at x = 0 of raster line y the pixel side asks clk_sys
-- (toggle + stable line number) to fetch line y+1 into half (y+1) mod 2 of
-- the line buffer. The reader writes that half's line info (tile modes,
-- layout, on) first, then issues the reads; the pixel side latches the line
-- info at x = 800 of line y (~3700 clk_sys cycles later) and reads the
-- buffer half during line y+1, while the other half is being filled.
-- Per-frame state (layout, modes, buffers) is latched at the request for
-- line 480, so a frame never mixes layouts or buffers. A fetch that has not
-- finished when the next request arrives is abandoned (late responses are
-- dropped).
--
-- Output: r/g/b for the pixel (x, y) four clk_pix cycles after x/y (to
-- match text_display's stage E).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;
use work.mosaic_pkg.all;

entity mosaic_display is
  port (
    -- frame store side (clk_sys)
    clk_sys : in  std_logic;
    mem_req : out mem_req_t;
    mem_rsp : in  mem_rsp_t;
    enable  : in  std_logic;                       -- DDR3 ok and select screen
    slots   : in  std_logic_vector(9 downto 0);    -- local presence (con_slots)
    seen    : in  std_logic_vector(31 downto 0);   -- issue 0035 status vectors
    fresh   : in  std_logic_vector(31 downto 0);
    cur_buf : in  std_logic_vector(31 downto 0);
    scale   : in  std_logic_vector(31 downto 0);   -- '1' = stored at 160x100
    -- pixel side
    clk_pix : in  std_logic;
    x, y    : in  unsigned(10 downto 0);
    de      : in  std_logic;
    r, g, b : out std_logic_vector(7 downto 0);
    mos_on  : out std_logic;                       -- layer active (per line)
    mos_quad: out std_logic                        -- 1 = 2x2 layout
  );
end entity;

architecture rtl of mosaic_display is
  constant LINE_LAST : natural := 524;             -- raster lines 0..524
  constant LATCH_X   : natural := 800;

  type lb_t is array (0 to 511) of std_logic_vector(127 downto 0);
  signal lb : lb_t;
  attribute ram_style : string;
  attribute ram_style of lb : signal is "block";

  -- pixel -> sys request
  signal p_tog  : std_logic := '0';
  signal p_line : unsigned(9 downto 0) := (others => '0');
  signal s_tog  : std_logic_vector(2 downto 0) := "000";
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of s_tog : signal is "TRUE";

  -- line info per buffer half (written on clk_sys, read on clk_pix a line later)
  type mode4_t is array (0 to 3) of tmode_t;
  type info_t is array (0 to 1) of mode4_t;
  signal li_mode : info_t := (others => (others => TM_OFF));
  signal li_on, li_quad : std_logic_vector(1 downto 0) := "00";

  -- per-frame state (clk_sys)
  type mode10_t is array (0 to 9) of tmode_t;
  signal f_mode : mode10_t := (others => TM_OFF);
  signal f_buf  : std_logic_vector(9 downto 0) := (others => '0');
  signal f_en, f_quad : std_logic := '0';

  -- fetch (clk_sys)
  type mach4_t is array (0 to 3) of unsigned(4 downto 0);
  signal pend    : std_logic := '0';
  signal pend_ln : unsigned(9 downto 0) := (others => '0');
  signal req_v   : std_logic := '0';
  signal req_a   : unsigned(MEM_AW - 1 downto 0) := (others => '0');
  signal q_mask, r_mask : std_logic_vector(3 downto 0) := "0000";
  signal q_i, r_i : natural range 0 to 3 := 0;
  signal q_wi, r_wi : unsigned(6 downto 0) := (others => '0');
  signal q_k     : mach4_t := (others => (others => '0'));
  signal q_b     : std_logic_vector(3 downto 0) := "0000";
  signal q_v     : unsigned(7 downto 0) := (others => '0');
  signal f_wlast : unsigned(6 downto 0) := (others => '0');   -- words per tile - 1
  signal r_h     : std_logic := '0';
  signal outst   : unsigned(9 downto 0) := (others => '0');
  signal drop    : std_logic := '0';

  -- pixel side
  signal c_on, c_quad, c_h : std_logic := '0';
  signal c_mode : mode4_t := (others => TM_OFF);
  signal c_frow : std_logic_vector(7 downto 0) := (others => '0');
  signal s1_mode, s2_mode : tmode_t := TM_OFF;
  signal s1_addr : unsigned(8 downto 0) := (others => '0');
  signal s1_sub, s2_sub : unsigned(1 downto 0) := "00";
  signal s1_un   : unsigned(8 downto 0) := (others => '0');
  signal s2_q    : std_logic_vector(127 downto 0) := (others => '0');
  signal s2_bar  : natural range 0 to 6 := 0;
  signal s2_fb   : std_logic := '0';
  signal s3_rgb, s4_rgb : std_logic_vector(23 downto 0) := (others => '0');

  type glyph_t is array (0 to 15) of std_logic_vector(7 downto 0);
  constant FROWN : glyph_t := (x"00", x"00", x"7E", x"81", x"A5", x"81", x"81", x"81",
                               x"99", x"A5", x"C3", x"81", x"7E", x"00", x"00", x"00");
  type bars_t is array (0 to 6) of std_logic_vector(23 downto 0);
  constant BARS : bars_t := (x"C0C0C0", x"C0C000", x"00C0C0", x"00C000",
                             x"C000C0", x"C00000", x"0000C0");
  constant FROWN_BG : std_logic_vector(23 downto 0) := x"303030";
  constant FROWN_FG : std_logic_vector(23 downto 0) := x"A0A0A0";

  -- next tile index > i with a mask bit set (4 = none); i = -1 for the first
  function next_tile(m : std_logic_vector(3 downto 0); i : integer) return natural is
  begin
    for t in 0 to 3 loop
      if t > i and m(t) = '1' then return t; end if;
    end loop;
    return 4;
  end function;
begin
  mem_req.valid <= req_v;
  mem_req.we    <= '0';
  mem_req.addr  <= req_a;
  mem_req.wdata <= (others => '0');
  mem_req.wmask <= (others => '0');

  ---------------------------------------------------------------- clk_sys reader
  process (clk_sys)
    variable acc, startf : boolean;
    variable ni : natural range 0 to 4;
    variable o  : unsigned(9 downto 0);
    variable ny : natural range 0 to 1023;
    variable inuse : std_logic_vector(9 downto 0);
    variable quad, inrow : boolean;
    variable rel, j, v, k : natural;
    variable md : tmode_t;
    variable m4 : std_logic_vector(3 downto 0);
    variable h  : natural range 0 to 1;
    variable w  : unsigned(7 downto 0);
  begin
    if rising_edge(clk_sys) then
      s_tog <= s_tog(1 downto 0) & p_tog;
      if s_tog(2) /= s_tog(1) then
        pend <= '1'; pend_ln <= p_line;     -- p_line is stable for a whole line
      end if;

      -- responses, in request order
      if mem_rsp.rvalid = '1' and drop = '0' then
        if f_quad = '1' then w := to_unsigned(r_i * 80, 8); else w := to_unsigned(r_i * 40, 8); end if;
        w := w + r_wi;
        lb(to_integer(r_h & w)) <= mem_rsp.rdata;
        if r_wi = f_wlast then
          r_wi <= (others => '0');
          ni := next_tile(r_mask, r_i);
          if ni < 4 then r_i <= ni; end if;
        else
          r_wi <= r_wi + 1;
        end if;
      end if;

      -- requests
      acc := req_v = '1' and mem_rsp.ready = '1';
      if acc then
        if q_wi = f_wlast then
          ni := next_tile(q_mask, q_i);
          if ni = 4 then
            req_v <= '0';
          else
            q_i <= ni; q_wi <= (others => '0');
            req_a <= thumb_addr(q_k(ni), q_b(ni), q_v, (others => '0'));
          end if;
        else
          q_wi <= q_wi + 1;
          req_a <= thumb_addr(q_k(q_i), q_b(q_i), q_v, q_wi + 1);
        end if;
      end if;

      o := outst;
      if acc then o := o + 1; end if;
      if mem_rsp.rvalid = '1' then o := o - 1; end if;
      outst <= o;
      if o = 0 then drop <= '0'; end if;

      -- a new line request abandons an unfinished fetch
      startf := false;
      if pend = '1' then
        if req_v = '1' or outst /= 0 then
          req_v <= '0';
          if o /= 0 then drop <= '1'; end if;
        elsif not acc then
          startf := true;
        end if;
      end if;

      if startf then
        pend <= '0';
        ny := to_integer(pend_ln);
        if ny = 480 then
          -- start of vertical blank: latch the next frame's state
          inuse := slots or seen(9 downto 0);
          quad := inuse(9 downto 4) = "000000";
          f_quad <= '1' when quad else '0';
          f_en <= enable;
          for kk in 0 to 9 loop
            if fresh(kk) = '1' and (scale(kk) = '1') /= quad then
              f_mode(kk) <= TM_THUMB;
            elsif inuse(kk) = '1' then
              f_mode(kk) <= TM_BARS;
            else
              f_mode(kk) <= TM_FROWN;
            end if;
          end loop;
          f_buf <= cur_buf(9 downto 0);
          if quad then
            f_wlast <= to_unsigned(79, 7);
          else
            f_wlast <= to_unsigned(39, 7);
          end if;
        elsif ny < 480 then
          h := ny mod 2;
          inrow := false; j := 0; v := 0;
          if f_quad = '1' then
            if ny >= MOS_Y0_Q and ny < MOS_Y0_Q + 2 * MOS_TH_Q then
              inrow := true; rel := ny - MOS_Y0_Q;
              if rel >= MOS_TH_Q then j := 1; end if;
              v := rel - j * MOS_TH_Q;
            end if;
          else
            if ny >= MOS_Y0_D and ny < MOS_Y0_D + 3 * MOS_TH_D then
              inrow := true; rel := ny - MOS_Y0_D;
              if rel >= 2 * MOS_TH_D then j := 2; elsif rel >= MOS_TH_D then j := 1; end if;
              v := rel - j * MOS_TH_D;
            end if;
          end if;
          m4 := "0000";
          for i in 0 to 3 loop
            if f_quad = '1' then k := 2 * j + i; else k := 4 * j + i; end if;
            md := TM_OFF;
            if inrow and f_en = '1' and k <= 9 and (f_quad = '0' or i < 2) then
              md := f_mode(k);
            end if;
            li_mode(h)(i) <= md;
            if md = TM_THUMB then m4(i) := '1'; end if;
            q_k(i) <= to_unsigned(k mod 32, 5);
            if k <= 9 then q_b(i) <= f_buf(k); else q_b(i) <= '0'; end if;
          end loop;
          li_on(h) <= f_en; li_quad(h) <= f_quad;
          q_mask <= m4; r_mask <= m4;
          q_v <= to_unsigned(v, 8);
          if h = 1 then r_h <= '1'; else r_h <= '0'; end if;
          r_wi <= (others => '0'); q_wi <= (others => '0');
          ni := next_tile(m4, -1);
          if ni < 4 then
            q_i <= ni; r_i <= ni; req_v <= '1';
            if f_quad = '1' then k := 2 * j + ni; else k := 4 * j + ni; end if;
            req_a <= thumb_addr(to_unsigned(k, 5), f_buf(k), to_unsigned(v, 8), (others => '0'));
          end if;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- clk_pix render
  process (clk_pix)
    variable in1 : boolean;
    variable p   : natural range 0 to 2047;
    variable i   : natural range 0 to 3;
    variable u, un : natural range 0 to 1023;
    variable ln, rel, vn : natural range 0 to 1023;
    variable s   : natural range 0 to 3;
    variable px  : std_logic_vector(23 downto 0);
    variable bi  : natural range 0 to 6;
  begin
    if rising_edge(clk_pix) then
      -- line requests and line info
      if x = 0 then
        if y >= LINE_LAST then p_line <= (others => '0');
        else p_line <= resize(y + 1, 10); end if;
        p_tog <= not p_tog;
      end if;
      if x = LATCH_X then
        c_h <= p_line(0);
        c_on <= li_on(to_integer(p_line(0 downto 0)));
        c_quad <= li_quad(to_integer(p_line(0 downto 0)));
        c_mode <= li_mode(to_integer(p_line(0 downto 0)));
        -- frown glyph row for this line (normalised to 320x200 tile space)
        ln := to_integer(p_line);
        vn := 0;
        if li_quad(to_integer(p_line(0 downto 0))) = '1' then
          if ln >= MOS_Y0_Q then
            rel := ln - MOS_Y0_Q;
            if rel >= MOS_TH_Q then rel := rel - MOS_TH_Q; end if;
            vn := rel mod 256;
          end if;
        else
          if ln >= MOS_Y0_D then
            rel := ln - MOS_Y0_D;
            if rel >= 2 * MOS_TH_D then rel := rel - 2 * MOS_TH_D;
            elsif rel >= MOS_TH_D then rel := rel - MOS_TH_D; end if;
            vn := (2 * rel) mod 1024;
          end if;
        end if;
        if vn >= 36 and vn < 164 then c_frow <= FROWN((vn - 36) / 8);
        else c_frow <= (others => '0'); end if;
      end if;

      -- stage 1: tile, buffer address
      in1 := de = '1' and c_on = '1' and x >= MOS_X0 and x < MOS_X0 + MOS_W;
      p := (to_integer(x) - MOS_X0) mod 2048;
      if not in1 then p := 0; end if;
      if c_quad = '1' then
        if p >= MOS_TW_Q then i := 1; else i := 0; end if;
        u := p - i * MOS_TW_Q; un := u;
      else
        if p >= 3 * MOS_TW_D then i := 3; elsif p >= 2 * MOS_TW_D then i := 2;
        elsif p >= MOS_TW_D then i := 1; else i := 0; end if;
        u := p - i * MOS_TW_D; un := 2 * u;
      end if;
      if in1 then s1_mode <= c_mode(i); else s1_mode <= TM_OFF; end if;
      s1_addr <= c_h & to_unsigned(p / 4, 8);
      s1_sub  <= to_unsigned(p mod 4, 2);
      s1_un   <= to_unsigned(un, 9);

      -- stage 2: buffer read, procedural patterns
      s2_q <= lb(to_integer(s1_addr));
      s2_mode <= s1_mode; s2_sub <= s1_sub;
      un := to_integer(s1_un);
      if un < 46 then bi := 0; elsif un < 92 then bi := 1; elsif un < 137 then bi := 2;
      elsif un < 183 then bi := 3; elsif un < 229 then bi := 4; elsif un < 275 then bi := 5;
      else bi := 6; end if;
      s2_bar <= bi;
      if un >= 128 and un < 192 then s2_fb <= c_frow(7 - (un - 128) / 8);
      else s2_fb <= '0'; end if;

      -- stage 3: pixel
      s := to_integer(s2_sub);
      px := s2_q(32 * s + 23 downto 32 * s);
      case s2_mode is
        when TM_THUMB => s3_rgb <= px;
        when TM_BARS  => s3_rgb <= BARS(s2_bar);
        when TM_FROWN => if s2_fb = '1' then s3_rgb <= FROWN_FG; else s3_rgb <= FROWN_BG; end if;
        when others   => s3_rgb <= (others => '0');
      end case;
      -- stage 4: output register
      s4_rgb <= s3_rgb;
    end if;
  end process;
  r <= s4_rgb(23 downto 16);
  g <= s4_rgb(15 downto 8);
  b <= s4_rgb(7 downto 0);
  mos_on <= c_on;
  mos_quad <= c_quad;
end architecture;
