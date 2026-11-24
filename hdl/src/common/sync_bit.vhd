-- Two-flop synchroniser for single-bit level signals.
library ieee;
use ieee.std_logic_1164.all;

entity sync_bit is
  generic (INIT : std_logic := '0');
  port (
    clk : in  std_logic;
    d   : in  std_logic;
    q   : out std_logic
  );
end entity;

architecture rtl of sync_bit is
  signal s : std_logic_vector(1 downto 0) := (others => INIT);
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of s : signal is "TRUE";
begin
  process (clk)
  begin
    if rising_edge(clk) then
      s <= s(0) & d;
    end if;
  end process;
  q <= s(1);
end architecture;
