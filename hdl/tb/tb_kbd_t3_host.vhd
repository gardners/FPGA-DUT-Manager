-- tb_kbd_t3_host: keyboard type 3 (ADR 0014, issue 0046) end to end:
-- kbd_t3_host (125 MHz) against the type-3 keyboard CPLD firmware
-- (megakey_t3 with the OSCH model, key matrix model), with 20 ns of cable
-- delay each way. Checked, at the nominal OSCH frequency and at both ends
-- of its +/-5.5 % tolerance (each entered from the stale auto-baud value
-- of the previous run, i.e. up to 11 % off):
-- * the keyboard enters type 3 and the host publishes frames: keys at
--   their MEGA65 matrix positions, commit id, date stamp, version, the
--   CAPS LOCK state word; no receive errors once locked;
-- * the host's LED vector arrives in the CPLD's control frame;
-- * the keyboard leaves type 3 T3_TIMEOUT after the host stops sending,
--   and at once when KIO8 goes high (an MK-I host clocking).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library machxo2;
use machxo2.osch_sim_pkg.all;

entity tb_kbd_t3_host is
end entity;

architecture tb of tb_kbd_t3_host is
  constant T3_TIMEOUT : natural := 24_180;     -- 1 ms at 24.18 MHz
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal en   : std_logic := '0';
  signal kio8 : std_logic := '0';
  signal txd, k9, k10, rxd : std_logic;
  signal so   : std_logic_vector(9 downto 0);
  signal si   : std_logic_vector(7 downto 0);
  signal keys : std_logic_vector(79 downto 0) := (others => '0');
  signal leds : std_logic_vector(95 downto 0) := x"112233_445566_778899_AABBCC";
  signal pressed : std_logic_vector(79 downto 0);
  signal strobe, present : std_logic;
  signal commit : std_logic_vector(31 downto 0);
  signal date   : std_logic_vector(13 downto 0);
  signal locks  : std_logic_vector(3 downto 0);
  signal version : std_logic_vector(6 downto 0);
  signal errs   : unsigned(15 downto 0);
  signal ledo   : std_logic_vector(13 downto 0);

  function phys(r, c : natural) return natural is
  begin
    return 8 * r + c;
  end function;
