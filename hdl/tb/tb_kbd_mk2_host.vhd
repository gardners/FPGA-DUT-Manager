-- tb_kbd_mk2_host: our MK-II host scanning six behavioural TCA9555 models
-- (U1 0x20 LEDs, U3/U5/U2/U4/U6 at 0x21..0x25 keys) on an open-drain bus
-- with pull-ups. Checks every key position (issue 0009 mapping), SHIFT LOCK,
-- CAPS LOCK latch and hold re-toggle, LED PWM and bit mapping, periodic U1
-- re-initialisation, ACK-based presence and that the bus never shows a
-- START/STOP inside a byte.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kbd_mk2_host is
end entity;

architecture tb of tb_kbd_mk2_host is
  constant CAPS_HOLD : positive := 20;
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal sda, scl : std_logic;
  signal sda_low, scl_low, sda_in : std_logic;
  signal enable  : std_logic := '0';
  signal leds    : std_logic_vector(95 downto 0) := (others => '0');
  signal pressed : std_logic_vector(79 downto 0);
  signal strobe, present : std_logic;
  signal commit  : std_logic_vector(31 downto 0);

  type slv16_arr is array (0 to 5) of std_logic_vector(15 downto 0);
  type nat_arr is array (0 to 5) of natural;
  signal pins : slv16_arr := (others => (others => '1'));
  signal outr, cfgr : slv16_arr;
  signal ncfg, nout, nrd, nerr : nat_arr;

  -- expected mapping (issue 0009 analysis): index = expander 1..5, port bit
  -- 0..15; -1 none, -2 special (SHIFT LOCK, GPIO, CAPS LOCK)
  type map_t is array (1 to 5, 0 to 15) of integer;
  constant EXP : map_t := (
    1 => (-1, 9, 62, 65, 18, 13, 10, -2, 20, 23, 12, 15, 61, 58, 14, 57),
    2 => (2, 7, 73, 74, -2, -2, 55, 52, 75, 54, 49, 46, 1, 53, 50, 45),
    3 => (67, 70, 69, 68, 0, 51, 48, 43, 41, 38, 33, 30, 40, 35, 6, 3),
    4 => (42, 36, 37, 39, 28, 31, 47, 44, 60, 21, 17, 26, 22, 29, 25, 34),
    5 => (4, 5, 32, 27, 24, 19, 16, 11, 8, 59, 56, 63, 71, 66, -2, 64));

  -- LED nibbles: ov(hi downto hi-3), ov(i) = leds(95 - i); U1 output bit
  -- (0..7 port 0, 8..15 port 1) that carries each one
  type led_t is record hi : natural; obit : natural; end record;
  type led_arr is array (0 to 11) of led_t;
  constant LEDMAP : led_arr := (
    (95, 0), (87, 1), (79, 2),       -- LED0 g r b
    (71, 4), (63, 5), (55, 6),       -- LED1 g r b
    (47, 8), (31, 9), (39, 10),      -- LED2 g r b
    (23, 12), (7, 13), (15, 14));    -- LED3 g r b
