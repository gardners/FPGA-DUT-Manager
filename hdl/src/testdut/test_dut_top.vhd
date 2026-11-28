-- test_dut_top: bitstream for a second Mimas A7 acting as a known,
-- instrumented DUT on the supervisor's DUT0 port (issue 0068).
--
-- Wiring: straight jumpers P12 rows 3-7 -> P12 rows 3-7; the same balls as
-- the supervisor's DUT0 port, each in the opposite direction:
--   J21 UART TX out    K22 UART RX in (the supervisor's TX)
--   G20 "powered" out  (driven '1'; '0' while DIP switch 0 reads '1')
--   J20 TCK in, J19 TMS in, H20 TDI in, K21 TDO out (soft TAP)
--   H19 spare, input without pull (shown on digit 3's decimal point)
-- The UART TX is mirrored onto the board's own USB UART (FTDI channel A).
--
-- LEDs: 0 heartbeat (1 Hz), 1 K22 level, 2 K22 continuously low >= 10 ms,
-- 3 byte received, 4 byte sent, 5 TCK activity (each stretched ~50 ms),
-- 6 TAP not in Test-Logic-Reset, 7 G20 "powered" output level.
-- 7-segment: "tdut" normally, "r Lo" while K22 has been low >= 10 ms;
-- digit 0's decimal point = heartbeat, digit 3's = H19 level.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity test_dut_top is
  generic (
    CLK_PER_MS    : positive := 100_000;
    MS_PER_STATUS : positive := 1000;
    BAUD_INC      : unsigned(31 downto 0) := x"051E_B852";  -- 2 Mbaud @ 100 MHz
    IDCODE        : std_logic_vector(31 downto 0) := x"7E57D001";
    BUILD_ID      : std_logic_vector(31 downto 0) := x"00000000"  -- vivado/build_test_dut.tcl
  );
  port (
    clk100      : in  std_logic;
    led         : out std_logic_vector(7 downto 0);
    seg         : out std_logic_vector(7 downto 0);
    seg_en      : out std_logic_vector(3 downto 0);
    dip         : in  std_logic_vector(7 downto 0);
    usb_uart_tx : out std_logic;
    dut_uart_tx : out std_logic;          -- J21
    dut_uart_rx : in  std_logic;          -- K22
    dut_powered : out std_logic;          -- G20
    dut_tck     : in  std_logic;          -- J20
    dut_tms     : in  std_logic;          -- J19
    dut_tdi     : in  std_logic;          -- H20
    dut_tdo     : out std_logic;          -- K21
    dut_spare   : in  std_logic           -- H19
  );
end entity;

architecture rtl of test_dut_top is
  signal clk : std_logic;
  signal txd, rx_lvl, rx_stb, tx_stb, sec_stb, tck_stb, in_tlr : std_logic;
  signal low_ms : unsigned(31 downto 0);
  signal rx_low : std_logic;
  signal pow    : std_logic := '0';
  signal dip_s, spare_s : std_logic_vector(1 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of dip_s, spare_s : signal is "TRUE";

  signal ms_cnt : integer range 0 to CLK_PER_MS - 1 := 0;
  signal hb_cnt : integer range 0 to 499 := 0;
  signal hb     : std_logic := '0';
  signal st_rx, st_tx, st_tck : integer range 0 to 63 := 0;

  signal digit : unsigned(1 downto 0) := (others => '0');

  -- segments gfedcba (1 = lit), as seg7_status
  constant CH_t : std_logic_vector(6 downto 0) := "1111000";
  constant CH_d : std_logic_vector(6 downto 0) := "1011110";
  constant CH_u : std_logic_vector(6 downto 0) := "0011100";
  constant CH_r : std_logic_vector(6 downto 0) := "1010000";
  constant CH_L : std_logic_vector(6 downto 0) := "0111000";
  constant CH_o : std_logic_vector(6 downto 0) := "1011100";
  constant CH_OFF : std_logic_vector(6 downto 0) := "0000000";
begin
  clk <= clk100;   -- Vivado inserts the global buffer

  uart : entity work.testdut_uart
    generic map (CLK_PER_MS => CLK_PER_MS, MS_PER_STATUS => MS_PER_STATUS, BAUD_INC => BAUD_INC,
                 BUILD_ID => BUILD_ID)
    port map (clk => clk, rxd => dut_uart_rx, txd => txd, rx_level => rx_lvl,
              rx_low_ms => low_ms, rx_stb => rx_stb, tx_stb => tx_stb, sec_stb => sec_stb);

  tap : entity work.jtag_tap_soft
    generic map (IDCODE => IDCODE)
    port map (clk => clk, tck => dut_tck, tms => dut_tms, tdi => dut_tdi, tdo => dut_tdo,
              in_tlr => in_tlr, tck_stb => tck_stb, user_dr => open);

  dut_uart_tx <= txd;
  usb_uart_tx <= txd;
  dut_powered <= pow;
  -- low_ms is BCD: >= 10 ms means any digit above the units digit set
  rx_low <= '1' when rx_lvl = '0' and low_ms(31 downto 4) /= 0 else '0';

  process (clk)
    variable ms_tick : boolean;
    variable lit : std_logic_vector(6 downto 0);
    variable dp  : std_logic;
  begin
    if rising_edge(clk) then
      dip_s   <= dip_s(0) & dip(0);
      spare_s <= spare_s(0) & dut_spare;
      pow     <= not dip_s(1);

      ms_tick := ms_cnt = CLK_PER_MS - 1;
      if ms_tick then
        ms_cnt <= 0;
        if hb_cnt = 499 then
          hb_cnt <= 0;
          hb     <= not hb;
        else
          hb_cnt <= hb_cnt + 1;
        end if;
        if st_rx /= 0 then st_rx <= st_rx - 1; end if;
        if st_tx /= 0 then st_tx <= st_tx - 1; end if;
        if st_tck /= 0 then st_tck <= st_tck - 1; end if;
      else
        ms_cnt <= ms_cnt + 1;
      end if;
      if rx_stb = '1' then st_rx <= 50; end if;
      if tx_stb = '1' then st_tx <= 50; end if;
      if tck_stb = '1' then st_tck <= 50; end if;

      led(0) <= hb;
      led(1) <= rx_lvl;
      led(2) <= rx_low;
      led(3) <= '1' when st_rx /= 0 else '0';
      led(4) <= '1' when st_tx /= 0 else '0';
      led(5) <= '1' when st_tck /= 0 else '0';
      led(6) <= not in_tlr;
      led(7) <= pow;

      -- display scan, about 1 kHz per digit
      if ms_tick then
        digit <= digit + 1;
      end if;
      if rx_low = '1' then
        case to_integer(digit) is
          when 0 => lit := CH_r; when 1 => lit := CH_OFF;
          when 2 => lit := CH_L; when others => lit := CH_o;
        end case;
      else
        case to_integer(digit) is
          when 0 => lit := CH_t; when 1 => lit := CH_d;
          when 2 => lit := CH_u; when others => lit := CH_t;
        end case;
      end if;
      case to_integer(digit) is
        when 0      => dp := hb;
        when 3      => dp := spare_s(1);
        when others => dp := '0';
      end case;
      -- board pins 7SEG_0..7 = G F A B DP C D E, active low
      seg(0) <= not lit(6);
      seg(1) <= not lit(5);
      seg(2) <= not lit(0);
      seg(3) <= not lit(1);
      seg(4) <= not dp;
      seg(5) <= not lit(2);
      seg(6) <= not lit(3);
      seg(7) <= not lit(4);
      seg_en <= (others => '1');
      seg_en(to_integer(digit)) <= '0';
    end if;
  end process;
end architecture;
