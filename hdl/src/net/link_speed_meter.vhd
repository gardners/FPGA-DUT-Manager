-- link_speed_meter: Ethernet link speed from the RGMII RX clock (issue 0070).
--
-- No MDIO: the RTL8211E's RXC runs at 125 MHz (1000BASE-T), 25 MHz (100) or
-- 2.5 MHz (10), and stops (or floats) while the PHY is in reset / powered
-- down. A 3-bit counter in the RXC domain gives a square wave at RXC/8; its
-- bit is synchronised into clk (2 flip-flops, a single bit, so no gray code
-- is needed and a stopped RXC simply leaves it static) and its transitions
-- (RXC/4 per second) are counted over 2**WIN_LOG2 clk cycles. Each window is
-- classified against thresholds roughly geometrically between the nominal
-- rates (>62.5 MHz = 1000, >8 MHz = 100, >0.5 MHz = 10, else none);
-- `speed` changes only after DEBOUNCE + 1 consecutive windows agree.
-- With CLK_HZ = 125 MHz and WIN_LOG2 = 15 a window is 262 us (1000BASE-T:
-- 8192 transitions per window) and the output settles in ~1 ms.
--
-- Speed code (heartbeat link block, ADR 0005 section 3a):
--   0 none, 1 = 10 Mb/s, 2 = 100 Mb/s, 3 = 1000 Mb/s.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity link_speed_meter is
  generic (
    CLK_HZ   : positive := 125_000_000;
    WIN_LOG2 : positive := 15;      -- window = 2**WIN_LOG2 clk cycles
    DEBOUNCE : positive := 4        -- equal windows before speed changes
  );
  port (
    rxc   : in  std_logic;          -- RX clock from the PHY (may stop)
    clk   : in  std_logic;          -- free-running system clock
    speed : out std_logic_vector(1 downto 0);
    count : out unsigned(WIN_LOG2 - 1 downto 0)   -- last window's transitions
  );
end entity;

architecture rtl of link_speed_meter is
  constant QW : natural := 2 ** WIN_LOG2 / 4;   -- transitions per window if RXC = CLK_HZ
  -- transitions per window at f_hz (integer, no overflow up to WIN_LOG2 = 19)
  function thr(f_khz : natural) return natural is
  begin
    return QW * f_khz / (CLK_HZ / 1000);
  end function;
  constant T_1000 : natural := thr(62_500);
  constant T_100  : natural := thr(8_000);
  constant T_10   : natural := thr(500);

  signal div   : unsigned(2 downto 0) := (others => '0');
  signal s     : std_logic_vector(2 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of s : signal is "TRUE";
  signal win   : unsigned(WIN_LOG2 - 1 downto 0) := (others => '0');
  signal cnt   : unsigned(WIN_LOG2 - 1 downto 0) := (others => '0');
  signal last  : std_logic_vector(1 downto 0) := "00";
  signal agree : integer range 0 to DEBOUNCE - 1 := 0;
  signal spd   : std_logic_vector(1 downto 0) := "00";
  signal cnt_q : unsigned(WIN_LOG2 - 1 downto 0) := (others => '0');
begin
  -- RXC domain: free-running divider; div(2) is the only signal crossing
  process (rxc)
  begin
    if rising_edge(rxc) then
      div <= div + 1;
    end if;
  end process;

  process (clk)
    variable cls : std_logic_vector(1 downto 0);
  begin
    if rising_edge(clk) then
      s <= s(1 downto 0) & div(2);
      if win = 2 ** WIN_LOG2 - 1 then
        if cnt > T_1000 then    cls := "11";
        elsif cnt > T_100 then  cls := "10";
        elsif cnt > T_10 then   cls := "01";
        else                    cls := "00";
        end if;
        cnt_q <= cnt;
        cnt   <= (others => '0');
        if cls = last then
          if agree = DEBOUNCE - 1 then
            spd <= cls;
          else
            agree <= agree + 1;
          end if;
        else
          last  <= cls;
          agree <= 0;
          if DEBOUNCE = 1 then spd <= cls; end if;
        end if;
      elsif s(2) /= s(1) and cnt /= 2 ** WIN_LOG2 - 1 then
        cnt <= cnt + 1;
      end if;
      win <= win + 1;
    end if;
  end process;
  speed <= spd;
  count <= cnt_q;
end architecture;
