-- tb_kbd_phys_host: type-3 probe and MK-I / MK-II auto-detection on one
-- keyboard port (issues 0009, 0046). Pins have pull-ups on KIO8/KIO9 (XDC
-- PULLUP) and a pull-down on KIO10, as on the board.
--  1. MK-II (TCA9555 models, KIO10 tied low) attached from power-up: the
--     type-3 probe runs first and must not produce an I2C START or STOP
--     (SDA never changes while SCL is high); then MK-II is detected.
--  2. MK-I (our kbd_mk1_device, KIO10 high at idle): selected at once;
--     the periodic re-probe (no answer) leaves the published keys intact.
--  3. The type-3 keyboard CPLD firmware (megakey_t3 + key matrix model)
--     replaces it: first seen as MK-I, upgraded to type 3 by the next
--     re-probe; keys, commit id and LEDs over type 3.
--  4. Unplugged: type 3 lost -> probe -> legacy -> none.
--  5. MK-II again.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library machxo2;
use machxo2.osch_sim_pkg.all;

entity tb_kbd_phys_host is
end entity;

architecture tb of tb_kbd_phys_host is
  -- must exceed the longest run of '0' bits in an MK-I frame (the 14-bit
  -- date stamp plus neighbours, 400 clocks per bit): use the real value
  constant DETECT  : positive := 15432;
  constant REPROBE : positive := 375_000;      -- 3 ms
  type kbd_t is (NONE, MK1, MK2, T3);
  signal attached : kbd_t := MK2;
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal pin8, pin9, pin10 : std_logic;
  signal k8o, k8oe, k9o, k9oe : std_logic;
  signal dev_kio10, t3_kio10 : std_logic;
  signal leds    : std_logic_vector(95 downto 0) := x"123456_789ABC_DEF012_345678";
  signal pressed : std_logic_vector(79 downto 0);
  signal strobe  : std_logic;
  signal ktype   : std_logic_vector(1 downto 0);
  signal commit  : std_logic_vector(31 downto 0);
  signal probing : std_logic;
  signal dev_keys : std_logic_vector(79 downto 0) := (others => '0');
  signal dev_leds : std_logic_vector(95 downto 0);
  signal dev_stb  : std_logic;
  signal frames   : unsigned(15 downto 0);
  signal mk2_conn : std_logic;
  type slv16_arr is array (0 to 5) of std_logic_vector(15 downto 0);
  signal pins : slv16_arr := (others => (others => '1'));
  type nat_arr is array (0 to 5) of natural;
  signal i2c_err : nat_arr;
  signal so : std_logic_vector(9 downto 0);
  signal si : std_logic_vector(7 downto 0);
  signal mkeys : std_logic_vector(79 downto 0) := (others => '0');
  signal probe_conds, probes : natural := 0;
  signal watch   : std_logic_vector(79 downto 0) := (others => '0');
  signal watch_on : boolean := false;
