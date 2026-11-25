-- 100 MHz -> 27 MHz pixel and 135 MHz (5x) TMDS bit-pair clock.
-- VCO = 100 / 5 * 54 = 1080 MHz; /40 = 27, /8 = 135.
library ieee;
use ieee.std_logic_1164.all;
use work.xc7_prims_pkg.all;

entity clocks_video_xc7 is
  port (
    clk100    : in  std_logic;
    clk_pix   : out std_logic;
    clk_pix5  : out std_logic;
    locked    : out std_logic
  );
end entity;

architecture rtl of clocks_video_xc7 is
  signal fb, fb_g, c0, c1 : std_logic;
begin
  mmcm : MMCME2_BASE
    generic map (
      CLKIN1_PERIOD => 10.0, DIVCLK_DIVIDE => 5, CLKFBOUT_MULT_F => 54.0,
      CLKOUT0_DIVIDE_F => 40.0, CLKOUT1_DIVIDE => 8)
    port map (
      CLKOUT0 => c0, CLKOUT0B => open, CLKOUT1 => c1, CLKOUT1B => open,
      CLKOUT2 => open, CLKOUT2B => open, CLKOUT3 => open, CLKOUT3B => open,
      CLKOUT4 => open, CLKOUT5 => open, CLKOUT6 => open,
      CLKFBOUT => fb, CLKFBOUTB => open, LOCKED => locked,
      CLKIN1 => clk100, PWRDWN => '0', RST => '0', CLKFBIN => fb_g);
  bfb : BUFG port map (O => fb_g, I => fb);
  b0  : BUFG port map (O => clk_pix, I => c0);
  b1  : BUFG port map (O => clk_pix5, I => c1);
end architecture;
