-- tb_kbd_phys_host: MK-I / MK-II auto-detection. The same keyboard port is
-- left empty, then given an MK-II keyboard (TCA9555 models, KIO10 tied
-- low), an MK-I keyboard (our kbd_mk1_device, KIO10 high at idle), the MK-II
-- again and finally nothing. Pins have pull-ups on KIO8/KIO9 (XDC PULLUP)
-- and a pull-down on KIO10, as on the board.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kbd_phys_host is
end entity;

architecture tb of tb_kbd_phys_host is
  -- must exceed the longest run of '0' bits in an MK-I frame (the 14-bit
  -- date stamp plus neighbours, 400 clocks per bit): use the real value
  constant DETECT : positive := 15432;
  type kbd_t is (NONE, MK1, MK2);
  signal attached : kbd_t := NONE;
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal pin8, pin9, pin10 : std_logic;
  signal k8o, k8oe, k9o, k9oe : std_logic;
  signal dev_kio10 : std_logic;
  signal leds    : std_logic_vector(95 downto 0) := x"123456_789ABC_DEF012_345678";
  signal pressed : std_logic_vector(79 downto 0);
  signal strobe  : std_logic;
  signal ktype   : std_logic_vector(1 downto 0);
  signal commit  : std_logic_vector(31 downto 0);
  signal dev_keys : std_logic_vector(79 downto 0) := (others => '0');
  signal dev_leds : std_logic_vector(95 downto 0);
  signal dev_stb  : std_logic;
  signal frames   : unsigned(15 downto 0);
  signal mk2_conn : std_logic;
  type slv16_arr is array (0 to 5) of std_logic_vector(15 downto 0);
  signal pins : slv16_arr := (others => (others => '1'));
begin
  clk <= not clk after 4 ns when not done;

  pin8 <= 'H'; pin9 <= 'H'; pin10 <= 'L';
  pin8 <= k8o when k8oe = '1' else 'Z';
  pin9 <= k9o when k9oe = '1' else 'Z';
  pin10 <= dev_kio10 when attached = MK1 else
           '0' when attached = MK2 else 'Z';
  mk2_conn <= '1' when attached = MK2 else '0';

  dut : entity work.kbd_phys_host
    generic map (MK2_QUARTER_CYCLES => 8, MK2_DETECT_CYCLES => DETECT,
                 MK2_REINIT_LOG2 => 4, MK2_CAPS_HOLD => 20)
    port map (clk => clk, kio8_o => k8o, kio8_oe => k8oe, kio8_i => to_X01(pin8),
              kio9_o => k9o, kio9_oe => k9oe, kio10 => to_X01(pin10), leds => leds,
              pressed => pressed, strobe => strobe, kbd_type => ktype,
              kbd_commit => commit);

  mk1dev : entity work.kbd_mk1_device
    port map (clk => clk, keys_pressed => dev_keys, kio8_in => to_X01(pin8),
              kio9_in => to_X01(pin9), kio10_out => dev_kio10, leds => dev_leds,
              leds_strobe => dev_stb, frame_count => frames);

  exp_g : for i in 0 to 5 generate
    u : entity work.i2c_expander_model
      generic map (ADDR => "0100" & std_logic_vector(to_unsigned(i, 3)))
      port map (sda => pin8, scl => pin9, connected => mk2_conn, pins => pins(i),
                out_regs => open, cfg_regs => open, cfg_writes => open,
                out_writes => open, reads => open, errors => open);
  end generate;

  process
    variable want : std_logic_vector(79 downto 0);
    procedure scans(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk) and strobe = '1'; end loop;
    end procedure;
    procedure check_type(t : std_logic_vector(1 downto 0); msg : string) is
    begin
      assert ktype = t report msg & ": type " & to_string(ktype) & " want " & to_string(t)
        severity failure;
    end procedure;
  begin
    -- nothing attached: MK-II scanning, no ACKs
    wait for 300 us;
    check_type("00", "empty port");
    assert pressed = (79 downto 0 => '0') report "keys from an empty port" severity failure;
    assert k8o = '0' and k9o = '0' report "MK-II pins not open drain" severity failure;

    -- MK-II keyboard
    attached <= MK2;
    pins(3)(0) <= '0';                     -- HELP (67)
    scans(3);
    check_type("10", "MK-II");
    want := (others => '0'); want(67) := '1';
    assert pressed = want report "MK-II keys " & to_hstring(pressed) severity failure;
    assert commit = x"4D4B4949" report "MK-II commit id" severity failure;

    -- MK-I keyboard: KIO10 high selects MK-I at once
    attached <= MK1;
    dev_keys <= (5 => '1', 60 => '1', 0 => '1', others => '0');
    wait for 1 us;
    check_type("01", "MK-I");
    assert k8oe = '1' and k9oe = '1' report "MK-I pins not driven" severity failure;
    scans(3);
    want := (5 => '1', 60 => '1', 0 => '1', 76 => '1', others => '0');
    assert pressed = want report "MK-I keys " & to_hstring(pressed) severity failure;
    assert commit = x"53555056" report "MK-I commit id " & to_hstring(commit) severity failure;
    check_type("01", "MK-I kept while scanning");
    for i in 0 to 95 loop
      assert dev_leds(i) = leds(95 - i) report "MK-I LED bit " & integer'image(i) severity failure;
    end loop;

    -- back to MK-II: KIO10 low for DETECT cycles
    attached <= MK2;
    for i in 1 to DETECT / 2 loop wait until rising_edge(clk); end loop;
    check_type("01", "MK-I kept before the detect time");
    wait for 150 us;                       -- past the detect time
    pins(3)(0) <= '1'; pins(5)(0) <= '0';  -- F1 (4)
    scans(3);
    check_type("10", "MK-II again");
    want := (others => '0'); want(4) := '1';
    assert pressed = want report "MK-II keys again " & to_hstring(pressed) severity failure;

    -- unplugged
    attached <= NONE;
    scans(2);
    check_type("00", "unplugged");
    assert pressed = (79 downto 0 => '0') report "keys after unplug" severity failure;
    report "tb_kbd_phys_host PASSED";
    done <= true;
    wait;
  end process;
end architecture;
