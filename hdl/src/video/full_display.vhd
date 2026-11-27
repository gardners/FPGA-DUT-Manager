-- full_display: full-resolution relayed picture layer of the console
-- (issue 0060).
--
-- When the video target is a local machine without local video, its
-- pictures arrive over the thumbnail relay at scale 1/1 and thumb_rx_writer
-- stores them in one of three DDR3 buffers (mem_pkg full_addr, xRGB32, row
-- stride 256 words). This entity reads the latest complete one (buf) line
-- by line (mem_pkg port, clk_sys) into a two-line buffer and renders it 1:1
-- in the 720x480p60 console raster on clk_pix; text_display shows it
-- instead of the text wherever layer_on = '1'.
--
-- Per frame (latched at the request for line 480, the start of vertical
-- blank, so a frame never mixes buffers): enable, buf, width, height. The
-- latched buffer is reported as shown (clk_sys), so the writer never
-- overwrites it. Raster line y shows picture row y + yoff, yoff = (height -
-- 480) / 2 for taller pictures (576 lines: the centre 480), 0 otherwise;
-- pixels x < min(width, 720) of rows < height show the picture, the rest is
-- black. enable = '0': no memory traffic, layer off.
--
-- Line protocol as mosaic_display: at x = 0 of raster line y the pixel side
-- asks clk_sys (toggle + stable line number) to fetch line y+1 into half
-- (y+1) mod 2 of the line buffer; the reader writes that half's line info
-- first, the pixel side latches it at x = 800 of line y and reads the half
-- during line y+1. A fetch not finished when the next request arrives is
-- abandoned (late responses dropped).
--
-- Output: r/g/b for the pixel (x, y) four clk_pix cycles after x/y (as
-- mosaic_display, text_display's stage E).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity full_display is
  generic (
    H_ACTIVE  : natural := 720;
    V_ACTIVE  : natural := 480;
    LINE_LAST : natural := 524;     -- raster lines 0..LINE_LAST
    LATCH_X   : natural := 800
  );
  port (
    -- frame store side (clk_sys)
    clk_sys : in  std_logic;
    mem_req : out mem_req_t;
    mem_rsp : in  mem_rsp_t;
    enable  : in  std_logic;                     -- DDR3 ok and a fresh picture to show
    buf     : in  unsigned(1 downto 0);          -- latest complete picture
    width   : in  unsigned(10 downto 0);
    height  : in  unsigned(9 downto 0);
    shown   : out unsigned(1 downto 0);          -- buffer of the frame being shown
    -- pixel side
    clk_pix : in  std_logic;
    x, y    : in  unsigned(10 downto 0);
    de      : in  std_logic;
    r, g, b : out std_logic_vector(7 downto 0);
    layer_on: out std_logic                      -- layer active (per line)
  );
end entity;

architecture rtl of full_display is
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
  type w_arr is array (0 to 1) of unsigned(10 downto 0);
  signal li_on : std_logic_vector(1 downto 0) := "00";
  signal li_w  : w_arr := (others => (others => '0'));

  -- per-frame state (clk_sys)
  signal f_en   : std_logic := '0';
  signal f_buf  : unsigned(1 downto 0) := "00";
  signal f_w    : unsigned(10 downto 0) := (others => '0');
  signal f_h    : unsigned(9 downto 0) := (others => '0');
  signal f_yoff : unsigned(9 downto 0) := (others => '0');
  signal f_last : unsigned(7 downto 0) := (others => '0');   -- words per line - 1

  -- fetch (clk_sys)
  signal pend    : std_logic := '0';
  signal pend_ln : unsigned(9 downto 0) := (others => '0');
  signal gv      : std_logic := '0';
  signal g_row   : unsigned(10 downto 0) := (others => '0');
  signal g_480, g_lt : boolean := false;
  signal req_v   : std_logic := '0';
  signal req_a   : unsigned(MEM_AW - 1 downto 0) := (others => '0');
  signal q_row   : unsigned(9 downto 0) := (others => '0');
  signal q_wi, r_wi : unsigned(7 downto 0) := (others => '0');
  signal r_h     : std_logic := '0';
  signal outst   : unsigned(9 downto 0) := (others => '0');
  signal drop    : std_logic := '0';

  -- pixel side
  signal c_on, c_h : std_logic := '0';
  signal c_w : unsigned(10 downto 0) := (others => '0');
  signal s1_on : std_logic := '0';
  signal s1_addr : unsigned(8 downto 0) := (others => '0');
  signal s1_sub, s2_sub : unsigned(1 downto 0) := "00";
  signal s2_on : std_logic := '0';
  signal s2_q : std_logic_vector(127 downto 0) := (others => '0');
  signal s3_rgb, s4_rgb : std_logic_vector(23 downto 0) := (others => '0');
begin
  mem_req.valid <= req_v;
  mem_req.we    <= '0';
  mem_req.addr  <= req_a;
  mem_req.wdata <= (others => '0');
  mem_req.wmask <= (others => '0');
  shown <= f_buf;

  ---------------------------------------------------------------- clk_sys reader
  process (clk_sys)
    variable acc, startf : boolean;
    variable o : unsigned(9 downto 0);
    variable ww : unsigned(10 downto 0);
    variable h : natural range 0 to 1;
  begin
    if rising_edge(clk_sys) then
      s_tog <= s_tog(1 downto 0) & p_tog;
      gv <= pend;
      if s_tog(2) /= s_tog(1) then
        pend <= '1'; pend_ln <= p_line;     -- p_line is stable for a whole line
        gv <= '0';
      end if;

      -- responses, in request order
      if mem_rsp.rvalid = '1' and drop = '0' then
        lb(to_integer(r_h & r_wi)) <= mem_rsp.rdata;
        r_wi <= r_wi + 1;
      end if;

      -- requests
      acc := req_v = '1' and mem_rsp.ready = '1';
      if acc then
        if q_wi = f_last then
          req_v <= '0';
        else
          q_wi <= q_wi + 1;
          req_a <= full_addr(f_buf, q_row, q_wi + 1);
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
        elsif not acc and gv = '1' then
          startf := true;
        end if;
      end if;

      if startf then
        pend <= '0';
        gv   <= '0';
        if g_480 then
          -- start of vertical blank: latch the next frame's picture
          f_en <= enable;
          if enable = '1' then
            f_buf <= buf;
            f_w <= width;
            f_h <= height;
            if height > V_ACTIVE then
              f_yoff <= shift_right(height - V_ACTIVE, 1);
            else
              f_yoff <= (others => '0');
            end if;
            if width > H_ACTIVE then ww := to_unsigned(H_ACTIVE, 11); else ww := width; end if;
            ww := shift_right(ww + 3, 2);
            if ww = 0 then f_last <= (others => '0'); else f_last <= resize(ww - 1, 8); end if;
          end if;
        elsif g_lt then
          if pend_ln(0) = '1' then h := 1; else h := 0; end if;
          if f_en = '1' and g_row < f_h and f_w /= 0 then
            li_on(h) <= '1';
            li_w(h)  <= f_w;
            q_row <= g_row(9 downto 0);
            q_wi  <= (others => '0');
            r_wi  <= (others => '0');
            if h = 1 then r_h <= '1'; else r_h <= '0'; end if;
            req_v <= '1';
            req_a <= full_addr(f_buf, g_row(9 downto 0), (others => '0'));
          else
            li_on(h) <= '0';
          end if;
        end if;
      end if;

      -- line setup for pend_ln (used by startf from the next cycle on)
      g_480 <= pend_ln = V_ACTIVE;
      g_lt  <= pend_ln < V_ACTIVE;
      g_row <= resize(pend_ln, 11) + f_yoff;
    end if;
  end process;

  ---------------------------------------------------------------- clk_pix render
  process (clk_pix)
    variable s : natural range 0 to 3;
  begin
    if rising_edge(clk_pix) then
      if x = 0 then
        if y >= LINE_LAST then p_line <= (others => '0');
        else p_line <= resize(y + 1, 10); end if;
        p_tog <= not p_tog;
      end if;
      if x = LATCH_X then
        c_h  <= p_line(0);
        c_on <= li_on(to_integer(p_line(0 downto 0)));
        c_w  <= li_w(to_integer(p_line(0 downto 0)));
      end if;
      -- stage 1: buffer address
      if de = '1' and c_on = '1' and x < c_w and x < H_ACTIVE then s1_on <= '1'; else s1_on <= '0'; end if;
      s1_addr <= c_h & x(9 downto 2);
      s1_sub  <= x(1 downto 0);
      -- stage 2: buffer read
      s2_q <= lb(to_integer(s1_addr));
      s2_on <= s1_on; s2_sub <= s1_sub;
      -- stage 3: pixel
      s := to_integer(s2_sub);
      if s2_on = '1' then s3_rgb <= s2_q(32 * s + 23 downto 32 * s);
      else s3_rgb <= (others => '0'); end if;
      -- stage 4: output register
      s4_rgb <= s3_rgb;
    end if;
  end process;
  r <= s4_rgb(23 downto 16);
  g <= s4_rgb(15 downto 8);
  b <= s4_rgb(7 downto 0);
  layer_on <= c_on;
end architecture;
