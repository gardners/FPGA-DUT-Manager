-- tb_link_speed: link_speed_meter (RXC at 125 / 25 / 2.5 MHz / stopped,
-- debouncing) and gig_renegotiate (attempt, hold, back-off, episode reset,
-- no-link handling, saturation; times scaled by generics), issue 0070.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_link_speed is
end entity;

architecture tb of tb_link_speed is
  signal done : boolean := false;
  -- meter: 125 MHz system clock, RXC with a selectable period (0 = stopped)
  signal clk     : std_logic := '0';
  signal rxc     : std_logic := '0';
  signal rxc_per : time := 0 ns;
  signal speed   : std_logic_vector(1 downto 0);
  signal count   : unsigned(11 downto 0);
  signal glitch_ok : boolean := true;
  signal watch_glitch : boolean := false;
  signal meter_done : boolean := false;
  -- renegotiation FSM: 100 MHz, 1 "ms" = 10 cycles
  signal fclk     : std_logic := '0';
  signal enable   : std_logic := '0';
  signal fspeed   : std_logic_vector(1 downto 0) := "00";
  signal phy_hold : std_logic;
  signal attempts : unsigned(7 downto 0);
  signal level    : unsigned(2 downto 0);
  constant MS : time := 100 ns;
begin
  clk  <= not clk after 4 ns when not done;
  fclk <= not fclk after 5 ns when not done;

  process
  begin
    if done then wait; end if;
    if rxc_per = 0 ns then
      wait on rxc_per, done;
    else
      rxc <= not rxc;
      wait for rxc_per / 2;
    end if;
  end process;

  meter : entity work.link_speed_meter
    generic map (CLK_HZ => 125_000_000, WIN_LOG2 => 12, DEBOUNCE => 2)
    port map (rxc => rxc, clk => clk, speed => speed, count => count);

  fsm : entity work.gig_renegotiate
    generic map (TICK_CYC => 10, SETTLE_MS => 30, NOTGIG_MS => 10, HOLD_MS => 20,
                 STABLE_MS => 100, GAP1_MS => 20, GAP2_MS => 50, GAP3_MS => 80, GAP4_MS => 100)
    port map (clk => fclk, enable => enable, speed => fspeed, phy_hold => phy_hold,
              attempts => attempts, level => level);

  -- glitch watcher: speed must stay gigabit while watch_glitch
  process (clk)
  begin
    if rising_edge(clk) and watch_glitch and speed /= "11" then
      glitch_ok <= false;
    end if;
  end process;

  ---------------------------------------------------------------- meter
  pm : process
    procedure expect(per : time; want : std_logic_vector(1 downto 0); what : string) is
    begin
      rxc_per <= per;
      wait for 200 us;               -- > (DEBOUNCE + 2) windows of 32.8 us
      assert speed = want report "meter " & what & ": speed " & to_string(speed) &
        " want " & to_string(want) & " (count " & integer'image(to_integer(count)) & ")"
        severity failure;
    end procedure;
  begin
    wait for 1 us;
    assert speed = "00" report "meter: not 'none' at start" severity failure;
    expect(8 ns, "11", "125 MHz");
    expect(40 ns, "10", "25 MHz");
    expect(400 ns, "01", "2.5 MHz");
    expect(0 ns, "00", "stopped");
    expect(8.1 ns, "11", "123.5 MHz (asynchronous to clk)");
    -- debounce: a 40 us stop (spans at most 3 windows, one or two judged not 1000) must not change the speed
    wait until rising_edge(clk);
    watch_glitch <= true;
    rxc_per <= 0 ns;
    wait for 40 us;
    rxc_per <= 8 ns;
    wait for 150 us;
    watch_glitch <= false;
    assert glitch_ok report "meter: a 40 us RXC stop changed the speed" severity failure;
    expect(40 ns, "10", "25 MHz again");
    expect(8 ns, "11", "125 MHz again");
    expect(0 ns, "00", "stopped again");
    report "meter checks done";
    meter_done <= true;
    wait;
  end process;

  ---------------------------------------------------------------- FSM
  pf : process
    variable t_rel : time;
    variable gap   : time;
    procedure near(got, want : time; what : string) is
    begin
      assert got > want - 2 * MS and got < want + 2 * MS
        report what & ": " & time'image(got) & " want ~" & time'image(want) severity failure;
    end procedure;
    -- wait for the next attempt; return the gap from the previous release
    procedure next_attempt(want_gap : time; what : string) is
      variable t0 : time;
    begin
      t0 := now;
      wait until phy_hold = '1' for want_gap + 20 * MS;
      assert phy_hold = '1' report what & ": no attempt" severity failure;
      near(now - t0, want_gap, what & " gap");
      t0 := now;
      wait until phy_hold = '0';
      near(now - t0, 20 * MS, what & " hold time");
    end procedure;
  begin
    -- power-up: disabled -> no hold
    fspeed <= "10";
    wait for 100 * MS;
    assert phy_hold = '0' and attempts = 0 report "fsm: acted while disabled" severity failure;
    -- gigabit from the start: never acts
    fspeed <= "11";
    enable <= '1';
    wait for 300 * MS;
    assert phy_hold = '0' and attempts = 0 report "fsm: acted at gigabit" severity failure;
    -- link drops to 100: attempt after NOTGIG (10 ms; already past settle)
    fspeed <= "10";
    next_attempt(10 * MS, "first attempt");
    assert attempts = 1 and level = 1 report "fsm: counters after attempt 1" severity failure;
    -- 100-only partner: back-off gap = SETTLE + GAPn + NOTGIG after each release
    next_attempt((30 + 20 + 10) * MS, "attempt 2");
    next_attempt((30 + 50 + 10) * MS, "attempt 3");
    next_attempt((30 + 80 + 10) * MS, "attempt 4");
    next_attempt((30 + 100 + 10) * MS, "attempt 5");
    next_attempt((30 + 100 + 10) * MS, "attempt 6");
    assert attempts = 6 and level = 4 report "fsm: counters after attempt 6" severity failure;
    -- renegotiation works: gigabit during settle (SETTLE + GAP4 = 130 ms);
    -- STABLE (100 ms) of gigabit in watch then ends the episode
    fspeed <= "11";
    wait for (130 + 90) * MS;
    assert level = 4 and attempts = 6 report "fsm: back-off reset before STABLE" severity failure;
    wait for 20 * MS;
    assert level = 0 and attempts = 6 report "fsm: back-off not reset after STABLE gigabit" severity failure;
    -- a fresh fault retries quickly again
    fspeed <= "10";
    next_attempt(10 * MS, "attempt 7 (new episode)");
    assert attempts = 7 and level = 1 report "fsm: counters after attempt 7" severity failure;
    -- no link after release: no attempt; a 10/100 run broken by no-link restarts
    fspeed <= "00";
    wait for 300 * MS;
    assert phy_hold = '0' and attempts = 7 report "fsm: acted on no link" severity failure;
    for i in 1 to 5 loop
      fspeed <= "01";
      wait for 7 * MS;
      fspeed <= "00";
      wait for 1 * MS;
    end loop;
    assert phy_hold = '0' and attempts = 7 report "fsm: interrupted 10/100 runs triggered" severity failure;
    fspeed <= "01";
    next_attempt(10 * MS, "attempt 8 (10 Mb/s)");
    -- disable (power-up reset) mid-hold releases the PHY hold at once
    wait until phy_hold = '1';
    enable <= '0';
    wait for 1 * MS;
    assert phy_hold = '0' report "fsm: hold not released when disabled" severity failure;
    -- saturation: a 100-only partner for > 255 attempts
    enable <= '1';
    fspeed <= "10";
    wait until attempts = 255 for 300 * 170 * MS;
    wait for 200 * MS;
    assert attempts = 255 report "fsm: attempts did not saturate at 255: " &
      integer'image(to_integer(attempts)) severity failure;
    report "fsm checks done";
    if not meter_done then wait until meter_done; end if;
    report "tb_link_speed PASSED";
    done <= true;
    wait;
  end process;
end architecture;
