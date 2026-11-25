-- rx_phase_hunter: self-calibrating RGMII RX sample phase (issue 0028).
--
-- Owner rule: start at the calibrated power-up phase and only hunt after
-- BAD_TRIGGER consecutive bad frames. A hunt visits POSITIONS evenly spaced
-- phase positions round the full circle (STEPS_PER_POS fine MMCM steps
-- apart), judges each on the next FRAMES_PER_POS frame events (or a timeout
-- when no traffic arrives = fail), then moves to the middle of the longest
-- circular run of passing positions. If nothing passes it returns to where
-- the hunt started. Then it goes back to watching.
--
-- Vendor-neutral: drives a generic "phase step" handshake (ps_en pulse,
-- ps_done pulse; ps_inc is always '1', the circle wraps), as provided by
-- the Xilinx MMCM dynamic phase shift (PSEN/PSINCDEC/PSDONE on PSCLK = clk).
-- Frame events (ev_good / ev_bad, one-cycle pulses in clk) come from
-- rx_frame_observer via a clock-domain crossing.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rx_phase_hunter is
  generic (
    POSITIONS      : positive := 64;      -- positions per full circle
    STEPS_PER_POS  : positive := 7;       -- fine steps between positions
    FRAMES_PER_POS : positive := 4;       -- events judged per position
    BAD_TRIGGER    : positive := 3;       -- consecutive bad frames to hunt
    TIMEOUT_CYC    : positive := 12_500_000  -- 100 ms at 125 MHz without events
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;            -- MMCM (re)started: phase = default
    ev_good   : in  std_logic;
    ev_bad    : in  std_logic;
    ps_en     : out std_logic;
    ps_inc    : out std_logic;
    ps_done   : in  std_logic;
    -- status
    position  : out unsigned(7 downto 0); -- current position (0 = power-up)
    eye_width : out unsigned(7 downto 0); -- passing positions in the last hunt
    hunting   : out std_logic;
    hunts     : out unsigned(15 downto 0)
  );
end entity;

architecture rtl of rx_phase_hunter is
  type state_t is (S_WATCH, S_JUDGE, S_MOVE, S_PSWAIT, S_PICK, S_GOTO);
  type after_t is (A_JUDGE, A_PICK, A_GOTO);
  signal state   : state_t := S_WATCH;
  signal then_do   : after_t := A_JUDGE;   -- where S_MOVE continues
  signal pos     : integer range 0 to POSITIONS - 1 := 0;   -- 0 = power-up phase
  signal origin  : integer range 0 to POSITIONS - 1 := 0;
  signal visited : integer range 0 to POSITIONS := 0;
  signal steps   : integer range 0 to STEPS_PER_POS := 0;
  signal bad_run : integer range 0 to BAD_TRIGGER := 0;
  signal nev     : integer range 0 to FRAMES_PER_POS := 0;
  signal ngood   : integer range 0 to FRAMES_PER_POS := 0;
  signal tmo     : integer range 0 to TIMEOUT_CYC := 0;
  signal settle  : integer range 0 to 3 := 0;
  signal pass    : std_logic_vector(POSITIONS - 1 downto 0) := (others => '0');
  signal target  : integer range 0 to POSITIONS - 1 := 0;
  signal width   : unsigned(7 downto 0) := (others => '0');
  signal nhunts  : unsigned(15 downto 0) := (others => '0');
  -- S_PICK: one position per cycle, twice round, longest run of passes
  signal pk_i    : integer range 0 to 2 * POSITIONS := 0;
  signal run_len, best_len : integer range 0 to POSITIONS := 0;
  signal best_end : integer range 0 to 2 * POSITIONS := 0;
begin
  ps_inc    <= '1';
  position  <= to_unsigned(pos, 8);
  eye_width <= width;
  hunting   <= '0' when state = S_WATCH else '1';
  hunts     <= nhunts;

  process (clk)
    procedure judged(ok : boolean) is
    begin
      if ok then pass(pos) <= '1'; end if;
      steps <= 0;
      if visited = POSITIONS - 1 then
        then_do <= A_PICK;               -- last one: the move returns to origin
      else
        then_do <= A_JUDGE;
      end if;
      visited <= visited + 1;
      state <= S_MOVE;
    end procedure;
  begin
    if rising_edge(clk) then
      ps_en <= '0';
      if rst = '1' then
        state <= S_WATCH; pos <= 0; bad_run <= 0;
      else
        case state is
          when S_WATCH =>
            if ev_good = '1' then
              bad_run <= 0;
            elsif ev_bad = '1' then
              if bad_run = BAD_TRIGGER - 1 then
                bad_run <= 0;
                nhunts  <= nhunts + 1;
                origin  <= pos;
                visited <= 0;
                pass    <= (others => '0');
                nev <= 0; ngood <= 0; tmo <= 0; settle <= 0;
                state   <= S_JUDGE;      -- judge the current position first
              else
                bad_run <= bad_run + 1;
              end if;
            end if;

          when S_JUDGE =>
            if settle /= 3 then
              settle <= settle + 1;      -- skip events already in flight
            elsif ev_good = '1' or ev_bad = '1' then
              tmo <= 0;
              if nev = FRAMES_PER_POS - 1 then
                judged(ev_good = '1' and ngood = FRAMES_PER_POS - 1);
              else
                nev <= nev + 1;
                if ev_good = '1' then ngood <= ngood + 1; end if;
              end if;
            elsif tmo = TIMEOUT_CYC - 1 then
              judged(false);             -- no traffic here: fail
            else
              tmo <= tmo + 1;
            end if;

          when S_MOVE =>
            -- advance one position (STEPS_PER_POS fine steps), then continue
            if steps = STEPS_PER_POS then
              steps <= 0;
              if pos = POSITIONS - 1 then pos <= 0; else pos <= pos + 1; end if;
              nev <= 0; ngood <= 0; tmo <= 0; settle <= 0;
              case then_do is
                when A_JUDGE => state <= S_JUDGE;
                when A_PICK  =>
                  pk_i <= 0; run_len <= 0; best_len <= 0; best_end <= 0;
                  state <= S_PICK;
                when A_GOTO  => state <= S_GOTO;
              end case;
            else
              ps_en <= '1';
              state <= S_PSWAIT;
            end if;

          when S_PSWAIT =>
            if ps_done = '1' then
              steps <= steps + 1;
              state <= S_MOVE;
            end if;

          when S_PICK =>
            if pk_i = 2 * POSITIONS then
              width <= to_unsigned(best_len, 8);
              if best_len = 0 or best_len = POSITIONS then
                target <= origin;          -- nothing (or everything) passes
              else
                target <= (best_end - best_len / 2) mod POSITIONS;
              end if;
              state <= S_GOTO;
            else
              if pass(pk_i mod POSITIONS) = '1' then
                if run_len < POSITIONS then
                  run_len <= run_len + 1;
                  if run_len + 1 > best_len then
                    best_len <= run_len + 1;
                    best_end <= pk_i;
                  end if;
                end if;
              else
                run_len <= 0;
              end if;
              pk_i <= pk_i + 1;
            end if;

          when S_GOTO =>
            if pos = target then
              bad_run <= 0;
              state <= S_WATCH;
            else
              steps <= 0;
              then_do <= A_GOTO;
              state <= S_MOVE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
