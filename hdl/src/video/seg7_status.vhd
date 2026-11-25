-- seg7_status: Mimas A7 seven-segment status (active-low segments/enables).
-- Until every enabled endpoint has an address: blinking "dHCP".
-- Then: P12 DUT ID (1 hex digit), '-', P13 DUT ID (2 hex digits, 1m), e.g.
-- "0-10" (issue 0026).
-- Mimas A7 V3.1 schematic (sheet 12): pins 7SEG_0..7 drive segments
-- G, F, A, B, DP, C, D, E of a common-anode display; all active low.
-- Digit n is enable(n) = DIG(n+1) via a PNP (active low).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seg7_status is
  generic (CLK_HZ : positive := 125_000_000);
  port (
    clk      : in  std_logic;
    have_ip  : in  std_logic;               -- all enabled endpoints addressed
    id0, id1 : in  unsigned(4 downto 0);     -- 0x0n, 0x1m
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
          when 0 => lit := hex7(id0(3 downto 0)); when 1 => lit := CH_DASH;
          when 2 => lit := hex7("000" & id1(4 downto 4));
          when others => lit := hex7(id1(3 downto 0));
        end case;
      end if;
      -- lit is gfedcba; map to the board's 7SEG_0..7 = G F A B DP C D E
      seg(0) <= not lit(6);   -- G
      seg(1) <= not lit(5);   -- F
      seg(2) <= not lit(0);   -- A
      seg(3) <= not lit(1);   -- B
      seg(4) <= '1';          -- DP off
      seg(5) <= not lit(2);   -- C
      seg(6) <= not lit(3);   -- D
      seg(7) <= not lit(4);   -- E
      seg_en <= (others => '1');
      seg_en(to_integer(digit)) <= '0';
    end if;
  end process;
end architecture;
