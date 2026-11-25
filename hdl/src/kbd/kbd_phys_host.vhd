-- kbd_phys_host: the master's own MEGA65 keyboard, MK-I or MK-II, detected
-- as mega65r6.vhdl does (ADR 0006, issue 0009): start in MK-II mode; KIO10
-- high at any time selects MK-I at once (an MK-I keyboard drives KIO10 high
-- at idle; an MK-II ties it low); KIO10 low for MK2_DETECT_CYCLES returns to
-- MK-II (5000 cycles at 40.5 MHz upstream = 123 us).
--
-- Pins: MK-I mode drives KIO8 (clock/sync) and KIO9 (LED data) push-pull;
-- MK-II mode uses KIO8 = SDA and KIO9 = SCL open drain (o = '0', oe = pull
-- low). The top level turns o/oe into tri-state buffers. All pin outputs
-- and results are registered here (one 2:1 mux level, IOB-friendly).
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
    MK2_CAPS_HOLD      : positive := 510
  );
  port (
    clk        : in  std_logic;
    kio8_o     : out std_logic;
    kio8_oe    : out std_logic;
    kio8_i     : in  std_logic;               -- SDA in MK-II mode
    kio9_o     : out std_logic;
    kio9_oe    : out std_logic;
    kio10      : in  std_logic;
    leds       : in  std_logic_vector(95 downto 0);
    pressed    : out std_logic_vector(79 downto 0);
    strobe     : out std_logic;
    kbd_type   : out std_logic_vector(1 downto 0);  -- 0 none, 1 MK-I, 2 MK-II
    kbd_commit : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of kbd_phys_host is
  signal k10_s     : std_logic_vector(1 downto 0) := "00";
  signal mk1_mode  : std_logic := '0';
  signal det_cnt   : integer range 0 to MK2_DETECT_CYCLES := 0;
  signal mk2_en    : std_logic := '0';
  signal m1_kio8, m1_kio9 : std_logic;
  signal m1_pressed, m2_pressed : std_logic_vector(79 downto 0);
  signal m1_stb, m2_stb, m2_present : std_logic;
  signal m1_commit, m2_commit : std_logic_vector(31 downto 0);
  signal sda_low, scl_low : std_logic;
begin
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

  process (clk)
  begin
    if rising_edge(clk) then
      k10_s <= k10_s(0) & kio10;
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
        pressed    <= m1_pressed;
        strobe     <= m1_stb;
        kbd_type   <= "01";
        kbd_commit <= m1_commit;
      else
        kio8_o <= '0'; kio8_oe <= sda_low;
        kio9_o <= '0'; kio9_oe <= scl_low;
        pressed    <= m2_pressed;
        strobe     <= m2_stb;
        kbd_type   <= m2_present & '0';
        kbd_commit <= m2_commit;
        if m2_present = '0' then
          pressed <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture;
