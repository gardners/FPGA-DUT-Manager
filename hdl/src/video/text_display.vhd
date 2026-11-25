-- text_display: 80x25 text renderer with its own memories (ADR 0012).
--
-- Write port (any clock, e.g. clk_rx from text_rx_tap):
--   0x0000-0x07CF characters, 0x0800-0x0FCF attributes (lo nibble fg, hi bg),
--   0x1000-0x102F palette (16 x R,G,B), 0x1030 control.
-- Read side runs on clk_pix: 9x16 cells (VGA style: column 9 repeats column 8
-- for codes 0xC0-0xDF so box drawing joins), text area centred in the raster.
-- Pipeline (5 clocks): counters -> address -> char/attr RAM -> font ROM -> RGB.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
-- Font: Terminus-derived, SIL OFL 1.1 (third_party/fonts).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.font8x16_pkg.all;

entity text_display is
  generic (
    TOP    : natural := 40;     -- first text line ((480 - 400) / 2)
    LEFT   : natural := 0;      -- first text pixel column
    MESSAGE : string := "No video source found";   -- centred, reverse video box
    FOOTER  : string := "MEGA KVM";                -- lower left (product/version/build)
    VISIBLE : natural := 78                        -- columns the monitor shows
  );
  port (
    -- write side
    wr_clk  : in  std_logic;
    wr_en   : in  std_logic;
    wr_addr : in  unsigned(12 downto 0);
    wr_data : in  std_logic_vector(7 downto 0);
    -- video side
    clk_pix : in  std_logic;
    x, y    : in  unsigned(10 downto 0);
    de_in, hs_in, vs_in : in std_logic;
    r, g, b : out std_logic_vector(7 downto 0);
    de_out, hs_out, vs_out : out std_logic;
    force_text   : out std_logic         -- control bit 0
  );
end entity;

architecture rtl of text_display is
  type ram_t is array (0 to 2047) of std_logic_vector(7 downto 0);

  -- power-up screen (owner 2026-11-25): white on blue, MESSAGE centred in a
  -- 3-row reverse-video (blue on white) box, FOOTER in the lower left.
  constant BOX_W : natural := MESSAGE'length + 8;
  constant BOX_X : natural := (VISIBLE - BOX_W) / 2;
  constant BOX_Y : natural := 11;
  function ch(c : character) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function;
  function init_chars return ram_t is
    variable m : ram_t := (others => x"20");
  begin
    for i in MESSAGE'range loop
      m((BOX_Y + 1) * 80 + BOX_X + 4 + i - MESSAGE'low) := ch(MESSAGE(i));
    end loop;
    for i in FOOTER'range loop
      m(24 * 80 + 1 + i - FOOTER'low) := ch(FOOTER(i));
    end loop;
    return m;
  end function;
  function init_attrs return ram_t is
    variable m : ram_t := (others => x"1F");        -- white on blue
  begin
    for r in BOX_Y to BOX_Y + 2 loop
      for c in BOX_X to BOX_X + BOX_W - 1 loop
        m(r * 80 + c) := x"F1";                     -- blue on white
      end loop;
    end loop;
    return m;
  end function;

  signal chars : ram_t := init_chars;
  signal attrs : ram_t := init_attrs;
  attribute ram_style : string;
  attribute ram_style of chars, attrs : signal is "block";  -- issue 0019

  type pal_t is array (0 to 47) of std_logic_vector(7 downto 0);
  -- VGA 16-colour palette
  signal pal : pal_t := (
    x"00", x"00", x"00",  x"00", x"00", x"AA",  x"00", x"AA", x"00",  x"00", x"AA", x"AA",
    x"AA", x"00", x"00",  x"AA", x"00", x"AA",  x"AA", x"55", x"00",  x"AA", x"AA", x"AA",
    x"55", x"55", x"55",  x"55", x"55", x"FF",  x"55", x"FF", x"55",  x"55", x"FF", x"FF",
    x"FF", x"55", x"55",  x"FF", x"55", x"FF",  x"FF", x"FF", x"55",  x"FF", x"FF", x"FF");
  signal ctrl : std_logic_vector(7 downto 0) := x"00";

  signal font : font_array_t := FONT8X16;

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
begin
  force_text <= ctrl(0);

  ---------------------------------------------------------------- writes
  process (wr_clk)
    variable a : natural;
  begin
    if rising_edge(wr_clk) then
      if wr_en = '1' then
        a := to_integer(wr_addr);
        if wr_addr(12 downto 11) = "00" then
          chars(a mod 2048) <= wr_data;
        elsif wr_addr(12 downto 11) = "01" then
          attrs(a mod 2048) <= wr_data;
        elsif a >= 16#1000# and a < 16#1030# then
          pal(a - 16#1000#) <= wr_data;
        elsif a = 16#1030# then
          ctrl <= wr_data;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- render
  process (clk_pix)
    variable bitv   : std_logic;
    variable fg, bg : natural;
  begin
    if rising_edge(clk_pix) then
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

      -- B: address
      addr_b <= resize(row & "000000", 11) + resize(row & "0000", 11) + resize(col, 11);
      cx_b <= cx; cy_b <= cy; in_b <= in_a;

      -- C: character / attribute RAM
      ch_c <= chars(to_integer(addr_b));
      at_c <= attrs(to_integer(addr_b));
      cx_c <= cx_b; cy_c <= cy_b; in_c <= in_b;

      -- D: font ROM (interlaced layout: row(0) & code & row(3:1))
      font_d <= font(to_integer(cy_c(0) & unsigned(ch_c) & cy_c(3 downto 1)));
      ch_d <= ch_c; at_d <= at_c; cx_d <= cx_c; in_d <= in_c;

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
      if in_d = '0' then
        r <= x"00"; g <= x"00"; b <= x"00";
      elsif bitv = '1' then
        r <= pal(3 * fg); g <= pal(3 * fg + 1); b <= pal(3 * fg + 2);
      else
        r <= pal(3 * bg); g <= pal(3 * bg + 1); b <= pal(3 * bg + 2);
      end if;

      de_d <= de_d(3 downto 0) & de_in;
      hs_d <= hs_d(3 downto 0) & hs_in;
      vs_d <= vs_d(3 downto 0) & vs_in;
    end if;
  end process;
  de_out <= de_d(4);
  hs_out <= hs_d(4);
  vs_out <= vs_d(4);
end architecture;
