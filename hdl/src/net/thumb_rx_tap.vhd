-- thumb_rx_tap: thumbnail relay frames (EtherType 0x88B5, ADR 0005 s10,
-- issue 0038) parsed at line rate in the clk_rx domain, beside the RX slots
-- (relay frames are up to ~8 KiB, larger than a slot).
--
--   * request (subtype 1, broadcast or to one of our MACs): at a good FCS
--     the requester's MAC, scale and rate divisor are published to clk_sys
--     (held bus + toggle; requests are >= 64 bytes apart).
--   * lines (subtype 2, to one of our MACs): every line becomes a LINE tag
--     (machine, row, frame low byte, scale, height) followed by RUN entries
--     (count, RGB888): one per pixel for RAW888, one per tuple for RLE24.
--     An END tag closes the frame: good = FCS ok, header sane, every line
--     complete (runs never cross a line end) and no FIFO overflow. Pixels
--     of a bad frame may already be in the FIFO; thumb_rx_writer only
--     counts the rows of good frames, so they never complete a picture.
--   * present, no source (subtype 3, to one of our MACs): a SEEN tag at a
--     good FCS.
-- FIFO entries (36 bits): tag(35:34) & data(33:0).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.thumb_pkg.all;

entity thumb_rx_tap is
  generic (FIFO_AW : positive := 11);
  port (
    clk      : in  std_logic;                       -- clk_rx
    rx_dv    : in  std_logic;
    rxd      : in  std_logic_vector(7 downto 0);
    mac0, mac1 : in std_logic_vector(47 downto 0);  -- quasi-static (sys domain)
    -- clk_sys side
    sclk     : in  std_logic;
    f_valid  : out std_logic;
    f_dout   : out std_logic_vector(35 downto 0);
    f_pop    : in  std_logic;
    req_stb  : out std_logic;                       -- one sclk cycle per request
    req_mac  : out std_logic_vector(47 downto 0);
    req_scale: out std_logic_vector(7 downto 0);
    req_div  : out std_logic_vector(7 downto 0);
    frames   : out unsigned(15 downto 0)            -- good relay frames (clk_rx)
  );
end entity;

