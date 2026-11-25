-- tb_kbd_led_status: power LED colour codes and the "not connected" pulse.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kbd_led_status is
end entity;

architecture tb of tb_kbd_led_status is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal dut_leds : std_logic_vector(95 downto 0) := x"AAAAAAAAAAAA" & x"123456789ABC";
  signal conn : std_logic := '1';
  signal machine : unsigned(4 downto 0) := (others => '0');
  signal leds : std_logic_vector(95 downto 0);
begin
  clk <= not clk after 4 ns when not done;
  dut : entity work.kbd_led_status generic map (PULSE_BITS => 10)
    port map (clk, dut_leds, conn, machine, leds);
  process
    procedure expect(k : natural; rgb : std_logic_vector(23 downto 0)) is
    begin
      machine <= to_unsigned(k, 5);
      wait until rising_edge(clk); wait until rising_edge(clk);
      assert leds(95 downto 72) = rgb and leds(71 downto 48) = rgb
        report "machine " & integer'image(k) & ": " & to_hstring(leds(71 downto 48)) severity failure;
      assert leds(47 downto 0) = dut_leds(47 downto 0) report "drive LEDs not passed" severity failure;
    end procedure;
    variable lo, hi : natural;
  begin
    expect(0, x"0000FF"); expect(3, x"00FF00"); expect(6, x"FFFFFF");
    expect(7, x"00007F"); expect(10, x"007F00"); expect(13, x"7F7F7F");
    expect(14, x"0000FF");
    conn <= '0';
    wait until rising_edge(clk); wait until rising_edge(clk);
    lo := 255; hi := 0;
    for i in 0 to 1100 loop
      wait until rising_edge(clk);
      assert leds(71 downto 56) = x"0000" report "pulse not red" severity failure;
      if to_integer(unsigned(leds(55 downto 48))) < lo then lo := to_integer(unsigned(leds(55 downto 48))); end if;
      if to_integer(unsigned(leds(55 downto 48))) > hi then hi := to_integer(unsigned(leds(55 downto 48))); end if;
    end loop;
    assert lo = 0 and hi = 127 report "pulse range " & integer'image(lo) & ".." & integer'image(hi) severity failure;
    report "tb_kbd_led_status PASSED";
    done <= true;
    wait;
  end process;
end architecture;