begin
  clk <= not clk after 4 ns when not done;

  pin8 <= 'H'; pin9 <= 'H'; pin10 <= 'L';
  pin8 <= k8o when k8oe = '1' else 'Z';
  pin9 <= k9o when k9oe = '1' else 'Z';
  pin10 <= dev_kio10 when attached = MK1 else
           t3_kio10 when attached = T3 else
           '0' when attached = MK2 else 'Z';
  mk2_conn <= '1' when attached = MK2 else '0';

  dut : entity work.kbd_phys_host
    generic map (MK2_QUARTER_CYCLES => 8, MK2_DETECT_CYCLES => DETECT,
                 MK2_REINIT_LOG2 => 4, MK2_CAPS_HOLD => 20,
                 T3_PROBE_CYCLES => 100_000, T3_LOSS_CYCLES => 125_000,
                 REPROBE_CYCLES => REPROBE)
    port map (clk => clk, kio8_o => k8o, kio8_oe => k8oe, kio8_i => to_X01(pin8),
              kio9_o => k9o, kio9_oe => k9oe, kio10 => to_X01(pin10), leds => leds,
              pressed => pressed, strobe => strobe, kbd_type => ktype,
              kbd_commit => commit, probing => probing);

  mk1dev : entity work.kbd_mk1_device
    port map (clk => clk, keys_pressed => dev_keys, kio8_in => to_X01(pin8),
              kio9_in => to_X01(pin9), kio10_out => dev_kio10, leds => dev_leds,
              leds_strobe => dev_stb, frame_count => frames);

  t3kbd : entity work.megakey_t3
    generic map (T3_TIMEOUT => 12_090)
    port map (KIO8 => to_X01(pin8), KIO9 => to_X01(pin9), KIO10 => t3_kio10,
              SCAN_OUT => so, SCAN_IN => si, KEY_RESTORE => '1',
              LED_R0 => open, LED_G0 => open, LED_B0 => open, LED_R1 => open,
              LED_G1 => open, LED_B1 => open, LED_R2 => open, LED_G2 => open,
              LED_B2 => open, LED_R3 => open, LED_G3 => open, LED_B3 => open,
              LED_SHIFT => open, LED_CAPS => open);
  mat : entity work.kbd_matrix_model port map (so, mkeys, si);

  exp_g : for i in 0 to 5 generate
    u : entity work.i2c_expander_model
      generic map (ADDR => "0100" & std_logic_vector(to_unsigned(i, 3)))
      port map (sda => pin8, scl => pin9, connected => mk2_conn, pins => pins(i),
                out_regs => open, cfg_regs => open, cfg_writes => open,
                out_writes => open, reads => open, errors => i2c_err(i));
  end generate;

  -- while the type-3 probe owns the pins, SDA (KIO8) must never change with
  -- SCL (KIO9) high: that would be an I2C START or STOP for an MK-II
  i2c_mon : process (pin8)
  begin
    if probing = '1' and to_X01(pin9) = '1' and to_X01(pin8) /= to_X01(pin8'last_value) then
      probe_conds <= probe_conds + 1;
    end if;
  end process;
  probe_cnt : process (probing)
  begin
    if probing = '1' then
      probes <= probes + 1;
    end if;
  end process;
  -- published keys must not glitch (e.g. across a re-probe)
  keys_mon : process (clk)
  begin
    if rising_edge(clk) and watch_on and strobe = '1' then
      assert pressed = watch report "published keys glitched: " & to_hstring(pressed)
        severity failure;
    end if;
  end process;

  process
    variable want : std_logic_vector(79 downto 0);
    variable p0 : natural;
    procedure scans(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk) and strobe = '1'; end loop;
    end procedure;
    procedure check_type(t : std_logic_vector(1 downto 0); msg : string) is
    begin
      assert ktype = t report msg & ": type " & to_string(ktype) & " want " & to_string(t)
        severity failure;
    end procedure;
    procedure no_i2c_errors(msg : string) is
    begin
      for i in 0 to 5 loop
        assert i2c_err(i) = 0 report msg & ": I2C protocol error at expander " &
          integer'image(i) severity failure;
      end loop;
      assert probe_conds = 0 report msg & ": START/STOP during a type-3 probe" severity failure;
    end procedure;
  begin
    -- 1. MK-II from power-up: probe first, then MK-II
    pins(3)(0) <= '0';                     -- HELP (67)
    wait until rising_edge(clk) and probing = '1';
    wait until rising_edge(clk) and probing = '0';
    check_type("00", "after the probe");
    scans(3);
    check_type("10", "MK-II");
    want := (others => '0'); want(67) := '1';
    assert pressed = want report "MK-II keys " & to_hstring(pressed) severity failure;
    assert commit = x"4D4B4949" report "MK-II commit id" severity failure;
    no_i2c_errors("MK-II after the probe");
    p0 := probes;
    wait for 4 ms;                         -- > REPROBE: never re-probed with an MK-II
    assert probes = p0 report "re-probed while an MK-II answers" severity failure;

    -- 2. MK-I keyboard: KIO10 high selects MK-I at once
    attached <= MK1;
    dev_keys <= (5 => '1', 60 => '1', 0 => '1', others => '0');
    wait for 1 us;
    check_type("01", "MK-I");
    assert k8oe = '1' and k9oe = '1' report "MK-I pins not driven" severity failure;
    scans(2);
    want := (5 => '1', 60 => '1', 0 => '1', 76 => '1', others => '0');
    assert pressed = want report "MK-I keys " & to_hstring(pressed) severity failure;
    assert commit = x"53555056" report "MK-I commit id " & to_hstring(commit) severity failure;
    for i in 0 to 95 loop
      assert dev_leds(i) = leds(95 - i) report "MK-I LED bit " & integer'image(i) severity failure;
    end loop;
    -- the re-probe (MK-I does not answer) must not disturb the keys
    watch <= want; watch_on <= true;
    p0 := probes;
    wait until probes /= p0;
    wait until rising_edge(clk) and probing = '0';
    scans(3);
    check_type("01", "MK-I after a re-probe");
    watch_on <= false;

    -- 3. type-3 keyboard (CPLD firmware) instead: MK-I first, then type 3
    attached <= T3;
    mkeys(8 * 1 + 0) <= '1';               -- F3 -> 5
    mkeys(8 * 4 + 5) <= '1';               -- SPACE -> 60
    wait until ktype = "11" for 2 * REPROBE * 8 ns + 2 ms;
    check_type("11", "type 3");
    scans(3);
    want := (5 | 60 => '1', others => '0');
    want(72) := pressed(72);
    assert pressed = want report "type-3 keys " & to_hstring(pressed) severity failure;
    assert commit = x"2ed09bd3" report "type-3 commit id " & to_hstring(commit) severity failure;
    assert k8oe = '1' and k8o = '0' report "KIO8 not held low in type 3" severity failure;
    check_type("11", "type 3 kept");

    -- 4. unplugged: lost -> probe -> legacy -> none
    attached <= NONE;
    wait for 3 ms;
    check_type("00", "unplugged");
    assert pressed = (79 downto 0 => '0') report "keys after unplug" severity failure;

    -- 5. MK-II again
    attached <= MK2;
    pins(3)(0) <= '1'; pins(5)(0) <= '0';  -- F1 (4)
    wait until ktype = "10" for 2 * REPROBE * 8 ns + 2 ms;
    scans(3);
    check_type("10", "MK-II again");
    want := (others => '0'); want(4) := '1';
    assert pressed = want report "MK-II keys again " & to_hstring(pressed) severity failure;
    no_i2c_errors("end");
    report "tb_kbd_phys_host PASSED (" & integer'image(probes) & " probes)";
    done <= true;
    osch_stop <= true;
    wait;
  end process;
end architecture;
