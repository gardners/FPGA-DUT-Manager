-- tb_video_pt_ctrl: passthrough sequencer (issue 0032). Checks the enter
-- debounce, that the clock select only changes while the TX is in reset,
-- immediate fallback on source loss, no holdoff after a user-dropped
-- request, the exponential holdoff of a self-loop (HDMI OUT -> HDMI IN:
-- the source dies whenever the TX is reset) and that the loop never
-- latches, recovery once a real source appears, and the PLL watchdog.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_video_pt_ctrl is
end entity;

architecture tb of tb_video_pt_ctrl is
  constant ENTER : natural := 20;
  constant PRE   : natural := 2;
  constant RSTC  : natural := 10;
  constant HOLD  : natural := 50;
  constant STAB  : natural := 100;
  constant WD    : natural := 30;
  constant PRC   : natural := 3;
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal req, vin, pll : std_logic := '0';
  signal sel, rst, act, prst : std_logic;
  signal sel_d : std_logic := '0';
  signal cyc : natural := 0;
  signal loopback : boolean := false;
  signal vin_s, pll_s, vin_l, pll_l, act_d : std_logic := '0';
  signal enters : natural := 0;
  type tarr is array (0 to 15) of natural;
  signal enter_at : tarr := (others => 0);
  signal rst_d : std_logic := '0';
  signal prst_len, prst_pulses : natural := 0;
begin
  clk <= not clk after 4 ns when not done;

  dut : entity work.video_pt_ctrl
    generic map (ENTER_CYC => ENTER, PRE_CYC => PRE, RST_CYC => RSTC, HOLDOFF_CYC => HOLD,
                 STABLE_CYC => STAB, MAX_BACKOFF => 2, PLL_WD_CYC => WD, PLL_RST_CYC => PRC)
    port map (clk => clk, req => req, vin_locked => vin, pll_locked => pll,
              sel => sel, tx_rst => rst, active => act, pll_rst => prst);
  vin <= vin_l when loopback else vin_s;
  pll <= pll_l when loopback else pll_s;

  -- self-loop model: our TX feeds our RX. In passthrough the RX recovers
  -- our own clock; a TX reset stops the TMDS clock lane, so the RX (and the
  -- PLL behind it) unlocks a few cycles later and relocks on the console
  -- output some cycles after the reset ends with sel = 0.
  loopm : process (clk)
    variable down, up : natural := 0;
  begin
    if rising_edge(clk) then
      if loopback then
        if rst = '1' and sel = '1' then
          up := 0;
          if down = 3 then vin_l <= '0'; pll_l <= '0'; else down := down + 1; end if;
        elsif rst = '0' and sel = '0' then
          down := 0;
          if up = 15 then vin_l <= '1'; pll_l <= '1'; else up := up + 1; end if;
        end if;
      end if;
    end if;
  end process;

  mon : process (clk)
  begin
    if rising_edge(clk) then
      cyc <= cyc + 1;
      sel_d <= sel;
      rst_d <= rst;
      act_d <= act;
      if sel /= sel_d then
        assert rst = '1' report "clock select changed outside TX reset" severity failure;
      end if;
      if act = '1' then
        assert sel = '1' and rst = '0' report "active without sel / in reset" severity failure;
      end if;
      if rst = '1' and rst_d = '0' and act_d = '0' then
        if enters < 16 then enter_at(enters) <= cyc; end if;
        enters <= enters + 1;
      end if;
      if prst = '1' then prst_len <= prst_len + 1; end if;
      if prst = '1' and prst_len = 0 then prst_pulses <= prst_pulses + 1; end if;
    end if;
  end process;

  stim : process
    procedure tick(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;
    variable t0, n0 : natural;
  begin
    tick(5);
    -- 1. nothing requested: console
    vin_s <= '1'; pll_s <= '1';
    tick(100);
    assert sel = '0' and rst = '0' and act = '0' report "idle not console" severity failure;

    -- 2. request: debounce, then reset, switch, release
    req <= '1';
    t0 := cyc;
    wait until act = '1';
    assert cyc - t0 >= ENTER + RSTC report "entered passthrough too early" severity failure;
    assert cyc - t0 <= ENTER + RSTC + 8 report "entered passthrough too late" severity failure;
    -- a short request glitch-free stay
    tick(STAB + 10);
    assert act = '1' report "passthrough not held" severity failure;

    -- 3. user drops the request: immediate select back, reset, no holdoff
    req <= '0';
    tick(1);
    tick(1);
    assert sel = '0' and rst = '1' and act = '0' report "no immediate fallback on req drop" severity failure;
    wait until rst = '0';
    assert sel = '0' report "console clock not selected after leave" severity failure;
    req <= '1';
    t0 := cyc;
    wait until act = '1';
    assert cyc - t0 <= ENTER + RSTC + 8 report "holdoff applied after a user drop" severity failure;

    -- 4. source lost after a stable passthrough: fall back, no holdoff
    tick(STAB + 10);
    vin_s <= '0';
    tick(4);
    assert sel = '0' and act = '0' report "no fallback on source loss" severity failure;
    wait until rst = '0';
    vin_s <= '1';
    t0 := cyc;
    wait until act = '1';
    assert cyc - t0 <= ENTER + RSTC + 10 report "holdoff after a stable session ended" severity failure;
    req <= '0';
    wait until rst = '0';
    tick(5);

    -- 5. self-loop: every attempt fails; attempts are spaced by the
    -- doubling holdoff (50, 100, 200, 200 ...) and never latch
    loopback <= true;
    n0 := enters;
    req <= '1';
    tick(2500);
    req <= '0';
    loopback <= false;
    report "self-loop attempts: " & integer'image(enters - n0);
    assert enters - n0 >= 4 and enters - n0 <= 16 report "unexpected self-loop attempt count" severity failure;
    for i in 1 to 3 loop
      exit when n0 + i + 1 > enters or n0 + i >= 16;
      assert enter_at(n0 + i) - enter_at(n0 + i - 1) >= HOLD * 2 ** (i - 1)
        report "attempt " & integer'image(i) & " too soon after the previous" severity failure;
    end loop;
    assert act = '0' report "self-loop latched in passthrough" severity failure;
    tick(3);
    if rst = '1' then wait until rst = '0'; end if;
    tick(5);
    assert sel = '0' report "self-loop left the passthrough clock selected" severity failure;

    -- 6. a real source after the loop: enters after the remaining holdoff
    vin_s <= '1'; pll_s <= '1';
    req <= '1';
    wait until act = '1' for 10 us;
    assert act = '1' report "no passthrough after the loop was removed" severity failure;
    req <= '0';
    wait until rst = '0';

    -- 7. PLL watchdog: locked source, PLL not locked -> reset pulse
    pll_s <= '0';
    tick(WD + 20);
    assert prst_pulses = 1 and prst_len = PRC
      report "PLL watchdog pulse " & integer'image(prst_pulses) & "x" & integer'image(prst_len)
      severity failure;
    pll_s <= '1';
    tick(WD * 3);
    assert prst_pulses = 1 report "PLL watchdog fired while locked" severity failure;

    report "tb_video_pt_ctrl PASSED";
    done <= true;
    wait;
  end process;
end architecture;
