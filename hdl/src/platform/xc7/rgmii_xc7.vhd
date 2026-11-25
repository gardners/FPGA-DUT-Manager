-- RGMII <-> GMII-style byte interface for Artix-7 (ADR 0004).
-- PHY delays are strapped off on the Mimas A7 (RTL8211E RXDLY/TXDLY = 0):
--   TX: data via ODDR on clk_sys; TXC via ODDR on clk_tx90 (+90 deg, 2 ns).
--   RX: RXC (MRCC pin W19) -> MMCM (1:1, 125 MHz, CLKOUT0 at RX_PHASE,
--       BUFG feedback so the clock tree insertion delay is compensated) ->
--       BUFG -> IDDR. RXD/RX_CTL pass an IDELAYE2 (RX_IDELAY taps of 78 ps)
--       for fine trim. Replaces BUFG-only RXC, whose ~5.2 ns insertion made
--       the sample point depend on the BUFG route (issue 0019).
--       The MMCM is re-reset from clk_sys whenever it has not been locked for
--       ~1 ms (PHY reset, link down, cable change). Gigabit only: at 100 Mb/s
--       RXC is 25 MHz and the MMCM will not lock (issue 0018).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.xc7_prims_pkg.all;

entity rgmii_xc7 is
  generic (
    RX_IDELAY : integer := 0;         -- taps of ~78 ps (200 MHz reference)
    -- RX sample clock phase in MMCM steps of 5.625 deg (VCO 1000 MHz / 8).
    -- Calibrated on hardware by scanning builds (issue 0019).
    RX_PHASE_STEPS : integer := 22
  );
  port (
    clk_sys   : in  std_logic;   -- 125 MHz
    clk_tx90  : in  std_logic;   -- 125 MHz, +90 degrees
    -- pins
    rgmii_txc    : out std_logic;
    rgmii_tx_ctl : out std_logic;
    rgmii_txd    : out std_logic_vector(3 downto 0);
    rgmii_rxc    : in  std_logic;
    rgmii_rx_ctl : in  std_logic;
    rgmii_rxd    : in  std_logic_vector(3 downto 0);
    -- GMII side
    clk_rx    : out std_logic;
    rx_locked : out std_logic;   -- RX MMCM locked (clk_sys domain)
    rx_dv     : out std_logic;
    rx_er     : out std_logic;
    rxd       : out std_logic_vector(7 downto 0);
    tx_en     : in  std_logic;
    tx_er     : in  std_logic;
    txd       : in  std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of rgmii_xc7 is
  signal rxc_g   : std_logic;
  signal rx_fb, rx_fb_g, rx_c0, rx_lock : std_logic;
  signal mmcm_rst : std_logic := '1';
  signal lock_s   : std_logic_vector(1 downto 0) := "00";
  signal unlock_n : unsigned(17 downto 0) := (others => '0');
  signal rst_n    : unsigned(4 downto 0) := (others => '1');
  signal d_dly   : std_logic_vector(4 downto 0);
  signal d_in    : std_logic_vector(4 downto 0);
  signal q1, q2  : std_logic_vector(4 downto 0);
  signal tx_ctl2 : std_logic;
begin
  ---------------------------------------------------------------- TX
  tx_ctl2 <= tx_en xor tx_er;
  g_txd : for i in 0 to 3 generate
    o : ODDR generic map (DDR_CLK_EDGE => "SAME_EDGE", SRTYPE => "SYNC")
      port map (Q => rgmii_txd(i), C => clk_sys, CE => '1',
                D1 => txd(i), D2 => txd(i + 4), R => '0', S => '0');
  end generate;
  o_ctl : ODDR generic map (DDR_CLK_EDGE => "SAME_EDGE", SRTYPE => "SYNC")
    port map (Q => rgmii_tx_ctl, C => clk_sys, CE => '1',
              D1 => tx_en, D2 => tx_ctl2, R => '0', S => '0');
  o_clk : ODDR generic map (DDR_CLK_EDGE => "SAME_EDGE", SRTYPE => "SYNC")
    port map (Q => rgmii_txc, C => clk_tx90, CE => '1',
              D1 => '1', D2 => '0', R => '0', S => '0');

  ---------------------------------------------------------------- RX
  rmmcm : MMCME2_BASE
    generic map (
      CLKIN1_PERIOD => 8.0, DIVCLK_DIVIDE => 1, CLKFBOUT_MULT_F => 8.0,
      CLKOUT0_DIVIDE_F => 8.0, CLKOUT0_PHASE => real(RX_PHASE_STEPS) * 5.625)
    port map (
      CLKOUT0 => rx_c0, CLKOUT0B => open, CLKOUT1 => open, CLKOUT1B => open,
      CLKOUT2 => open, CLKOUT2B => open, CLKOUT3 => open, CLKOUT3B => open,
      CLKOUT4 => open, CLKOUT5 => open, CLKOUT6 => open,
      CLKFBOUT => rx_fb, CLKFBOUTB => open, LOCKED => rx_lock,
      CLKIN1 => rgmii_rxc, PWRDWN => '0', RST => mmcm_rst, CLKFBIN => rx_fb_g);
  bfb : BUFG port map (O => rx_fb_g, I => rx_fb);
  bg  : BUFG port map (O => rxc_g, I => rx_c0);
  clk_rx <= rxc_g;

  -- lock watchdog (clk_sys): 16-cycle reset pulse after ~1 ms without lock
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      lock_s <= lock_s(0) & rx_lock;
      if rst_n /= 0 then
        rst_n    <= rst_n - 1;
        mmcm_rst <= '1';
        unlock_n <= (others => '0');
      else
        mmcm_rst <= '0';
        if lock_s(1) = '1' then
          unlock_n <= (others => '0');
        elsif unlock_n = 2**18 - 1 then
          rst_n <= (others => '1');
        else
          unlock_n <= unlock_n + 1;
        end if;
      end if;
    end if;
  end process;
  rx_locked <= lock_s(1);

  d_in <= rgmii_rx_ctl & rgmii_rxd;
  g_rx : for i in 0 to 4 generate
    dl : IDELAYE2
      generic map (IDELAY_TYPE => "FIXED", IDELAY_VALUE => RX_IDELAY,
                   DELAY_SRC => "IDATAIN", REFCLK_FREQUENCY => 200.0,
                   SIGNAL_PATTERN => "DATA", HIGH_PERFORMANCE_MODE => "TRUE")
      port map (CNTVALUEOUT => open, DATAOUT => d_dly(i), C => '0', CE => '0',
                CINVCTRL => '0', DATAIN => '0', IDATAIN => d_in(i), INC => '0',
                LD => '0', LDPIPEEN => '0', REGRST => '0', CNTVALUEIN => "00000");
    id : IDDR generic map (DDR_CLK_EDGE => "SAME_EDGE_PIPELINED", SRTYPE => "SYNC")
      port map (Q1 => q1(i), Q2 => q2(i), C => rxc_g, CE => '1',
                D => d_dly(i), R => '0', S => '0');
  end generate;

  process (rxc_g)
  begin
    if rising_edge(rxc_g) then
      rxd   <= q2(3 downto 0) & q1(3 downto 0);
      rx_dv <= q1(4);
      rx_er <= q1(4) xor q2(4);
    end if;
  end process;
end architecture;
