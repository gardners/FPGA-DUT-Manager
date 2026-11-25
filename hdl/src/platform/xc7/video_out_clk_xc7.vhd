-- video_out_clk_xc7: DVI transmitter clocks for HDMI OUT (issue 0032).
--
-- Console: the local 27 MHz / 135 MHz pair from clocks_video_xc7 (MMCM
-- outputs, unbuffered here). Passthrough: a PLL on the HDMI IN recovered
-- pixel clock (dvi2rgb PixelClk, already on a BUFG) makes a phase-aligned
-- 1x / 5x pair. dvi2rgb's own SerialClk is a BUFIO (I/O clocks of the HDMI
-- IN bank only) and cannot clock fabric, so it cannot feed the TX.
-- PLL: VCO = 35 x f_pix (945 MHz at 27 MHz; 800..1600 MHz -> 22.9..45.7 MHz,
-- covering dvi2rgb's kClkRange 5 band from 25 MHz), /35 = 1x, /7 = 5x.
--
-- Two BUFGCTRLs select console (I0) or passthrough (I1) on the S pins
-- (asynchronous-safe select; CE tied high), glitch free. IGNORE1 = 1: when
-- switching back to the console, do not wait for a falling edge of the
-- passthrough clock, which may already have stopped (HDMI IN unplugged,
-- PLL in reset) - otherwise the mux could hang. The console clock never
-- stops, so IGNORE0 = 0 keeps the switch to passthrough glitch free. The
-- sequencer (video_pt_ctrl) holds the TX in reset across every switch.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use work.xc7_prims_pkg.all;

entity video_out_clk_xc7 is
  port (
    con_pix, con_pix5 : in  std_logic;   -- console MMCM outputs (unbuffered)
    vin_pclk          : in  std_logic;   -- HDMI IN recovered pixel clock (BUFG)
    pll_rst           : in  std_logic;   -- async
    sel               : in  std_logic;   -- 1 = passthrough
    pll_locked        : out std_logic;
    tx_pix, tx_pix5   : out std_logic    -- to dvi_tx_xc7 (global clocks)
  );
end entity;

architecture rtl of video_out_clk_xc7 is
  signal fb, p1, p5, nsel : std_logic;
begin
  pll : PLLE2_BASE
    generic map (CLKIN1_PERIOD => 37.037, DIVCLK_DIVIDE => 1, CLKFBOUT_MULT => 35,
                 CLKOUT0_DIVIDE => 35, CLKOUT1_DIVIDE => 7)
    port map (CLKOUT0 => p1, CLKOUT1 => p5, CLKOUT2 => open, CLKOUT3 => open,
              CLKOUT4 => open, CLKOUT5 => open, CLKFBOUT => fb, LOCKED => pll_locked,
              CLKIN1 => vin_pclk, PWRDWN => '0', RST => pll_rst, CLKFBIN => fb);

  nsel <= not sel;
  mpix : BUFGCTRL
    generic map (INIT_OUT => 0, PRESELECT_I0 => true, PRESELECT_I1 => false)
    port map (O => tx_pix, I0 => con_pix, I1 => p1, S0 => nsel, S1 => sel,
              CE0 => '1', CE1 => '1', IGNORE0 => '0', IGNORE1 => '1');
  mser : BUFGCTRL
    generic map (INIT_OUT => 0, PRESELECT_I0 => true, PRESELECT_I1 => false)
    port map (O => tx_pix5, I0 => con_pix5, I1 => p5, S0 => nsel, S1 => sel,
              CE0 => '1', CE1 => '1', IGNORE0 => '0', IGNORE1 => '1');
end architecture;
