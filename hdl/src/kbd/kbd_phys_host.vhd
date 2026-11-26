-- kbd_phys_host: the master's own MEGA65 keyboard: type 3 (async UART, ADR
-- 0014), MK-I or MK-II.
--
-- Type 3 is probed first (issue 0046): KIO8 held low, byte pairs on KIO9
-- for T3_PROBE_CYCLES. A type-3 keyboard answers on KIO10 and stays in type
-- 3 as long as we keep sending. Probing is harmless for the other kinds:
-- an MK-I keyboard only shifts on KIO8 edges and KIO8 does not move; for an
-- MK-II (KIO8 = SDA, KIO9 = SCL) SCL is pulled low before SDA, and SDA is
-- released while SCL is low again at the end, so SDA never changes while
-- SCL is high: no START or STOP, the expanders ignore the SCL pulses.
--
-- Without an answer, the R6 rule of mega65r6.vhdl (ADR 0006, issue 0009)
-- runs: start in MK-II mode; KIO10 high at any time selects MK-I at once (an
-- MK-I keyboard drives KIO10 high at idle; an MK-II ties it low); KIO10 low
-- for MK2_DETECT_CYCLES returns to MK-II (5000 cycles at 40.5 MHz upstream =
-- 123 us). Type 3 is probed again after REPROBE_CYCLES with no keyboard
-- (type 0) or with an MK-I (a type-3 keyboard also speaks MK-I, so this
-- upgrades it), but never while an MK-II answers. A lost type-3 keyboard
-- (no frame for T3_LOSS_CYCLES) is probed again at once. The first
-- MK1_SKIP_FRAMES MK-I frames after the probe are not published (the
-- keyboard's bit counter resynchronises at the next sync pulse).
--
-- Pins: MK-I mode drives KIO8 (clock/sync) and KIO9 (LED data) push-pull;
-- MK-II mode uses KIO8 = SDA and KIO9 = SCL open drain (o = '0', oe = pull
-- low); type 3 drives KIO8 low and KIO9 with the UART, push-pull. The top
-- level turns o/oe into tri-state buffers. All pin outputs and results are
-- registered here.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_phys_host is
  generic (
    MK1_HALF_CYCLES    : positive := 200;     -- MK-I clock half period
    MK2_QUARTER_CYCLES : positive := 125;     -- MK-II SCL quarter period
    MK2_DETECT_CYCLES  : positive := 15432;   -- KIO10 low this long -> MK-II
    MK2_REINIT_LOG2    : positive := 10;
    MK2_CAPS_HOLD      : positive := 510;
    T3_BIT_CYCLES      : positive := 62;            -- 2 Mb/s at 125 MHz
    T3_PROBE_CYCLES    : positive := 250_000;       -- 2 ms
    T3_LOSS_CYCLES     : positive := 1_250_000;     -- 10 ms
    REPROBE_CYCLES     : positive := 250_000_000;   -- 2 s
    PIN_STEP_CYCLES    : positive := 250;           -- 2 us per pin change step
    MK1_SKIP_FRAMES    : natural  := 2
  );
  port (
    clk        : in  std_logic;
    kio8_o     : out std_logic := '0';
    kio8_oe    : out std_logic := '0';
    kio8_i     : in  std_logic;               -- SDA in MK-II mode
    kio9_o     : out std_logic := '0';
    kio9_oe    : out std_logic := '0';
    kio10      : in  std_logic;
    leds       : in  std_logic_vector(95 downto 0);
    pressed    : out std_logic_vector(79 downto 0) := (others => '0');
    strobe     : out std_logic := '0';
    -- 0 none, 1 MK-I, 2 MK-II, 3 type 3
    kbd_type   : out std_logic_vector(1 downto 0);
    kbd_commit : out std_logic_vector(31 downto 0) := (others => '0');
    probing    : out std_logic := '0'       -- type-3 probe/session owns the pins
  );
end entity;

architecture rtl of kbd_phys_host is
  -- P_ENTER: KIO9 low, then KIO8 low (PIN_STEP each); P_PROBE / P_T3: UART;
  -- P_LEAVE: KIO9 low, then KIO8 released; P_LEGACY: MK-I / MK-II
  type pstate_t is (P_ENTER, P_PROBE, P_T3, P_LEAVE, P_LEGACY);
  signal ps        : pstate_t := P_ENTER;
  signal step      : std_logic := '0';
  signal pcnt      : integer range 0 to REPROBE_CYCLES := 0;

  signal k10_s     : std_logic_vector(1 downto 0) := "00";
  signal mk1_mode  : std_logic := '0';
  signal det_cnt   : integer range 0 to MK2_DETECT_CYCLES := 0;
  signal mk2_en    : std_logic := '0';
  signal t3_en     : std_logic := '0';
  signal skip      : integer range 0 to MK1_SKIP_FRAMES := MK1_SKIP_FRAMES;
  signal m1_kio8, m1_kio9, t3_txd : std_logic;
  signal m1_pressed, m2_pressed, t3_pressed : std_logic_vector(79 downto 0);
  signal m1_stb, m2_stb, m2_present, t3_stb, t3_present : std_logic;
  signal m1_commit, m2_commit, t3_commit : std_logic_vector(31 downto 0);
  signal sda_low, scl_low : std_logic;
  signal type_r    : std_logic_vector(1 downto 0) := "00";
  signal was_t3    : std_logic := '0';
begin
  kbd_type <= type_r;

  mk1 : entity work.kbd_mk1_host
    generic map (HALF_CYCLES => MK1_HALF_CYCLES)
    port map (clk => clk, kio8 => m1_kio8, kio9 => m1_kio9, kio10 => kio10,
              leds => leds, pressed => m1_pressed, strobe => m1_stb,
              present => open, kbd_commit => m1_commit);

  mk2 : entity work.kbd_mk2_host
    generic map (QUARTER_CYCLES => MK2_QUARTER_CYCLES, REINIT_LOG2 => MK2_REINIT_LOG2,
                 CAPS_HOLD => MK2_CAPS_HOLD)
    port map (clk => clk, enable => mk2_en, sda_in => kio8_i, sda_low => sda_low,
              scl_low => scl_low, leds => leds, pressed => m2_pressed, strobe => m2_stb,
              present => m2_present, kbd_commit => m2_commit);

  t3 : entity work.kbd_t3_host
    generic map (BIT_CYCLES => T3_BIT_CYCLES, LOSS_CYCLES => T3_LOSS_CYCLES)
    port map (clk => clk, enable => t3_en, txd => t3_txd, rxd => kio10, leds => leds,
              lock_ovr => "0000", pressed => t3_pressed, strobe => t3_stb,
              present => t3_present, kbd_commit => t3_commit, kbd_date => open,
              locks => open, version => open, rx_errors => open);

  process (clk)
  begin
    if rising_edge(clk) then
      if ps = P_LEGACY then probing <= '0'; else probing <= '1'; end if;
      k10_s  <= k10_s(0) & kio10;
      strobe <= '0';
      if pcnt /= REPROBE_CYCLES then
        pcnt <= pcnt + 1;
      end if;

      case ps is
        when P_ENTER =>
          -- SCL (KIO9) low first, then SDA (KIO8): no START for an MK-II
          mk2_en <= '0';
          kio9_o <= '0'; kio9_oe <= '1';
          if step = '1' then
            kio8_o <= '0'; kio8_oe <= '1';
          end if;
          if pcnt = PIN_STEP_CYCLES then
            pcnt <= 0;
            if step = '0' then
              step <= '1';
            else
              step  <= '0';
              t3_en <= '1';
              ps    <= P_PROBE;
            end if;
          end if;

        when P_PROBE | P_T3 =>
          kio8_o <= '0';    kio8_oe <= '1';
          kio9_o <= t3_txd; kio9_oe <= '1';
          if t3_present = '1' then
            ps <= P_T3;
            pcnt <= 0;
            type_r <= "11";
            if t3_stb = '1' then
              pressed    <= t3_pressed;
              kbd_commit <= t3_commit;
              strobe     <= '1';
            end if;
          elsif ps = P_T3 or pcnt = T3_PROBE_CYCLES then
            -- lost (probe again) / no answer (legacy detection)
            was_t3 <= '0';
            if ps = P_T3 then
              was_t3  <= '1';
              type_r  <= "00";
              pressed <= (others => '0');
            end if;
            pcnt  <= 0;
            t3_en <= '0';
            ps    <= P_LEAVE;
          end if;

        when P_LEAVE =>
          -- SCL low (UART idle was high), then release SDA while SCL is low
          kio9_o <= '0'; kio9_oe <= '1';
          if step = '1' then
            kio8_oe <= '0';
          end if;
          if pcnt = PIN_STEP_CYCLES then
            pcnt <= 0;
            if step = '0' then
              step <= '1';
            else
              step <= '0';
              if was_t3 = '1' then
                ps <= P_ENTER;              -- lost type 3: probe again
              else
                ps <= P_LEGACY;
              end if;
              mk1_mode <= '0';
              det_cnt  <= 0;
              skip     <= MK1_SKIP_FRAMES;
            end if;
          end if;

        when P_LEGACY =>
          if k10_s(1) = '1' then
            det_cnt  <= 0;
            mk1_mode <= '1';
          elsif det_cnt /= MK2_DETECT_CYCLES then
            det_cnt <= det_cnt + 1;
          else
            mk1_mode <= '0';
          end if;
          mk2_en <= not mk1_mode;

          if mk1_mode = '1' then
            kio8_o <= m1_kio8; kio8_oe <= '1';
            kio9_o <= m1_kio9; kio9_oe <= '1';
            type_r <= "01";
            if m1_stb = '1' then
              if skip /= 0 then
                skip <= skip - 1;
              else
                pressed    <= m1_pressed;
                kbd_commit <= m1_commit;
                strobe     <= '1';
              end if;
            end if;
          else
            kio8_o <= '0'; kio8_oe <= sda_low;
            kio9_o <= '0'; kio9_oe <= scl_low;
            skip   <= MK1_SKIP_FRAMES;
            type_r <= m2_present & '0';
            if m2_stb = '1' then
              pressed    <= m2_pressed;
              kbd_commit <= m2_commit;
              strobe     <= '1';
            end if;
            if m2_present = '0' then
              pressed <= (others => '0');
            end if;
          end if;

          -- probe type 3 again: no keyboard or an MK-I, never an MK-II
          if m2_present = '1' and mk1_mode = '0' then
            pcnt <= 0;
          elsif pcnt = REPROBE_CYCLES then
            pcnt   <= 0;
            mk2_en <= '0';
            ps     <= P_ENTER;
          end if;
      end case;
    end if;
  end process;
end architecture;
