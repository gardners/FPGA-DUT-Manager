-- kbd_led_status: physical keyboard LED vector (owner 2026-11-25).
-- Drive LEDs (0, 1) show the selected DUT's own LEDs. The power LED (LEDs 2
-- and 3) shows which machine the keyboard is connected to:
--   not connected (selected DUT not sensed powered): slow gentle red pulse;
--   machine k = 0..6: red, orange, yellow, green, blue, purple, white;
--   k = 7..13 the same colours at half brightness (k mod 14 beyond that);
--   selecting (KVM hotkey, issue 0029): double red blink - 100 ms on, 100 ms
--   off, 100 ms on, 800 ms off - overriding the above.
-- LED layout as mega65kbd_to_matrix: LED n = bits 24n+23..24n, R in 7..0,
-- G in 15..8, B in 23..16.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_led_status is
  generic (
    PULSE_BITS : positive := 28;            -- 2^28 / 125 MHz = 2.1 s per pulse
    MS_CYCLES  : positive := 125_000        -- clocks per ms (blink pattern)
  );
  port (
    clk       : in  std_logic;
    dut_leds  : in  std_logic_vector(95 downto 0);
    connected : in  std_logic;
    machine   : in  unsigned(4 downto 0);
    selecting : in  std_logic := '0';
    leds      : out std_logic_vector(95 downto 0)
  );
end entity;

architecture rtl of kbd_led_status is
  type rgb_arr_t is array (0 to 6) of std_logic_vector(23 downto 0);
  -- B & G & R
  constant COLOURS : rgb_arr_t := (
    x"0000FF",   -- red
    x"0060FF",   -- orange
    x"00C0FF",   -- yellow
    x"00FF00",   -- green
    x"FF0000",   -- blue
    x"FF00A0",   -- purple
    x"FFFFFF");  -- white
  signal cnt : unsigned(PULSE_BITS - 1 downto 0) := (others => '0');
  signal pwr : std_logic_vector(23 downto 0) := (others => '0');
  signal msc : integer range 0 to MS_CYCLES - 1 := 0;
  signal ms  : integer range 0 to 1099 := 0;
begin
  leds <= pwr & pwr & dut_leds(47 downto 0);

  process (clk)
    variable k   : integer range 0 to 31;
    variable c   : std_logic_vector(23 downto 0);
    variable tri : unsigned(6 downto 0);
  begin
    if rising_edge(clk) then
      cnt <= cnt + 1;
      if msc = MS_CYCLES - 1 then
        msc <= 0;
        if ms = 1099 then ms <= 0; else ms <= ms + 1; end if;
      else
        msc <= msc + 1;
      end if;
      if selecting = '1' then
        if ms < 100 or (ms >= 200 and ms < 300) then pwr <= x"0000FF"; else pwr <= x"000000"; end if;
      elsif connected = '1' then
        k := to_integer(machine) mod 14;
        c := COLOURS(k mod 7);
        if k >= 7 then                -- half brightness
          c := '0' & c(23 downto 17) & '0' & c(15 downto 9) & '0' & c(7 downto 1);
        end if;
        pwr <= c;
      else
        -- triangle 0..127..0 from the top bits: gentle red, max half brightness
        if cnt(cnt'high) = '0' then
          tri := cnt(cnt'high - 1 downto cnt'high - 7);
        else
          tri := not cnt(cnt'high - 1 downto cnt'high - 7);
        end if;
        pwr <= x"0000" & '0' & std_logic_vector(tri);
      end if;
    end if;
  end process;
end architecture;
