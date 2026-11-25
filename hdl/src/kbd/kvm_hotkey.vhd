-- kvm_hotkey: local target selection from the physical keyboard (issue 0029).
--
-- Both SHIFT keys held >= HOLD_MS, then MEGA tapped (pressed and released,
-- SHIFTs still held when MEGA goes down): enter selection (`selecting`).
-- Then a digit press chooses machine k (keys in keyboard order 1..9, 0 ->
-- k = 0..9): `choose` pulses with `k`. ESC or TIMEOUT_MS without a choice
-- pulses `cancel`, as does a press of any key other than a digit, MEGA or
-- LEFT SHIFT. One-handed alternative trigger: a train of LEFT SHIFT / MEGA
-- presses, each within GAP_MS of the previous one, reaching more than
-- TRAIN_N presses with at least TRAIN_EACH of each key within TRAIN_MS.
-- All keys still pass through to the DUT (owner: no suppression); this
-- block only observes the bitmap.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kvm_hotkey is
  generic (HOLD_MS : positive := 1000; TIMEOUT_MS : positive := 10_000;
           TRAIN_N : positive := 10; TRAIN_EACH : positive := 4;
           TRAIN_MS : positive := 2000; GAP_MS : positive := 500);
  port (
    clk       : in  std_logic;
    tick_1ms  : in  std_logic;
    keys      : in  std_logic_vector(79 downto 0);   -- physical, 1 = pressed
    selecting : out std_logic;
    choose    : out std_logic;
    k         : out unsigned(3 downto 0);
    cancel    : out std_logic
  );
end entity;

architecture rtl of kvm_hotkey is
  constant K_LSHIFT : natural := 15;
  constant K_RSHIFT : natural := 52;
  constant K_MEGA   : natural := 61;
  constant K_ESC    : natural := 71;
  type digit_t is array (0 to 9) of natural;   -- matrix number of keys 1..9, 0
  constant DIGITS : digit_t := (56, 59, 8, 11, 16, 19, 24, 27, 32, 35);
  type state_t is (S_IDLE, S_ARMED, S_MEGA, S_SELECT);
  signal state : state_t := S_IDLE;
  signal ms    : integer range 0 to TIMEOUT_MS := 0;
  signal prev  : std_logic_vector(79 downto 0) := (others => '0');
  signal shifts : boolean;
  -- one-handed train (counted in any state except S_SELECT)
  signal tr_ms, tr_gap : integer range 0 to TRAIN_MS := 0;
  signal tr_l, tr_m : integer range 0 to 63 := 0;
begin
  shifts <= keys(K_LSHIFT) = '1' and keys(K_RSHIFT) = '1';
  selecting <= '1' when state = S_SELECT else '0';

  process (clk)
    variable other : boolean;
  begin
    if rising_edge(clk) then
      prev <= keys;
      choose <= '0'; cancel <= '0';
      -- one-handed LSHIFT/MEGA train
      if tick_1ms = '1' then
        if tr_ms < TRAIN_MS then tr_ms <= tr_ms + 1; end if;
        if tr_gap < TRAIN_MS then tr_gap <= tr_gap + 1; end if;
      end if;
      if state /= S_SELECT and ((keys(K_LSHIFT) = '1' and prev(K_LSHIFT) = '0') or
                                (keys(K_MEGA) = '1' and prev(K_MEGA) = '0')) then
        if tr_gap > GAP_MS or tr_ms >= TRAIN_MS then   -- (re)start the train here
          tr_ms <= 0; tr_l <= 0; tr_m <= 0;
          if keys(K_LSHIFT) = '1' and prev(K_LSHIFT) = '0' then tr_l <= 1; end if;
          if keys(K_MEGA) = '1' and prev(K_MEGA) = '0' then tr_m <= 1; end if;
        else
          if keys(K_LSHIFT) = '1' and prev(K_LSHIFT) = '0' and tr_l < 63 then tr_l <= tr_l + 1; end if;
          if keys(K_MEGA) = '1' and prev(K_MEGA) = '0' and tr_m < 63 then tr_m <= tr_m + 1; end if;
        end if;
        tr_gap <= 0;
      end if;
      if state /= S_SELECT and tr_l + tr_m > TRAIN_N and tr_l >= TRAIN_EACH and
         tr_m >= TRAIN_EACH and tr_ms < TRAIN_MS then
        state <= S_SELECT; ms <= 0;
        tr_l <= 0; tr_m <= 0; tr_ms <= TRAIN_MS;
      end if;
      case state is
        when S_IDLE =>
          if not shifts then
            ms <= 0;
          elsif tick_1ms = '1' then
            if ms = HOLD_MS - 1 then state <= S_ARMED; else ms <= ms + 1; end if;
          end if;
        when S_ARMED =>
          if not shifts then
            state <= S_IDLE; ms <= 0;
          elsif keys(K_MEGA) = '1' and prev(K_MEGA) = '0' then
            state <= S_MEGA;
          end if;
        when S_MEGA =>                    -- wait for the MEGA release (tap)
          if keys(K_MEGA) = '0' then
            state <= S_SELECT; ms <= 0;
          end if;
        when S_SELECT =>
          if tick_1ms = '1' then ms <= ms + 1; end if;
          for i in 0 to 9 loop
            if keys(DIGITS(i)) = '1' and prev(DIGITS(i)) = '0' then
              choose <= '1'; k <= to_unsigned(i, 4);
              state <= S_IDLE; ms <= 0;
            end if;
          end loop;
          other := false;
          for j in 0 to 79 loop
            if keys(j) = '1' and prev(j) = '0' and j /= K_LSHIFT and j /= K_MEGA and
               j /= 56 and j /= 59 and j /= 8 and j /= 11 and j /= 16 and j /= 19 and
               j /= 24 and j /= 27 and j /= 32 and j /= 35 then
              other := true;                  -- includes ESC (71)
            end if;
          end loop;
          if other or ms = TIMEOUT_MS - 1 then
            cancel <= '1'; state <= S_IDLE; ms <= 0;
          end if;
      end case;
    end if;
  end process;
end architecture;
