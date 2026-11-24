-- Component declarations for the 7-series primitives we instantiate.
-- Declared locally (no unisim library) so the same source works with
-- GHDL+yosys (unbound components become black boxes mapped by
-- synth_xilinx/nextpnr) and with Vivado (resolved to primitives by name).
library ieee;
use ieee.std_logic_1164.all;

package xc7_prims_pkg is
  component BUFG
    port (O : out std_logic; I : in std_logic);
  end component;

  component MMCME2_BASE
    generic (
      BANDWIDTH          : string := "OPTIMIZED";
      CLKFBOUT_MULT_F    : real := 5.0;
      CLKFBOUT_PHASE     : real := 0.0;
      CLKIN1_PERIOD      : real := 0.0;
      CLKOUT0_DIVIDE_F   : real := 1.0;
      CLKOUT1_DIVIDE     : integer := 1;
      CLKOUT2_DIVIDE     : integer := 1;
      CLKOUT0_PHASE      : real := 0.0;
      CLKOUT1_PHASE      : real := 0.0;
      CLKOUT2_PHASE      : real := 0.0;
      DIVCLK_DIVIDE      : integer := 1;
      STARTUP_WAIT       : boolean := false
    );
    port (
      CLKOUT0, CLKOUT0B, CLKOUT1, CLKOUT1B, CLKOUT2, CLKOUT2B, CLKOUT3,
      CLKOUT3B, CLKOUT4, CLKOUT5, CLKOUT6, CLKFBOUT, CLKFBOUTB, LOCKED : out std_logic;
      CLKIN1, PWRDWN, RST, CLKFBIN : in std_logic
    );
  end component;

  component ODDR
    generic (
      DDR_CLK_EDGE : string := "OPPOSITE_EDGE";
      INIT         : bit := '0';
      SRTYPE       : string := "SYNC"
    );
    port (Q : out std_logic; C, CE, D1, D2, R, S : in std_logic);
  end component;

  component IDDR
    generic (
      DDR_CLK_EDGE : string := "OPPOSITE_EDGE";
      INIT_Q1      : bit := '0';
      INIT_Q2      : bit := '0';
      SRTYPE       : string := "SYNC"
    );
    port (Q1, Q2 : out std_logic; C, CE, D, R, S : in std_logic);
  end component;

  component IDELAYE2
    generic (
      CINVCTRL_SEL          : string := "FALSE";
      DELAY_SRC             : string := "IDATAIN";
      HIGH_PERFORMANCE_MODE : string := "FALSE";
      IDELAY_TYPE           : string := "FIXED";
      IDELAY_VALUE          : integer := 0;
      PIPE_SEL              : string := "FALSE";
      REFCLK_FREQUENCY      : real := 200.0;
      SIGNAL_PATTERN        : string := "DATA"
    );
    port (
      CNTVALUEOUT : out std_logic_vector(4 downto 0);
      DATAOUT     : out std_logic;
      C, CE, CINVCTRL, DATAIN, IDATAIN, INC, LD, LDPIPEEN, REGRST : in std_logic;
      CNTVALUEIN  : in std_logic_vector(4 downto 0)
    );
  end component;

  component IDELAYCTRL
    port (RDY : out std_logic; REFCLK, RST : in std_logic);
  end component;
end package;
