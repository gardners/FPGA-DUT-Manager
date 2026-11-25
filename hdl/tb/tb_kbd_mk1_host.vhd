-- tb_kbd_mk1_host: our MK-I host reading our MK-I device emulator (both at
-- 125 MHz) -- the same pairing as a physical MK-I keyboard on the master.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kbd_mk1_host is
end entity;

architecture tb of tb_kbd_mk1_host is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal keys : std_logic_vector(79 downto 0) := (others => '0');
  signal kio8, kio9, kio10 : std_logic;
  signal dev_leds, host_leds : std_logic_vector(95 downto 0);
  signal dstb, hstb, present : std_logic;
  signal frames : unsigned(15 downto 0);
  signal pressed : std_logic_vector(79 downto 0);
  signal commit : std_logic_vector(31 downto 0);
  type pat_t is array (natural range <>) of std_logic_vector(79 downto 0);
  constant PATS : pat_t := (x"00000000000000000000", x"00000000000000000001",
                            x"00000000000000000002", x"005A_A5C3_3C96_6912_4800",
                            x"00F0_0000_0000_0000_FFFC", x"0000_8000_0000_0000_0010");
begin
  clk <= not clk after 4 ns when not done;
  host_leds <= x"123456_789ABC_DEF012_345678";

  dev : entity work.kbd_mk1_device
    port map (clk => clk, keys_pressed => keys, kio8_in => kio8, kio9_in => kio9,
              kio10_out => kio10, leds => dev_leds, leds_strobe => dstb, frame_count => frames);
  host : entity work.kbd_mk1_host
    port map (clk => clk, kio8 => kio8, kio9 => kio9, kio10 => kio10, leds => host_leds,
              pressed => pressed, strobe => hstb, present => present, kbd_commit => commit);

  process
    variable want : std_logic_vector(79 downto 0);
    procedure scans(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk) and hstb = '1'; end loop;
    end procedure;
  begin
    scans(2);
    for p in PATS'range loop
      keys <= PATS(p);
      scans(3);
      want := PATS(p);
      -- the keyboard duplicates DEL/RETURN at 76/77
      want(76) := PATS(p)(0);
      want(77) := PATS(p)(1);
      assert pressed = want
        report "pattern " & integer'image(p) & ": got " & to_hstring(pressed) &
               " want " & to_hstring(want) severity failure;
    end loop;
    assert present = '1' report "MK-I not detected" severity failure;
    assert commit = x"53555056" report "commit id " & to_hstring(commit) severity failure;
    -- LED data: the device stores it bit-reversed (as mk2_to_mk1 does)
    for i in 0 to 95 loop
      assert dev_leds(i) = host_leds(95 - i) report "LED bit " & integer'image(i) severity failure;
    end loop;
    report "tb_kbd_mk1_host PASSED";
    done <= true;
    wait;
  end process;
end architecture;