begin
  clk <= not clk after 4 ns when not done;
  k9  <= transport txd after 20 ns;
  rxd <= transport k10 after 20 ns;

  host : entity work.kbd_t3_host
    generic map (LOSS_CYCLES => 125_000)
    port map (clk => clk, enable => en, txd => txd, rxd => rxd, leds => leds,
              lock_ovr => "0000", pressed => pressed, strobe => strobe, present => present,
              kbd_commit => commit, kbd_date => date, locks => locks, version => version,
              rx_errors => errs);

  kbd : entity work.megakey_t3
    generic map (T3_TIMEOUT => T3_TIMEOUT)
    port map (KIO8 => kio8, KIO9 => k9, KIO10 => k10, SCAN_OUT => so, SCAN_IN => si,
              KEY_RESTORE => '1',
              LED_R0 => ledo(0), LED_G0 => ledo(1), LED_B0 => ledo(2),
              LED_R1 => ledo(3), LED_G1 => ledo(4), LED_B1 => ledo(5),
              LED_R2 => ledo(6), LED_G2 => ledo(7), LED_B2 => ledo(8),
              LED_R3 => ledo(9), LED_G3 => ledo(10), LED_B3 => ledo(11),
              LED_SHIFT => ledo(12), LED_CAPS => ledo(13));
  mat : entity work.kbd_matrix_model port map (so, keys, si);

  stim : process
    alias kbd_t3   is << signal .tb_kbd_t3_host.kbd.t3 : std_logic >>;
    alias kbd_l9   is << signal .tb_kbd_t3_host.kbd.l9 : unsigned(7 downto 0) >>;
    alias kbd_ctrl is << signal .tb_kbd_t3_host.kbd.mega65_control_data : unsigned(127 downto 0) >>;
    variable want : std_logic_vector(79 downto 0);
    variable e0   : unsigned(15 downto 0);
    variable t0   : time;

    procedure frames(n : natural) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk) and strobe = '1';
      end loop;
    end procedure;

    procedure run(name : string; trim : integer; l9_lo, l9_hi : natural) is
    begin
      osch_trim_ppm <= trim;
      wait for 1 us;
      keys <= (others => '0');
      en <= '1';
      t0 := now;
      wait until present = '1' for 3 ms;
      assert present = '1' report name & ": no type-3 frame" severity failure;
      report name & ": type 3 up after " & time'image(now - t0) & ", l9 = " &
             integer'image(to_integer(kbd_l9));
      assert kbd_t3 = '1' report name & ": keyboard not in type 3" severity failure;
      assert to_integer(kbd_l9) >= l9_lo and to_integer(kbd_l9) <= l9_hi
        report name & ": auto-baud l9 = " & integer'image(to_integer(kbd_l9)) severity failure;
      frames(2);
      e0 := errs;
      assert commit = x"2ed09bd3" report name & ": commit " & to_hstring(commit) severity failure;
      assert unsigned(date) = 2527 report name & ": date stamp" severity failure;
      assert version = "0000001" report name & ": version" severity failure;
      assert pressed(71 downto 0) = (71 downto 0 => '0') report name & ": keys without presses"
        severity failure;
      -- F3 (1,0) -> 5, DEL (0,5) -> 0 + 76, RETURN (5,7) -> 1 + 77, SPACE (4,5) -> 60
      keys(phys(1, 0)) <= '1'; keys(phys(0, 5)) <= '1';
      keys(phys(5, 7)) <= '1'; keys(phys(4, 5)) <= '1';
      wait for 600 us;                 -- > 2 matrix scans
      frames(2);
      want := (5 | 0 | 76 | 1 | 77 | 60 => '1', others => '0');
      want(72) := pressed(72);         -- CAPS LOCK state carried over
      assert pressed = want report name & ": keys " & to_hstring(pressed) severity failure;
      keys <= (others => '0');
      wait for 600 us;
      frames(2);
      assert pressed(71 downto 0) = (71 downto 0 => '0') report name & ": release" severity failure;
      -- LED vector -> control frame bits 95..0 (MK-I: x"00000000" & leds)
      assert kbd_ctrl(95 downto 0) = unsigned(leds)
        report name & ": control frame " & to_hstring(kbd_ctrl(95 downto 0)) severity failure;
      leds <= not leds;
      wait for 500 us;
      assert kbd_ctrl(95 downto 0) = unsigned(leds) report name & ": new LEDs" severity failure;
      assert errs = e0 report name & ": receive errors after lock: " &
        integer'image(to_integer(errs - e0)) severity failure;
      -- stop sending: the keyboard leaves type 3 after T3_TIMEOUT
      en <= '0';
      wait for 900 us;
      assert kbd_t3 = '1' report name & ": left type 3 early" severity failure;
      wait for 200 us;
      assert kbd_t3 = '0' report name & ": still in type 3 after the timeout" severity failure;
    end procedure;
  begin
    wait for 10 us;
    run("nominal", 0, 106, 112);
    -- OSCH 5.5 % slow (period +5.82 %): 9 bits = 102.8 cycles
    run("slow", 58_200, 100, 106);
    -- OSCH 5.5 % fast (period -5.21 %): 9 bits = 114.8 cycles
    run("fast", -52_100, 112, 118);

    -- CAPS LOCK (5,0): lock word bit 0 and matrix bit 72
    osch_trim_ppm <= 0;
    en <= '1';
    wait until present = '1' for 3 ms;
    keys(phys(5, 0)) <= '1';
    wait for 600 us;
    keys(phys(5, 0)) <= '0';
    wait for 2 ms;                   -- 8 released scans before the next toggle
    frames(2);
    assert locks(0) = pressed(72) report "lock word vs matrix bit 72" severity failure;
    report "CAPS LOCK state " & std_logic'image(locks(0));

    -- KIO8 high (MK-I host) -> out of type 3 at once
    assert kbd_t3 = '1' report "not in type 3 before the KIO8 test" severity failure;
    kio8 <= '1';
    wait for 500 ns;
    assert kbd_t3 = '0' report "KIO8 high did not end type 3" severity failure;
    kio8 <= '0';
    en <= '0';
    wait for 10 us;
    report "tb_kbd_t3_host PASSED";
    done <= true;
    wait;
  end process;
end architecture;
