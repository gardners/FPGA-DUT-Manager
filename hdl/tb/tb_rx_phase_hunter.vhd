-- tb_rx_phase_hunter: RX phase hunter (issue 0028) against a channel model
-- whose "eye" (set of good positions) can be moved, plus rx_frame_observer.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rx_phase_hunter is
end entity;

architecture tb of tb_rx_phase_hunter is
  constant NPOS : natural := 64;
  constant SPP  : natural := 7;
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal rst  : std_logic := '0';
  signal ev_good, ev_bad, ps_en, ps_inc, ps_done, hunting : std_logic := '0';
  signal position, eye_width : unsigned(7 downto 0);
  signal hunts : unsigned(15 downto 0);
  -- channel: absolute fine phase (steps), eye in positions [lo, lo+len)
  signal fine    : natural := 0;
  signal eye_lo  : natural := 0;
  signal eye_len : natural := 64;
  signal traffic : boolean := true;
  -- observer
  signal o_dv, o_good, o_drop, t_good, t_bad : std_logic := '0';

  function in_eye(p, lo, len : natural) return boolean is
  begin
    return ((p + NPOS - lo) mod NPOS) < len;
  end function;
begin
  clk <= not clk after 4 ns when not done;

  dut : entity work.rx_phase_hunter
    generic map (POSITIONS => NPOS, STEPS_PER_POS => SPP, FRAMES_PER_POS => 4,
                 BAD_TRIGGER => 3, TIMEOUT_CYC => 3000)
    port map (clk, rst, ev_good, ev_bad, ps_en, ps_inc, ps_done,
              position, eye_width, hunting, hunts);

  -- MMCM phase-shift model: PSDONE 12 cycles after PSEN
  process
  begin
    wait until rising_edge(clk) and ps_en = '1';
    assert ps_inc = '1' report "ps_inc must be 1" severity failure;
    for i in 1 to 11 loop wait until rising_edge(clk); end loop;
    fine <= (fine + 1) mod (NPOS * SPP);
    ps_done <= '1';
    wait until rising_edge(clk);
    ps_done <= '0';
  end process;

  -- traffic: one frame event every 50 cycles, judged at the current phase
  process
  begin
    for i in 1 to 49 loop wait until rising_edge(clk); end loop;
    if traffic then
      if in_eye(fine / SPP, eye_lo, eye_len) then ev_good <= '1'; else ev_bad <= '1'; end if;
    end if;
    wait until rising_edge(clk);
    ev_good <= '0'; ev_bad <= '0';
  end process;

  process
    procedure tick(n : natural := 1) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;
    procedure settle(what : string) is
    begin
      -- wait for a hunt to start (if any) and finish
      tick(2000);
      while hunting = '1' loop tick(100); end loop;
      tick(1000);
      report what & ": position " & integer'image(to_integer(position)) &
             " width " & integer'image(to_integer(eye_width)) &
             " hunts " & integer'image(to_integer(hunts));
    end procedure;
    variable t0, t1 : std_logic;
  begin
    -- 1. eye covers the power-up phase: never hunts
    eye_lo <= 50; eye_len <= 30;         -- positions 50..63, 0..15
    tick(20000);
    assert hunts = 0 and position = 0 report "1: hunted with a good start" severity failure;

    -- 2. drift: eye moves to 10..30 -> hunt once, settle at the centre (20)
    eye_lo <= 10; eye_len <= 21;
    settle("2");
    assert hunts = 1 report "2: expected one hunt" severity failure;
    assert eye_width = 21 report "2: eye width" severity failure;
    assert position = 20 report "2: not centred" severity failure;
    assert fine = 20 * SPP report "2: fine phase disagrees with position" severity failure;
    tick(20000);
    assert hunts = 1 report "2: re-hunted while good" severity failure;

    -- 3. eye wrapping round position 0: 55..63, 0..5 (15) -> centre 62
    eye_lo <= 55; eye_len <= 15;
    settle("3");
    assert hunts = 2 and eye_width = 15 and position = 62
      report "3: wrap-around eye not centred" severity failure;

    -- 4. eye gone and then no traffic at all: every position times out,
    --    returns to where the hunt started
    eye_lo <= 0; eye_len <= 0;
    tick(400);                           -- three bad frames trigger the hunt
    traffic <= false;
    settle("4");
    assert hunts = 3 and eye_width = 0 and position = 62
      report "4: should fall back to the hunt origin" severity failure;

    -- 5. rst (MMCM restarted) returns to the power-up position
    rst <= '1'; tick; rst <= '0'; tick;
    assert position = 0 report "5: rst" severity failure;

    -- observer: good frame, bad frame, short burst, dropped frame
    t0 := t_good; t1 := t_bad;
    o_dv <= '1'; tick(80); o_dv <= '0'; tick; o_good <= '1'; tick; o_good <= '0'; tick(10);
    assert t_good /= t0 and t_bad = t1 report "obs: good frame" severity failure;
    t0 := t_good;
    o_dv <= '1'; tick(80); o_dv <= '0'; tick(10);
    assert t_bad /= t1 and t_good = t0 report "obs: bad frame" severity failure;
    t1 := t_bad;
    o_dv <= '1'; tick(20); o_dv <= '0'; tick(10);
    assert t_bad = t1 and t_good = t0 report "obs: short burst counted" severity failure;
    o_dv <= '1'; o_drop <= '1'; tick; o_drop <= '0'; tick(80); o_dv <= '0'; tick(10);
    assert t_bad = t1 and t_good = t0 report "obs: dropped frame counted" severity failure;

    report "tb_rx_phase_hunter PASSED";
    done <= true;
    wait;
  end process;

  obs : entity work.rx_frame_observer
    port map (clk, o_dv, o_good, o_drop, t_good, t_bad);
end architecture;
