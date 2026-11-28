-- gig_renegotiate: drop and renegotiate a link that came up at 10/100 (issue 0070).
--
-- The supervisor's MAC is gigabit only (issue 0018). When the link has been
-- up at 10 or 100 Mb/s (speed code 1/2 from link_speed_meter) for NOTGIG_MS
-- without a break, the PHY is held in hardware reset (phy_hold = '1', ANDed
-- into phy_rst_n) for HOLD_MS, released, and given SETTLE_MS to come out of
-- reset and autonegotiate before the speed is judged again. Successive
-- attempts back off: the wait after release is SETTLE_MS + GAPn_MS where n
-- is the number of attempts in the current episode (0 => no extra gap,
-- then GAP1, GAP2, GAP3, and GAP4 for every further attempt), so a partner
-- that can really only do 100 Mb/s sees the link drop for HOLD_MS about once
-- a minute rather than continuously. A gigabit link held for STABLE_MS
-- ends the episode (the next fault retries quickly again). No link (speed
-- 0) is neither good nor bad: it only clears the 10/100 run.
--
-- Times are in ms of TICK_CYC clk cycles; defaults are the hardware values
-- at 125 MHz. `attempts` counts PHY resets since configuration (saturates).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gig_renegotiate is
  generic (
    TICK_CYC  : positive := 125_000;   -- clk cycles per ms
    SETTLE_MS : positive := 3000;      -- after release: PHY out of reset + autoneg
    NOTGIG_MS : positive := 1000;      -- continuous 10/100 before an attempt
    HOLD_MS   : positive := 2000;      -- PHY reset held per attempt
    STABLE_MS : positive := 60_000;    -- gigabit this long resets the back-off
    GAP1_MS   : natural  := 2000;      -- extra wait before attempt 2
    GAP2_MS   : natural  := 10_000;    -- ... before attempt 3
    GAP3_MS   : natural  := 30_000;    -- ... before attempt 4
    GAP4_MS   : natural  := 60_000     -- ... before every later attempt
  );
  port (
    clk      : in  std_logic;
    enable   : in  std_logic;          -- power-up PHY reset released
    speed    : in  std_logic_vector(1 downto 0);   -- 0 none, 1 10, 2 100, 3 1000
    phy_hold : out std_logic;          -- '1': hold the PHY in reset
    attempts : out unsigned(7 downto 0);
    level    : out unsigned(2 downto 0)   -- back-off level (attempts this episode, max 4)
  );
end entity;

architecture rtl of gig_renegotiate is
  function maxi(a, b : natural) return natural is
  begin
    if a > b then return a; end if;
    return b;
  end function;
  constant TMAX : natural := maxi(maxi(SETTLE_MS + GAP4_MS, SETTLE_MS + GAP3_MS),
                                  maxi(maxi(HOLD_MS, NOTGIG_MS), STABLE_MS));

  type state_t is (S_OFF, S_SETTLE, S_WATCH, S_HOLD);
  signal state : state_t := S_OFF;
  signal tick  : integer range 0 to TICK_CYC - 1 := 0;
  signal ms    : std_logic := '0';
  signal t     : integer range 0 to TMAX := 0;         -- state timer (ms)
  signal bad   : integer range 0 to NOTGIG_MS := 0;    -- 10/100 run (ms)
  signal good  : integer range 0 to STABLE_MS := 0;    -- gigabit run (ms)
  signal lvl   : integer range 0 to 4 := 0;
  signal natt  : unsigned(7 downto 0) := (others => '0');

  function gap(l : integer) return natural is
  begin
    case l is
      when 0 => return 0;
      when 1 => return GAP1_MS;
      when 2 => return GAP2_MS;
      when 3 => return GAP3_MS;
      when others => return GAP4_MS;
    end case;
  end function;
begin
  phy_hold <= '1' when state = S_HOLD else '0';
  attempts <= natt;
  level    <= to_unsigned(lvl, 3);

  process (clk)
  begin
    if rising_edge(clk) then
      ms <= '0';
      if tick = TICK_CYC - 1 then
        tick <= 0;
        ms   <= '1';
      else
        tick <= tick + 1;
      end if;

      if enable = '0' then
        state <= S_OFF;
        t <= 0; bad <= 0; good <= 0;
      else
        case state is
          when S_OFF =>                -- power-up release: first judgement
            t <= 0;
            state <= S_SETTLE;

          when S_SETTLE =>
            bad <= 0; good <= 0;
            if ms = '1' then
              if t >= SETTLE_MS + gap(lvl) - 1 then
                t <= 0;
                state <= S_WATCH;
              else
                t <= t + 1;
              end if;
            end if;

          when S_WATCH =>
            if ms = '1' then
              if speed = "01" or speed = "10" then
                good <= 0;
                if bad = NOTGIG_MS - 1 then
                  bad <= 0; t <= 0;
                  if natt /= 255 then natt <= natt + 1; end if;
                  if lvl /= 4 then lvl <= lvl + 1; end if;
                  state <= S_HOLD;
                else
                  bad <= bad + 1;
                end if;
              elsif speed = "11" then
                bad <= 0;
                if good = STABLE_MS - 1 then
                  lvl <= 0;              -- episode over: quick retries again
                else
                  good <= good + 1;
                end if;
              else
                bad <= 0; good <= 0;     -- no link: neither good nor bad
              end if;
            end if;

          when S_HOLD =>
            if ms = '1' then
              if t = HOLD_MS - 1 then
                t <= 0;
                state <= S_SETTLE;
              else
                t <= t + 1;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
