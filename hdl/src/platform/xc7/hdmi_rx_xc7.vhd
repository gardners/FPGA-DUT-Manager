-- hdmi_rx_xc7: Mimas A7 HDMI IN (DVI 1.0 sink) via Digilent dvi2rgb
-- (third_party/digilent-dvi2rgb, BSD-3; issue 0022). 27 MHz pixel clock
-- range (kClkRange 5: >= 25 MHz), no ILA debug cores, no EDID emulation
-- yet (DDC lines released); hot-plug detect asserted.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;

entity hdmi_rx_xc7 is
  port (
    -- pins
    tmds_clk_p, tmds_clk_n : in std_logic;
    tmds_p, tmds_n         : in std_logic_vector(2 downto 0);
    hpd                    : out std_logic;
    -- 200 MHz IDELAYCTRL reference, reset while it is not stable
    ref_clk, ref_rst       : in std_logic;
    -- video out (pclk domain)
    pclk                   : out std_logic;
    rgb                    : out std_logic_vector(23 downto 0);  -- R & G & B
    de, hs, vs             : out std_logic;
    locked                 : out std_logic
  );
end entity;

architecture rtl of hdmi_rx_xc7 is
  signal d : std_logic_vector(23 downto 0);
begin
  hpd <= '1';
  dvi : entity work.dvi2rgb
    generic map (kEmulateDDC => false, kRstActiveHigh => true, kAddBUFG => true,
                 kClkRange => 5, kDebug => false)
    port map (
      TMDS_Clk_p => tmds_clk_p, TMDS_Clk_n => tmds_clk_n,
      TMDS_Data_p => tmds_p, TMDS_Data_n => tmds_n,
      RefClk => ref_clk, aRst => ref_rst, aRst_n => not ref_rst,
      vid_pData => d, vid_pVDE => de, vid_pHSync => hs, vid_pVSync => vs,
      PixelClk => pclk, SerialClk => open, aPixelClkLckd => open, pLocked => locked,
      SDA_I => '1', SDA_O => open, SDA_T => open,
      SCL_I => '1', SCL_O => open, SCL_T => open,
      pRst => '0', pRst_n => '1');
  -- dvi2rgb orders vid_pData as R(23:16), B(15:8), G(7:0) (DVI channel order)
  rgb <= d(23 downto 16) & d(7 downto 0) & d(15 downto 8);
end architecture;