architecture rtl of thumb_rx_tap is
  constant DEPTH : natural := 2 ** FIFO_AW;
  constant G_LINE : std_logic_vector(1 downto 0) := "00";
  constant G_RUN  : std_logic_vector(1 downto 0) := "01";
  constant G_END  : std_logic_vector(1 downto 0) := "10";
  constant G_SEEN : std_logic_vector(1 downto 0) := "11";

  type st_t is (S_IDLE, S_PRE, S_DATA);
  signal st : st_t := S_IDLE;
  signal idx : unsigned(13 downto 0) := (others => '0');
  signal crc : std_logic_vector(31 downto 0) := (others => '1');
  signal m0, m1 : std_logic_vector(47 downto 0) := (others => '0');
  signal okd0, okd1, okb : std_logic := '0';       -- destination matches so far
  signal hdr_ok : std_logic := '0';                -- EtherType/version/magic so far
  signal sub : std_logic_vector(7 downto 0) := (others => '0');
  signal src : std_logic_vector(47 downto 0) := (others => '0');
  signal machine : unsigned(4 downto 0) := (others => '0');
  signal mbad : std_logic := '0';
  signal scale, enc, rdiv, b18 : std_logic_vector(7 downto 0) := (others => '0');
  signal frame8 : std_logic_vector(7 downto 0) := (others => '0');
  signal row : unsigned(15 downto 0) := (others => '0');
  signal nlines, width, height, plen : unsigned(15 downto 0) := (others => '0');
  signal left : unsigned(15 downto 0) := (others => '0');   -- payload bytes left
  signal in_pl : std_logic := '0';
  signal bad : std_logic := '0';
  signal sane : std_logic := '0';
  signal enc_raw, chk, room_r : std_logic := '0';
  signal chk_cnt : unsigned(7 downto 0) := (others => '0');
  signal bi : unsigned(1 downto 0) := (others => '0');      -- byte in tuple/pixel
  signal tup : std_logic_vector(31 downto 0) := (others => '0');
  signal pix : unsigned(15 downto 0) := (others => '0');    -- pixels in this line
  signal ldone : unsigned(15 downto 0) := (others => '0');  -- lines complete
  signal line_pend : std_logic := '0';
  signal f_we : std_logic := '0';
  signal f_din : std_logic_vector(35 downto 0) := (others => '0');
  signal f_used : unsigned(FIFO_AW downto 0);
  signal nfr : unsigned(15 downto 0) := (others => '0');
  -- request to clk_sys
  signal rq_mac : std_logic_vector(47 downto 0) := (others => '0');
  signal rq_sc, rq_dv : std_logic_vector(7 downto 0) := (others => '0');
  signal rq_t : std_logic := '0';
  signal rq_s : std_logic_vector(3 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rq_s : signal is "TRUE";

  function line_tag(m : unsigned(4 downto 0); r : unsigned(15 downto 0); f : std_logic_vector(7 downto 0);
                    sc : std_logic_vector(7 downto 0); h : unsigned(15 downto 0)) return std_logic_vector is
    variable q : std_logic;
  begin
    if sc = x"02" then q := '1'; else q := '0'; end if;
    return G_LINE & "0000" & std_logic_vector(m) & std_logic_vector(r(7 downto 0)) & f & q &
           std_logic_vector(h(7 downto 0));
  end function;
begin
  fifo : entity work.async_fifo_bram generic map (FIFO_AW, 36)
    port map (wclk => clk, we => f_we, din => f_din, wused => f_used,
              rclk => sclk, rvalid => f_valid, dout => f_dout, pop => f_pop);
  frames <= nfr;

  process (clk)
    variable i : natural;
    variable b : std_logic_vector(7 downto 0);
    variable room : boolean;
    variable np : unsigned(15 downto 0);
    variable pushed : boolean;
  begin
    if rising_edge(clk) then
      m0 <= mac0; m1 <= mac1;
      f_we <= '0';
      room := room_r = '1';                  -- always leave room for END
      if f_used < DEPTH - 5 then room_r <= '1'; else room_r <= '0'; end if;
      pushed := false;
      case st is
        when S_IDLE =>
          if rx_dv = '1' then
            if rxd = x"D5" then st <= S_DATA; else st <= S_PRE; end if;
            idx <= (others => '0');
            crc <= (others => '1');
            okd0 <= '1'; okd1 <= '1'; okb <= '1'; hdr_ok <= '1';
            in_pl <= '0'; bad <= '0'; line_pend <= '0'; mbad <= '0'; chk <= '0';
          end if;

        when S_PRE =>
          if rx_dv = '0' then st <= S_IDLE;
          elsif rxd = x"D5" then st <= S_DATA;
          elsif rxd /= x"55" then st <= S_IDLE; end if;

        when S_DATA =>
          if rx_dv = '1' then
            b := rxd;
            crc <= crc32_byte(crc, b);
            if idx /= 16383 then idx <= idx + 1; end if;
            i := to_integer(idx);
            -- header
            if i <= 5 then
              if b /= m0(47 - 8 * i downto 40 - 8 * i) then okd0 <= '0'; end if;
              if b /= m1(47 - 8 * i downto 40 - 8 * i) then okd1 <= '0'; end if;
              if b /= x"FF" then okb <= '0'; end if;
            elsif i <= 11 then
              src <= src(39 downto 0) & b;
            end if;
            case i is
              when 12 => if b /= TH_ETYPE(15 downto 8) then hdr_ok <= '0'; end if;
              when 13 => if b /= TH_ETYPE(7 downto 0) then hdr_ok <= '0'; end if;
              when 14 => if b /= TH_VERSION then hdr_ok <= '0'; end if;
              when 15 => sub <= b;
              when 16 => if b /= TH_MAGIC(15 downto 8) then hdr_ok <= '0'; end if;
              when 17 => if b /= TH_MAGIC(7 downto 0) then hdr_ok <= '0'; end if;
              when 18 => machine <= unsigned(b(4 downto 0)); b18 <= b;     -- request: scale
                         if b(7 downto 5) /= "000" then mbad <= '1'; end if;
              when 19 => rdiv <= b;                                          -- request: divisor
              when 20 => scale <= b;
              when 21 => enc <= b;
                         if b = TH_ENC_RAW then enc_raw <= '1'; else enc_raw <= '0'; end if;
              when 25 => frame8 <= b;
              when 26 => row(15 downto 8) <= unsigned(b);
              when 27 => row(7 downto 0) <= unsigned(b);
              when 28 => nlines(15 downto 8) <= unsigned(b);
              when 29 => nlines(7 downto 0) <= unsigned(b);
              when 30 => width(15 downto 8) <= unsigned(b);
              when 31 => width(7 downto 0) <= unsigned(b);
              when 32 => height(15 downto 8) <= unsigned(b);
              when 33 => height(7 downto 0) <= unsigned(b);
              when 34 =>
                plen(15 downto 8) <= unsigned(b);
                -- header sanity, registered a byte early (timing)
                sane <= '0';
                if mbad = '0' and (enc = TH_ENC_RAW or enc = TH_ENC_RLE) and
                   ((scale = x"01" and width = 320) or (scale = x"02" and width = 160)) and
                   nlines /= 0 and height /= 0 and height <= 200 and row + nlines <= height then
                  sane <= '1';
                end if;
              when 35 =>
                plen(7 downto 0) <= unsigned(b);
                left <= unsigned(plen(15 downto 8) & unsigned(b));
                pix <= (others => '0');
                ldone <= (others => '0');
                bi <= (others => '0');
                -- a lines frame for us with a sane header: first LINE tag
                if hdr_ok = '1' and (okd0 = '1' or okd1 = '1') and sub = TH_SUB_LINES then
                  if sane = '1' and (plen(15 downto 8) /= 0 or b /= x"00") then
                    in_pl <= '1';
                    if room then
                      f_we  <= '1';
                      f_din <= line_tag(machine, row, frame8, scale, height);
                    else
                      bad <= '1';
                    end if;
                  else
                    bad <= '1';
                  end if;
                end if;
              when others => null;
            end case;
            -- payload: pixels (RAW888, 3 bytes) or tuples (RLE24, 4 bytes).
            -- The run is pushed at its last byte; its checks (count, line
            -- end, line count) follow a cycle later (chk; timing): a bad
            -- run only marks the frame bad, whose rows are never counted.
            if in_pl = '1' and i >= 36 then
              if left = 1 then in_pl <= '0'; end if;
              left <= left - 1;
              tup <= tup(23 downto 0) & b;
              if (enc_raw = '1' and bi = 2) or bi = 3 then
                bi <= (others => '0');
                chk <= '1';
                if enc_raw = '1' then chk_cnt <= x"01"; else chk_cnt <= unsigned(tup(23 downto 16)); end if;
                if bad = '0' then
                  if room then
                    f_we  <= '1';
                    pushed := true;
                    if enc_raw = '1' then
                      f_din <= G_RUN & "00" & x"01" & tup(15 downto 0) & b;
                    else
                      f_din <= G_RUN & "00" & tup(23 downto 0) & b;
                    end if;
                  else
                    bad <= '1';
                  end if;
                end if;
              else
                bi <= bi + 1;
              end if;
            end if;
            if chk = '1' then
              chk <= '0';
              np := pix + chk_cnt;
              if chk_cnt = 0 or np > width or ldone >= nlines then
                bad <= '1';
              end if;
              if np = width then
                pix   <= (others => '0');
                ldone <= ldone + 1;
                if ldone + 1 < nlines then line_pend <= '1'; end if;
              else
                pix <= np;
              end if;
            end if;
            -- next line's LINE tag in a cycle without a RUN push
            if line_pend = '1' and not pushed and i /= 35 then
              line_pend <= '0';
              if bad = '0' then
                if room then
                  f_we  <= '1';
                  f_din <= line_tag(machine, row + ldone, frame8, scale, height);
                else
                  bad <= '1';
                end if;
              end if;
            end if;
          else
            -- end of frame (FCS included in the CRC)
            st <= S_IDLE;
            if hdr_ok = '1' and crc = CRC32_RESIDUE then
              if sub = TH_SUB_REQ and (okb = '1' or okd0 = '1' or okd1 = '1') then
                rq_mac <= src;
                rq_sc  <= b18;
                rq_dv  <= rdiv;
                rq_t   <= not rq_t;
                nfr    <= nfr + 1;
              elsif sub = TH_SUB_NOSRC and (okd0 = '1' or okd1 = '1') and mbad = '0' then
                f_we  <= '1';
                f_din <= G_SEEN & (33 downto 5 => '0') & std_logic_vector(machine);
                nfr   <= nfr + 1;
              end if;
            end if;
            if sub = TH_SUB_LINES and hdr_ok = '1' and (okd0 = '1' or okd1 = '1') and idx > 35 then
              f_we <= '1';
              if crc = CRC32_RESIDUE and bad = '0' and ldone = nlines and line_pend = '0' then
                f_din <= G_END & (33 downto 1 => '0') & '1';
                nfr   <= nfr + 1;
              else
                f_din <= G_END & (33 downto 0 => '0');
              end if;
            end if;
          end if;
      end case;
    end if;
  end process;

  -- request to clk_sys: the bus is held until the next request frame ends
  process (sclk)
  begin
    if rising_edge(sclk) then
      rq_s <= rq_s(2 downto 0) & rq_t;
      req_stb <= rq_s(3) xor rq_s(2);
      if rq_s(3) /= rq_s(2) then
        req_mac   <= rq_mac;
        req_scale <= rq_sc;
        req_div   <= rq_dv;
      end if;
    end if;
  end process;
end architecture;