begin
  clk <= not clk after 4 ns when not done;

  sda <= 'H'; scl <= 'H';
  sda <= '0' when sda_low = '1' else 'Z';
  scl <= '0' when scl_low = '1' else 'Z';
  sda_in <= to_X01(sda);

  dut : entity work.kbd_mk2_host
    generic map (QUARTER_CYCLES => 8, REINIT_LOG2 => 6, CAPS_HOLD => CAPS_HOLD)
    port map (clk => clk, enable => enable, sda_in => sda_in, sda_low => sda_low,
              scl_low => scl_low, leds => leds, pressed => pressed, strobe => strobe,
              present => present, kbd_commit => commit);

  exp_g : for i in 0 to 5 generate
    u : entity work.i2c_expander_model
      generic map (ADDR => "0100" & std_logic_vector(to_unsigned(i, 3)))
      port map (sda => sda, scl => scl, pins => pins(i), out_regs => outr(i),
                cfg_regs => cfgr(i), cfg_writes => ncfg(i), out_writes => nout(i),
                reads => nrd(i), errors => nerr(i));
  end generate;

  process
    variable want : std_logic_vector(79 downto 0);
    variable k, last_out, ons : natural;
    variable cnt : nat_arr;
    type cnt12 is array (0 to 11) of natural;
    variable on_cnt : cnt12;
    variable fresh : natural;

    procedure scans(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk) and strobe = '1'; end loop;
    end procedure;

    procedure check(w : std_logic_vector(79 downto 0); msg : string) is
    begin
      assert pressed = w
        report msg & ": got " & to_hstring(pressed) & " want " & to_hstring(w)
        severity failure;
    end procedure;

    procedure set_nibble(signal l : inout std_logic_vector(95 downto 0);
                         hi, v : natural) is
      variable u : unsigned(3 downto 0) := to_unsigned(v, 4);
    begin
      for j in 0 to 3 loop
        l(95 - (hi - 3 + j)) <= u(j);
      end loop;
    end procedure;
  begin
    -- disabled: bus idle and released
    wait for 5 us;
    assert sda = 'H' and scl = 'H' report "bus not idle while disabled" severity failure;
    assert nrd(1) = 0 report "scanned while disabled" severity failure;
    enable <= '1';
    scans(3);
    assert present = '1' report "MK-II not present" severity failure;
    assert commit = x"4D4B4949" report "commit id" severity failure;
    assert ncfg(0) >= 1 and cfgr(0) = x"0000"
      report "U1 not configured as outputs: writes " & integer'image(ncfg(0)) & " cfg " & to_hstring(cfgr(0)) & " out " & to_hstring(outr(0)) & " nout " & integer'image(nout(0)) severity failure;
    for i in 1 to 5 loop
      assert nrd(i) >= 3 report "expander " & integer'image(i) & " not read" severity failure;
      assert cfgr(i) = x"FFFF" and ncfg(i) = 0 report "key expander written" severity failure;
    end loop;
    check((others => '0'), "idle");

    ---------------------------------------------------------------- mapping
    for a in 1 to 5 loop
      for b in 0 to 15 loop
        if EXP(a, b) /= -2 then
          pins(a)(b) <= '0';
          scans(2);
          want := (others => '0');
          if EXP(a, b) >= 0 then
            k := EXP(a, b);
            want(k) := '1';
            if k = 0 then want(76) := '1'; end if;
            if k = 1 then want(77) := '1'; end if;
          end if;
          check(want, "expander " & integer'image(a) & " bit " & integer'image(b));
          pins(a)(b) <= '1';
        end if;
      end loop;
    end loop;
    -- GPIO lines and several keys at once
    pins(2)(4) <= '0'; pins(2)(5) <= '0';
    pins(3)(0) <= '0'; pins(4)(8) <= '0'; pins(5)(0) <= '0';
    scans(2);
    want := (others => '0');
    want(67) := '1'; want(60) := '1'; want(4) := '1';
    check(want, "GPIO + multi-key");
    pins <= (others => (others => '1'));
    scans(2);
    check((others => '0'), "all released");

    ---------------------------------------------------------------- SHIFT LOCK
    assert outr(0)(7) = '1' report "shift lock LED on at start" severity failure;
    pins(1)(7) <= '0'; scans(2); pins(1)(7) <= '1'; scans(3);
    want := (others => '0'); want(15) := '1';
    check(want, "shift locked");
    assert outr(0)(7) = '0' report "shift lock LED off while locked" severity failure;
    pins(1)(11) <= '0'; scans(2);
    check(want, "LSHIFT while locked");
    pins(1)(11) <= '1';
    pins(1)(7) <= '0'; scans(2); pins(1)(7) <= '1'; scans(3);
    check((others => '0'), "shift unlocked");
    assert outr(0)(7) = '1' report "shift lock LED on after unlock" severity failure;

    ---------------------------------------------------------------- CAPS LOCK
    assert outr(0)(3) = '1' report "caps LED on at start" severity failure;
    pins(5)(14) <= '0'; scans(2);
    want := (others => '0'); want(72) := '1'; want(78) := '1';
    check(want, "caps pressed");
    pins(5)(14) <= '1'; scans(3);
    want(78) := '0';
    check(want, "caps latched");
    assert outr(0)(3) = '0' report "caps LED off while locked" severity failure;
    scans(9);
    pins(5)(14) <= '0'; scans(2); pins(5)(14) <= '1'; scans(3);
    check((others => '0'), "caps unlatched");
    assert outr(0)(3) = '1' report "caps LED on after unlock" severity failure;
    -- a bounce (released for fewer than 8 scans) does not toggle again
    scans(9);
    pins(5)(14) <= '0'; scans(2); pins(5)(14) <= '1'; scans(2);
    pins(5)(14) <= '0'; scans(2); pins(5)(14) <= '1'; scans(2);
    want := (others => '0'); want(72) := '1';
    check(want, "caps bounce");
    scans(9);
    pins(5)(14) <= '0'; scans(2); pins(5)(14) <= '1'; scans(2);
    check((others => '0'), "caps off again");
    scans(9);
    -- holding CAPS for CAPS_HOLD scans re-toggles it (turbo button use)
    pins(5)(14) <= '0'; scans(2);
    want := (others => '0'); want(72) := '1'; want(78) := '1';
    check(want, "caps hold start");
    scans(CAPS_HOLD + 12);
    want(72) := '0';
    check(want, "caps hold re-toggle");
    pins(5)(14) <= '1'; scans(2);
    check((others => '0'), "caps hold released");

    ---------------------------------------------------------------- LED PWM
    -- LED i gets nibble value (i + 3) mod 16 (covers 0 and 15); other bits
    -- of the vector set to catch mapping errors
    leds <= (others => '1');
    wait for 0 ns;
    for i in 0 to 11 loop
      set_nibble(leds, LEDMAP(i).hi, (i + 3) mod 16);
    end loop;
    scans(2);
    -- collect 16 consecutive scans that each wrote the output ports
    fresh := 0; on_cnt := (others => 0);
    last_out := nout(0);
    while fresh < 16 loop
      scans(1);
      if nout(0) = last_out then
        fresh := 0; on_cnt := (others => 0);   -- re-init scan: start again
      else
        fresh := fresh + 1;
        for i in 0 to 11 loop
          if outr(0)(LEDMAP(i).obit) = '0' then on_cnt(i) := on_cnt(i) + 1; end if;
        end loop;
        assert outr(0)(15) = '0' and outr(0)(11) = '0'
          report "unused LED port bits not 0" severity failure;
      end if;
      last_out := nout(0);
    end loop;
    for i in 0 to 11 loop
      assert on_cnt(i) = (i + 3) mod 16
        report "LED " & integer'image(i) & " on for " & integer'image(on_cnt(i)) &
               " of 16 scans, want " & integer'image((i + 3) mod 16) severity failure;
    end loop;

    ---------------------------------------------------------------- re-init, errors
    cnt(0) := ncfg(0);
    scans(70);
    assert ncfg(0) >= cnt(0) + 1 and cfgr(0) = x"0000"
      report "U1 not re-initialised periodically" severity failure;
    for i in 0 to 5 loop
      assert nerr(i) = 0 report "bus errors at expander " & integer'image(i) severity failure;
    end loop;

    -- disable: bus released, presence dropped
    enable <= '0';
    wait for 2 us;
    assert sda = 'H' and scl = 'H' report "bus not released on disable" severity failure;
    assert present = '0' report "present while disabled" severity failure;
    report "tb_kbd_mk2_host PASSED";
    done <= true;
    wait;
  end process;
end architecture;
