-- seg7_status: Mimas A7 seven-segment status (active-low segments/enables).
-- Until every enabled endpoint has an address: blinking "dHCP".
-- Then: DUT ID of the P12 half, '-', DUT ID of the P13 half (hex), blank.
-- Segment bit order assumed seg(0)=a .. seg(6)=g, seg(7)=dp; digit 0 =
-- enable(0). Both to be verified on hardware (issue 0013). V2.0 boards have
-- only three digits; the fourth is blank anyway.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seg7_status is
  generic (CLK_HZ : positive := 125_000_000);
  port (
    clk      : in  std_logic;
    have_ip  : in  std_logic;               -- all enabled endpoints addressed
    id0, id1 : in  unsigned(3 downto 0);
    seg      : out std_logic_vector(7 downto 0);
    seg_en   : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of seg7_status is
  constant SCAN : positive := CLK_HZ / 4000;      -- 1 kHz per digit
  signal cnt   : integer range 0 to SCAN - 1 := 0;
  signal digit : unsigned(1 downto 0) := (others => '0');
  signal blink : unsigned(23 downto 0) := (others => '0');

  -- segments gfedcba (1 = lit)
  function hex7(v : unsigned(3 downto 0)) return std_logic_vector is
  begin
    case to_integer(v) is
      when 0 => return "0111111"; when 1 => return "0000110"; when 2 => return "1011011";
      when 3 => return "1001111"; when 4 => return "1100110"; when 5 => return "1101101";
      when 6 => return "1111101"; when 7 => return "0000111"; when 8 => return "1111111";
      when 9 => return "1101111"; when 10 => return "1110111"; when 11 => return "1111100";
      when 12 => return "0111001"; when 13 => return "1011110"; when 14 => return "1111001";
      when others => return "1110001";
    end case;
  end function;
  constant CH_d : std_logic_vector(6 downto 0) := "1011110";
  constant CH_H : std_logic_vector(6 downto 0) := "1110110";
  constant CH_C : std_logic_vector(6 downto 0) := "0111001";
  constant CH_P : std_logic_vector(6 downto 0) := "1110011";
  constant CH_DASH : std_logic_vector(6 downto 0) := "1000000";
  constant CH_OFF  : std_logic_vector(6 downto 0) := "0000000";
begin
  process (clk)
    variable lit : std_logic_vector(6 downto 0);
  begin
    if rising_edge(clk) then
      blink <= blink + 1;
      if cnt = SCAN - 1 then
        cnt <= 0;
        digit <= digit + 1;
      else
        cnt <= cnt + 1;
      end if;
      if have_ip = '0' then
        case to_integer(digit) is
          when 0 => lit := CH_d; when 1 => lit := CH_H;
          when 2 => lit := CH_C; when others => lit := CH_P;
        end case;
        if blink(blink'high) = '1' then lit := CH_OFF; end if;
      else
        case to_integer(digit) is
          when 0 => lit := hex7(id0); when 1 => lit := CH_DASH;
          when 2 => lit := hex7(id1); when others => lit := CH_OFF;
        end case;
      end if;
      seg <= '1' & not lit;                         -- dp off
      seg_en <= (others => '1');
      seg_en(to_integer(digit)) <= '0';
    end if;
  end process;
end architecture;
