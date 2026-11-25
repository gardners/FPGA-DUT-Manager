-- video_pt_ctrl: HDMI OUT passthrough sequencer (issue 0032), vendor neutral.
--
-- Decides when the DVI transmitter runs from the HDMI IN recovered clocks
-- (passthrough) instead of the console's local clocks, and sequences the
-- switch: the transmitter is held in reset for RST_CYC around every clock
-- change, so the glitch-free clock mux (BUFGCTRL, platform side) never
-- switches under a running encoder/serialiser and the link restarts cleanly.
--
--   CON   --(req and source ok for ENTER_CYC, holdoff over)-->  ENTER
--   ENTER  TX reset; sel -> 1 after PRE_CYC; after RST_CYC  --> PT
--   PT    --(req dropped or source lost)-->                     LEAVE
--   LEAVE  sel -> 0 at once (the recovered clock may be dead), TX reset
--          for RST_CYC                                     --> CON
--
-- Source ok = recovered clock locked (vin_locked) and the passthrough PLL
-- locked (pll_locked); both are asynchronous inputs, synchronised here.
-- Losing the source (in ENTER or within STABLE_CYC of PT) counts as a
-- failed attempt: re-entry then waits HOLDOFF_CYC * 2^n (n = failed attempts
-- in a row, at most MAX_BACKOFF). This keeps a self-loop (HDMI OUT cabled to
-- HDMI IN: passthrough of our own output loses its source as soon as the TX
-- is reset) from re-trying faster than the monitor can follow. A request
-- dropped by the user (selection, forced screen) is not a failure.
-- pll_rst pulses (PLL_RST_CYC) when the source is locked but the PLL has
-- not locked for PLL_WD_CYC (a PLL must be reset after losing its input).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_pt_ctrl is
  generic (
    ENTER_CYC   : positive := 12_500_000;    -- 100 ms at 125 MHz
    PRE_CYC     : positive := 16;            -- reset before the clock switch
    RST_CYC     : positive := 2_000_000;     -- 16 ms TX reset per switch
    HOLDOFF_CYC : positive := 125_000_000;   -- 1 s after a failed attempt
    STABLE_CYC  : positive := 250_000_000;   -- 2 s of passthrough clears backoff
    MAX_BACKOFF : natural  := 3;             -- holdoff up to 8 s
    PLL_WD_CYC  : positive := 1_250_000;     -- 10 ms
    PLL_RST_CYC : positive := 125            -- 1 us
  );
  port (
    clk        : in  std_logic;
    req        : in  std_logic;   -- passthrough wanted (clk domain)
    vin_locked : in  std_logic;   -- async: HDMI IN recovered clock locked
    pll_locked : in  std_logic;   -- async: passthrough PLL locked
    sel        : out std_logic;   -- clock/data select, 1 = passthrough
    tx_rst     : out std_logic;   -- DVI TX reset (synchronise in TX domain)
    active     : out std_logic;   -- passthrough on HDMI OUT
    pll_rst    : out std_logic
  );
end entity;

architecture rtl of video_pt_ctrl is
  type state_t is (S_CON, S_ENTER, S_PT, S_LEAVE);
  signal st : state_t := S_CON;
  signal vl_s, pl_s : std_logic_vector(1 downto 0) := "00";
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of vl_s, pl_s : signal is "TRUE";
  signal src_ok : boolean;
  signal cnt    : natural range 0 to RST_CYC := 0;
  signal stab   : natural range 0 to ENTER_CYC := 0;
  signal hold   : natural range 0 to HOLDOFF_CYC * 2 ** MAX_BACKOFF := 0;
  signal pt_t   : natural range 0 to STABLE_CYC := 0;
  signal fails  : natural range 0 to MAX_BACKOFF := 0;
  signal failed : boolean := false;
  signal sel_r, rst_r : std_logic := '0';
  signal wd     : natural range 0 to PLL_WD_CYC := 0;
  signal prst   : natural range 0 to PLL_RST_CYC := 0;
begin
  src_ok <= vl_s(1) = '1' and pl_s(1) = '1';

  process (clk)
  begin
    if rising_edge(clk) then
      vl_s <= vl_s(0) & vin_locked;
      pl_s <= pl_s(0) & pll_locked;

      case st is
        when S_CON =>
          sel_r <= '0';
          rst_r <= '0';
          if hold /= 0 then hold <= hold - 1; end if;
          if req = '1' and src_ok then
            if stab /= ENTER_CYC then stab <= stab + 1; end if;
          else
            stab <= 0;
          end if;
          if stab = ENTER_CYC and hold = 0 and req = '1' and src_ok then
            st <= S_ENTER;
            rst_r <= '1';
            cnt <= 0;
            stab <= 0;
          end if;
        when S_ENTER =>
          rst_r <= '1';
          if cnt = PRE_CYC then sel_r <= '1'; end if;
          if req = '0' or not src_ok then
            st <= S_LEAVE;
            sel_r <= '0';
            cnt <= 0;
            failed <= not src_ok;
          elsif cnt = RST_CYC then
            st <= S_PT;
            rst_r <= '0';
            pt_t <= 0;
          else
            cnt <= cnt + 1;
          end if;
        when S_PT =>
          if pt_t /= STABLE_CYC then
            pt_t <= pt_t + 1;
          else
            fails <= 0;
          end if;
          if req = '0' or not src_ok then
            st <= S_LEAVE;
            sel_r <= '0';
            rst_r <= '1';
            cnt <= 0;
            failed <= not src_ok and pt_t /= STABLE_CYC;
          end if;
        when S_LEAVE =>
          sel_r <= '0';
          rst_r <= '1';
          if cnt = RST_CYC then
            st <= S_CON;
            rst_r <= '0';
            if failed then
              hold <= to_integer(shift_left(to_unsigned(HOLDOFF_CYC, 31), fails));
              if fails /= MAX_BACKOFF then fails <= fails + 1; end if;
            else
              hold <= 0;
            end if;
          else
            cnt <= cnt + 1;
          end if;
      end case;

      -- PLL watchdog
      if prst /= 0 then
        prst <= prst - 1;
        wd <= 0;
      elsif vl_s(1) = '1' and pl_s(1) = '0' then
        if wd = PLL_WD_CYC then
          prst <= PLL_RST_CYC;
          wd <= 0;
        else
          wd <= wd + 1;
        end if;
      else
        wd <= 0;
      end if;
    end if;
  end process;

  sel     <= sel_r;
  tx_rst  <= rst_r;
  active  <= '1' when st = S_PT else '0';
  pll_rst <= '1' when prst /= 0 else '0';
end architecture;
