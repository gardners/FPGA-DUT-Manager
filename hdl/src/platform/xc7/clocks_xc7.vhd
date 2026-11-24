-- 100 MHz in -> 125 MHz (clk_sys), 125 MHz +90 deg (RGMII TXC), 200 MHz
-- (IDELAYCTRL reference). VCO 1000 MHz.
library ieee;
use ieee.std_logic_1164.all;
use work.xc7_prims_pkg.all;

entity clocks_xc7 is
  port (
    clk100   : in  std_logic;
    clk_sys  : out std_logic;
    clk_tx90 : out std_logic;
    clk_ref  : out std_logic;
    locked   : out std_logic
  );
end entity;

architecture rtl of clocks_xc7 is
  signal fb, fb_g, c0, c1, c2 : std_logic;
begin
  mmcm : MMCME2_BASE
    generic map (
      CLKIN1_PERIOD => 10.0, DIVCLK_DIVIDE => 1, CLKFBOUT_MULT_F => 10.0,
      CLKOUT0_DIVIDE_F => 8.0, CLKOUT0_PHASE => 0.0,
      CLKOUT1_DIVIDE => 8, CLKOUT1_PHASE => 90.0,
      CLKOUT2_DIVIDE => 5, CLKOUT2_PHASE => 0.0)
    port map (
      CLKOUT0 => c0, CLKOUT0B => open, CLKOUT1 => c1, CLKOUT1B => open,
      CLKOUT2 => c2, CLKOUT2B => open, CLKOUT3 => open, CLKOUT3B => open,
      CLKOUT4 => open, CLKOUT5 => open, CLKOUT6 => open,
      CLKFBOUT => fb, CLKFBOUTB => open, LOCKED => locked,
      CLKIN1 => clk100, PWRDWN => '0', RST => '0', CLKFBIN => fb_g);
  bfb : BUFG port map (O => fb_g, I => fb);
  b0  : BUFG port map (O => clk_sys, I => c0);
  b1  : BUFG port map (O => clk_tx90, I => c1);
  b2  : BUFG port map (O => clk_ref, I => c2);
end architecture;
