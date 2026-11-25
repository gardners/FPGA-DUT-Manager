-- Behavioural DNA_PORT (Xilinx 7-series) for simulation: READ on a CLK edge
-- loads SIM_DNA_VALUE (bit 56 appears on DOUT), SHIFT shifts towards DOUT.
library ieee;
use ieee.std_logic_1164.all;

entity DNA_PORT is
  generic (SIM_DNA_VALUE : bit_vector(56 downto 0) := (others => '0'));
  port (DOUT : out std_logic; CLK, DIN, READ, SHIFT : in std_logic);
end entity;

architecture sim of DNA_PORT is
  signal r : std_logic_vector(56 downto 0) := (others => '0');
begin
  DOUT <= r(56);
  process (CLK)
  begin
    if rising_edge(CLK) then
      if READ = '1' then
        r <= to_stdlogicvector(SIM_DNA_VALUE);
      elsif SHIFT = '1' then
        r <= r(55 downto 0) & DIN;
      end if;
    end if;
  end process;
end architecture;
