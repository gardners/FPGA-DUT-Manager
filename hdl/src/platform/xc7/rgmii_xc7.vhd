-- RGMII <-> GMII-style byte interface for Artix-7 (ADR 0004).
-- PHY delays are strapped off on the Mimas A7 (RTL8211E RXDLY/TXDLY = 0):
--   TX: data via ODDR on clk_sys; TXC via ODDR on clk_tx90 (+90 deg, 2 ns).
--   RX: RXD/RX_CTL delayed by IDELAYE2 (fixed RX_IDELAY taps of 78 ps),
--       captured by IDDR on the BUFG'd RXC.
library ieee;
use ieee.std_logic_1164.all;
use work.xc7_prims_pkg.all;

entity rgmii_xc7 is
  generic (RX_IDELAY : integer := 26);   -- ~2.0 ns at 200 MHz reference
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
  bg : BUFG port map (O => rxc_g, I => rgmii_rxc);
  clk_rx <= rxc_g;

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
