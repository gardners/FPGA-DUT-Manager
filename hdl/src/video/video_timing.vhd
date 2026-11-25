-- Raster timing generator. Default 720x480p60 (CEA-861 mode 2/3, 27 MHz,
-- 858 x 525, negative syncs), the MEGA65 NTSC mode (issue 0027).
-- 720x576p50 (mode 17): H 12/64/68, V 576 5/5/39.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_timing is
  generic (
    H_ACTIVE : positive := 720; H_FP : positive := 16; H_SYNC : positive := 62; H_BP : positive := 60;
    V_ACTIVE : positive := 480; V_FP : positive := 9;  V_SYNC : positive := 6;  V_BP : positive := 30;
    SYNC_POL : std_logic := '0'           -- level during sync
  );
  port (
    clk    : in  std_logic;
    x      : out unsigned(10 downto 0);   -- pixel position (valid when de)
    y      : out unsigned(10 downto 0);
    de     : out std_logic;
    hs, vs : out std_logic;
    frame_start : out std_logic           -- one cycle at x=0, y=0
  );
end entity;

architecture rtl of video_timing is
  constant H_TOTAL : natural := H_ACTIVE + H_FP + H_SYNC + H_BP;
  constant V_TOTAL : natural := V_ACTIVE + V_FP + V_SYNC + V_BP;
  signal hc : unsigned(10 downto 0) := (others => '0');
  signal vc : unsigned(10 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if hc = H_TOTAL - 1 then
        hc <= (others => '0');
        if vc = V_TOTAL - 1 then
          vc <= (others => '0');
        else
          vc <= vc + 1;
        end if;
      else
        hc <= hc + 1;
      end if;
      x  <= hc;
      y  <= vc;
      if hc < H_ACTIVE and vc < V_ACTIVE then de <= '1'; else de <= '0'; end if;
      if hc >= H_ACTIVE + H_FP and hc < H_ACTIVE + H_FP + H_SYNC then hs <= SYNC_POL; else hs <= not SYNC_POL; end if;
      if vc >= V_ACTIVE + V_FP and vc < V_ACTIVE + V_FP + V_SYNC then vs <= SYNC_POL; else vs <= not SYNC_POL; end if;
      if hc = 0 and vc = 0 then frame_start <= '1'; else frame_start <= '0'; end if;
    end if;
  end process;
end architecture;
