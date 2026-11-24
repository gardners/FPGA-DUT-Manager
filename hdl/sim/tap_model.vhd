-- Behavioural IEEE 1149.1 TAP with a 32-bit IDCODE data register (sim only).
library ieee;
use ieee.std_logic_1164.all;

entity tap_model is
  generic (IDCODE : std_logic_vector(31 downto 0) := x"0362C093");
  port (
    tck, tms, tdi : in  std_logic;
    tdo           : out std_logic := '0';
    rises         : out natural
  );
end entity;

architecture sim of tap_model is
  type tap_t is (TLR, RTI, SELDR, CAPDR, SHDR, EX1DR, PADR, EX2DR, UPDR,
                 SELIR, CAPIR, SHIR, EX1IR, PAIR, EX2IR, UPIR);
  signal tap : tap_t := TLR;
  signal dr  : std_logic_vector(31 downto 0) := (others => '0');
  signal n   : natural := 0;
begin
  rises <= n;
  process (tck)
  begin
    if rising_edge(tck) then
      n <= n + 1;
      case tap is
        when TLR   => if tms = '0' then tap <= RTI; end if;
        when RTI   => if tms = '1' then tap <= SELDR; end if;
        when SELDR => if tms = '1' then tap <= SELIR; else tap <= CAPDR; end if;
        when CAPDR => dr <= IDCODE; if tms = '1' then tap <= EX1DR; else tap <= SHDR; end if;
        when SHDR  => dr <= tdi & dr(31 downto 1); if tms = '1' then tap <= EX1DR; end if;
        when EX1DR => if tms = '1' then tap <= UPDR; else tap <= PADR; end if;
        when PADR  => if tms = '1' then tap <= EX2DR; end if;
        when EX2DR => if tms = '1' then tap <= UPDR; else tap <= SHDR; end if;
        when UPDR  => if tms = '1' then tap <= SELDR; else tap <= RTI; end if;
        when SELIR => if tms = '1' then tap <= TLR; else tap <= CAPIR; end if;
        when CAPIR => if tms = '1' then tap <= EX1IR; else tap <= SHIR; end if;
        when SHIR  => if tms = '1' then tap <= EX1IR; end if;
        when EX1IR => if tms = '1' then tap <= UPIR; else tap <= PAIR; end if;
        when PAIR  => if tms = '1' then tap <= EX2IR; end if;
        when EX2IR => if tms = '1' then tap <= UPIR; else tap <= SHIR; end if;
        when UPIR  => if tms = '1' then tap <= SELDR; else tap <= RTI; end if;
      end case;
    end if;
    if falling_edge(tck) then
      if tap = SHDR then tdo <= dr(0); else tdo <= '0'; end if;
    end if;
  end process;
end architecture;
