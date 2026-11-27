-- text_display: 80x25 text renderer with three screens (ADR 0012, issue 0029).
--
-- Screens: 0 editable (host-written, blue), 1 no video (green), 2 select
-- (black; the ten machine boxes are an FPGA overlay, see below). The screen
-- shown is the `screen` input. Each screen has its own chars, attrs and
-- 16-colour palette.
-- Write port (any clock, e.g. clk_rx from text_rx_tap), address
-- screen(14:13) & offset(12:0):
--   0x0000-0x07CF characters, 0x0800-0x0FCF attributes (lo nibble fg, hi bg),
--   0x1000-0x102F palette (16 x R,G,B), 0x1030 control (screen 0 only).
-- Select-screen overlay: rows 11-13, ten 5-cell boxes in keyboard order
-- 1 2 .. 9 0 (machines 0..9), background = that machine's power-LED colour
-- (palette of screen 2), digit replaced by a frowning face (code 0x7F,
-- drawn into the font here) when slots(k) = '0'.
-- Live-thumbnail select screen (issue 0036): when mos_on = '1' (from
-- mosaic_display, DDR3 calibrated) the select screen is rearranged over the
-- thumbnail mosaic: each tile's digit (or frown) sits in a 3-cell
-- reverse-video box in the LED colour at the tile's top-left corner
-- (mosaic_pkg); every other cell's background is key green (palette entry
-- 8 of screen 2 = MOS_KEY) and the RAM text is limited to the title, hint
-- and footer rows outside the 4x3 block (none in the 2x2 layout). Output
-- pixels of exactly MOS_KEY, and pixels outside the text area, show the
-- mosaic layer (mos_r/g/b, aligned to stage E: valid 4 clocks after x/y).
-- Without mos_on the select screen is the boxes-only one above.
-- Read side runs on clk_pix: 9x16 cells (VGA style: column 9 repeats column 8
-- for codes 0xC0-0xDF so box drawing joins), text area centred in the raster.
-- Pipeline (5 clocks): counters -> address -> char/attr RAM -> font ROM -> RGB.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
-- Font: Terminus-derived, SIL OFL 1.1 (third_party/fonts); 0x7F replaced.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.font8x16_pkg.all;
use work.mosaic_pkg.all;

entity text_display is
  generic (
    TOP    : natural := 40;     -- first text line ((480 - 400) / 2)
    LEFT   : natural := 0;      -- first text pixel column
    MESSAGE : string := "No video source found";   -- screen 1, centred reverse box
    TITLE   : string := "Select device under test to connect to";  -- screen 2
    FOOTER  : string := "MEGA KVM";                -- lower left (product/version/build)
    VISIBLE : natural := 78                        -- columns the monitor shows
  );
  port (
    -- write side
    wr_clk  : in  std_logic;
    wr_en   : in  std_logic;
    wr_addr : in  unsigned(14 downto 0);
    wr_data : in  std_logic_vector(7 downto 0);
    -- video side
    clk_pix : in  std_logic;
    x, y    : in  unsigned(10 downto 0);
    de_in, hs_in, vs_in : in std_logic;
    r, g, b : out std_logic_vector(7 downto 0);
    de_out, hs_out, vs_out : out std_logic;
    force_text   : out std_logic;        -- control bit 0
    screen  : in  unsigned(1 downto 0) := "00";            -- any clock, quasi-static
    slots   : in  std_logic_vector(9 downto 0) := (others => '0');  -- machine k present
    -- thumbnail layer (issue 0036), clk_pix
    mos_on   : in  std_logic := '0';
    mos_quad : in  std_logic := '0';
    mos_r, mos_g, mos_b : in std_logic_vector(7 downto 0) := (others => '0');
    -- full-resolution relayed picture (full_display, issue 0060): replaces
    -- the whole screen while full_on (aligned as the mosaic layer)
    full_on  : in  std_logic := '0';
    full_r, full_g, full_b : in std_logic_vector(7 downto 0) := (others => '0')
  );
end entity;

architecture rtl of text_display is
  type ram_t is array (0 to 8191) of std_logic_vector(7 downto 0);   -- screen & 11 bits

  constant BOX_W : natural := MESSAGE'length + 8;
  constant BOX_X : natural := (VISIBLE - BOX_W) / 2;
  constant BOX_Y : natural := 11;
  constant OV_X  : natural := (VISIBLE - 68) / 2;    -- select boxes: 10 x 5 cells, gap 2
  -- live select screen: corner boxes (3 cells) and the RAM rows it shows
  type nat_arr is array (natural range <>) of natural;
  constant BCQ : nat_arr(0 to 1) := (mos_box_col(LEFT, true, 0), mos_box_col(LEFT, true, 1));
  constant BRQ : nat_arr(0 to 1) := (mos_box_row(TOP, true, 0), mos_box_row(TOP, true, 1));
  constant BCD : nat_arr(0 to 3) := (mos_box_col(LEFT, false, 0), mos_box_col(LEFT, false, 1),
                                     mos_box_col(LEFT, false, 2), mos_box_col(LEFT, false, 3));
  constant BRD : nat_arr(0 to 2) := (mos_box_row(TOP, false, 0), mos_box_row(TOP, false, 1),
                                     mos_box_row(TOP, false, 2));
  constant SEL_TITLE_ROW : natural := 7;   -- RAM rows of the select screen's text
  constant SEL_HINT_ROW  : natural := 16;
  constant KEY_IDX       : std_logic_vector(3 downto 0) := x"8";
  function ch(c : character) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function;
  procedure put(variable m : inout ram_t; scr, row, col : natural; t : string) is
  begin
    for i in t'range loop
      m(scr * 2048 + row * 80 + col + i - t'low) := ch(t(i));
    end loop;
  end procedure;
  function init_chars return ram_t is
    variable m : ram_t := (others => x"20");
  begin
    for scr in 0 to 2 loop
      put(m, scr, 24, 1, FOOTER);
    end loop;
    put(m, 1, BOX_Y + 1, BOX_X + 4, MESSAGE);
    put(m, 2, 7, (VISIBLE - TITLE'length) / 2, TITLE);
    put(m, 2, 16, (VISIBLE - 40) / 2, "Press 1-9 or 0 to choose, ESC to cancel");
    return m;
  end function;
  function init_attrs return ram_t is
    variable m : ram_t := (others => x"00");
  begin
    for i in 0 to 2047 loop
      m(i)        := x"1F";                          -- 0: white on blue
      m(2048 + i) := x"20";                          -- 1: black on green
      m(4096 + i) := x"07";                          -- 2: white on black
    end loop;
    for r in BOX_Y to BOX_Y + 2 loop
      for c in BOX_X to BOX_X + BOX_W - 1 loop
        m(2048 + r * 80 + c) := x"02";               -- green on black box
      end loop;
    end loop;
    return m;
  end function;

  signal chars : ram_t := init_chars;
  signal attrs : ram_t := init_attrs;
  attribute ram_style : string;
  attribute ram_style of chars, attrs : signal is "block";  -- issue 0019

  type pal_t is array (0 to 143) of std_logic_vector(7 downto 0);   -- 3 x 16 x RGB
  constant VGA : pal_t := (
    x"00", x"00", x"00",  x"00", x"00", x"AA",  x"00", x"AA", x"00",  x"00", x"AA", x"AA",
    x"AA", x"00", x"00",  x"AA", x"00", x"AA",  x"AA", x"55", x"00",  x"AA", x"AA", x"AA",
    x"55", x"55", x"55",  x"55", x"55", x"FF",  x"55", x"FF", x"55",  x"55", x"FF", x"FF",
    x"FF", x"55", x"55",  x"FF", x"55", x"FF",  x"FF", x"FF", x"55",  x"FF", x"FF", x"FF",
    others => x"00");
  -- select screen: 0 black, 1-7 the power-LED colours (red orange yellow
  -- green blue purple white), 8 key green (MOS_KEY, issue 0036), 9-15 the
  -- same at half brightness. LED green is 0x00FE00 so it is never keyed.
  constant SEL : pal_t := (
    x"00", x"00", x"00",  x"FF", x"00", x"00",  x"FF", x"60", x"00",  x"FF", x"C0", x"00",
    x"00", x"FE", x"00",  x"00", x"00", x"FF",  x"A0", x"00", x"FF",  x"FF", x"FF", x"FF",
    x"00", x"FF", x"00",  x"7F", x"00", x"00",  x"7F", x"30", x"00",  x"7F", x"60", x"00",
    x"00", x"7F", x"00",  x"00", x"00", x"7F",  x"50", x"00", x"7F",  x"7F", x"7F", x"7F",
    others => x"00");
  function init_pal return pal_t is
    variable p : pal_t;
  begin
    for i in 0 to 47 loop
      p(i) := VGA(i); p(48 + i) := VGA(i); p(96 + i) := SEL(i);
    end loop;
    return p;
  end function;
  signal pal : pal_t := init_pal;
  signal ctrl : std_logic_vector(7 downto 0) := x"00";

  -- frowning face for "no device" (owner 2026-11-25), replaces code 0x7F
  type glyph_t is array (0 to 15) of std_logic_vector(7 downto 0);
  constant FROWN : glyph_t := (x"00", x"00", x"7E", x"81", x"A5", x"81", x"81", x"81",
                               x"99", x"A5", x"C3", x"81", x"7E", x"00", x"00", x"00");
  function patched_font return font_array_t is
    variable f : font_array_t := FONT8X16;
  begin
    for r in 0 to 15 loop     -- interlaced: row(0) & code & row(3:1)
      f((r mod 2) * 2048 + 16#7F# * 8 + r / 2) := FROWN(r);
    end loop;
    return f;
  end function;
  signal font : font_array_t := patched_font;
  -- screen / slots into clk_pix (quasi-static)
  signal scr_s1, scr_s2 : unsigned(1 downto 0) := "00";
  signal slot_s1, slot_s2 : std_logic_vector(9 downto 0) := (others => '0');
  signal ov_c, ovin_b, ovdig_b : std_logic := '0';
  signal ovk_b : integer range 0 to 9 := 0;
  signal ovch_c, ovat_c : std_logic_vector(7 downto 0) := (others => '0');

  -- pipeline: A counters, B address, C RAM, D font, E pixel
  signal col     : unsigned(6 downto 0) := (others => '0');
  signal cx      : unsigned(3 downto 0) := (others => '0');
  signal row     : unsigned(4 downto 0) := (others => '0');
  signal cy      : unsigned(3 downto 0) := (others => '0');
  signal in_a, in_b, in_c, in_d : std_logic := '0';
  signal addr_b  : unsigned(10 downto 0) := (others => '0');
  signal cx_b, cx_c, cx_d, cy_b, cy_c : unsigned(3 downto 0) := (others => '0');
  signal ch_c, at_c, ch_d, at_d, font_d : std_logic_vector(7 downto 0) := (others => '0');
  signal de_d, hs_d, vs_d : std_logic_vector(4 downto 0) := (others => '0');
  signal scr_d : unsigned(1 downto 0) := "00";
  signal mm_b, mm_c, mm_d, mbl_b, mbl_c, mk_c : std_logic := '0';
begin
  force_text <= ctrl(0);

  ---------------------------------------------------------------- writes
  process (wr_clk)
    variable a  : natural;
    variable sc : natural range 0 to 3;
  begin
    if rising_edge(wr_clk) then
      if wr_en = '1' and wr_addr(14 downto 13) /= "11" then
        sc := to_integer(wr_addr(14 downto 13));
        a  := to_integer(wr_addr(12 downto 0));
        if wr_addr(12 downto 11) = "00" then
          chars(sc * 2048 + a mod 2048) <= wr_data;
        elsif wr_addr(12 downto 11) = "01" then
          attrs(sc * 2048 + a mod 2048) <= wr_data;
        elsif a >= 16#1000# and a < 16#1030# then
          pal(sc * 48 + a - 16#1000#) <= wr_data;
        elsif a = 16#1030# and sc = 0 then
          ctrl <= wr_data;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- render
  process (clk_pix)
    variable bitv   : std_logic;
    variable fg, bg : natural;
    variable pb     : natural range 0 to 143;
    variable k      : integer range 0 to 9;
    variable inbox  : boolean;
    variable chx    : std_logic_vector(7 downto 0);
    variable mm, blank, dig : boolean;
    variable rrow   : unsigned(4 downto 0);
    variable c      : std_logic_vector(23 downto 0);
  begin
    if rising_edge(clk_pix) then
      scr_s1 <= screen; scr_s2 <= scr_s1;
      slot_s1 <= slots; slot_s2 <= slot_s1;
      -- A: cell counters for the pixel (x, y) presented this cycle
      if x = LEFT then
        col <= (others => '0'); cx <= (others => '0');
      elsif cx = 8 then
        cx <= (others => '0'); col <= col + 1;
      else
        cx <= cx + 1;
      end if;
      if x = 0 then
        if y = TOP then
          row <= (others => '0'); cy <= (others => '0');
        elsif cy = 15 then
          cy <= (others => '0'); row <= row + 1;
        else
          cy <= cy + 1;
        end if;
      end if;
      if de_in = '1' and x >= LEFT and x < LEFT + 720 and y >= TOP and y < TOP + 400 then
        in_a <= '1';
      else
        in_a <= '0';
      end if;

      -- B: address; select-screen overlay decided from row/col
      mm := mos_on = '1' and scr_s2 = "10";
      rrow := row; blank := false;
      if mm then
        -- live select screen: only title/hint/footer rows show RAM text (4x3)
        if mos_quad = '1' then blank := true;
        elsif row = 1 then rrow := to_unsigned(SEL_TITLE_ROW, 5);
        elsif row = 23 then rrow := to_unsigned(SEL_HINT_ROW, 5);
        elsif row /= 24 then blank := true;
        end if;
      end if;
      addr_b <= resize(rrow & "000000", 11) + resize(rrow & "0000", 11) + resize(col, 11);
      cx_b <= cx; cy_b <= cy; in_b <= in_a;
      inbox := false; k := 0; dig := false;
      if mm then
        if mos_quad = '1' then
          for j in 0 to 1 loop
            for i in 0 to 1 loop
              if row = BRQ(j) and col >= BCQ(i) and col <= BCQ(i) + 2 then
                inbox := true; k := 2 * j + i; dig := col = BCQ(i) + 1;
              end if;
            end loop;
          end loop;
        else
          for j in 0 to 2 loop
            for i in 0 to 3 loop
              if 4 * j + i <= 9 and row = BRD(j) and col >= BCD(i) and col <= BCD(i) + 2 then
                inbox := true; k := 4 * j + i; dig := col = BCD(i) + 1;
              end if;
            end loop;
          end loop;
        end if;
      elsif scr_s2 = "10" and row >= 11 and row <= 13 then
        for i in 0 to 9 loop
          if col >= OV_X + 7 * i and col <= OV_X + 7 * i + 4 then
            inbox := true; k := i;
          end if;
        end loop;
        dig := row = 12 and col = OV_X + 7 * k + 2;
      end if;
      ovin_b  <= '1' when inbox else '0';
      ovk_b   <= k;
      ovdig_b <= '1' when inbox and dig else '0';
      mm_b    <= '1' when mm else '0';
      mbl_b   <= '1' when blank else '0';

      -- C: character / attribute RAM (screen chosen by scr_s2)
      ch_c <= chars(to_integer(scr_s2(1 downto 0) & addr_b));
      at_c <= attrs(to_integer(scr_s2(1 downto 0) & addr_b));
      cx_c <= cx_b; cy_c <= cy_b; in_c <= in_b;
      mm_c <= mm_b; mbl_c <= mbl_b;
      ov_c <= '0';
      k := ovk_b;
      if ovin_b = '1' then
        ov_c <= '1';
        -- background: power-LED colour (1-7 full, 9-11 half for machines 7-9);
        -- digit black on bright colours, white on dark ones
        if k < 7 then
          if k = 4 or k = 5 then ovat_c <= std_logic_vector(to_unsigned(k + 1, 4)) & x"7";
          else ovat_c <= std_logic_vector(to_unsigned(k + 1, 4)) & x"0"; end if;
        else
          ovat_c <= std_logic_vector(to_unsigned(k + 2, 4)) & x"7";
        end if;
        ovch_c <= x"20";
        if ovdig_b = '1' then
          if slot_s2(k) = '0' then ovch_c <= x"7F";
          elsif k = 9 then ovch_c <= x"30";                         -- '0'
          else ovch_c <= std_logic_vector(to_unsigned(16#31# + k, 8)); end if;
        end if;
      end if;

      -- D: font ROM (interlaced layout: row(0) & code & row(3:1))
      if ov_c = '1' then chx := ovch_c; at_d <= ovat_c;
      elsif mm_c = '1' then
        -- live select screen: RAM text (or blank) on key green
        if mbl_c = '1' then chx := x"20"; else chx := ch_c; end if;
        at_d <= KEY_IDX & at_c(3 downto 0);
      else chx := ch_c; at_d <= at_c; end if;
      mm_d <= mm_c;
      font_d <= font(to_integer(cy_c(0) & unsigned(chx) & cy_c(3 downto 1)));
      ch_d <= chx; cx_d <= cx_c; in_d <= in_c; scr_d <= scr_s2;

      -- E: pixel and palette
      if cx_d < 8 then
        bitv := font_d(7 - to_integer(cx_d(2 downto 0)));
      elsif unsigned(ch_d) >= 16#C0# and unsigned(ch_d) <= 16#DF# then
        bitv := font_d(0);
      else
        bitv := '0';
      end if;
      fg := to_integer(unsigned(at_d(3 downto 0)));
      bg := to_integer(unsigned(at_d(7 downto 4)));
      pb := 48 * to_integer(scr_d);
      if in_d = '0' then
        c := x"000000";
      elsif bitv = '1' then
        c := pal(pb + 3 * fg) & pal(pb + 3 * fg + 1) & pal(pb + 3 * fg + 2);
      else
        c := pal(pb + 3 * bg) & pal(pb + 3 * bg + 1) & pal(pb + 3 * bg + 2);
      end if;
      -- issue 0036: key green and the area outside the text show the mosaic
      if mm_d = '1' and (in_d = '0' or c = MOS_KEY) then
        c := mos_r & mos_g & mos_b;
      end if;
      if full_on = '1' then
        c := full_r & full_g & full_b;
      end if;
      r <= c(23 downto 16); g <= c(15 downto 8); b <= c(7 downto 0);

      de_d <= de_d(3 downto 0) & de_in;
      hs_d <= hs_d(3 downto 0) & hs_in;
      vs_d <= vs_d(3 downto 0) & vs_in;
    end if;
  end process;
  de_out <= de_d(4);
  hs_out <= hs_d(4);
  vs_out <= vs_d(4);
end architecture;
