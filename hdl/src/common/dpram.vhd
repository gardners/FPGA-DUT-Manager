-- Simple dual-port RAM: one write port (clock A), one registered read port
-- (clock B). Infers block RAM in Vivado and yosys. Read latency 1 cycle.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
  generic (
    ADDR_W : positive := 11;
    DATA_W : positive := 8
  );
  port (
    clk_a  : in  std_logic;
    we_a   : in  std_logic;
    addr_a : in  unsigned(ADDR_W - 1 downto 0);
    din_a  : in  std_logic_vector(DATA_W - 1 downto 0);
    clk_b  : in  std_logic;
    addr_b : in  unsigned(ADDR_W - 1 downto 0);
    dout_b : out std_logic_vector(DATA_W - 1 downto 0)
  );
end entity;

architecture rtl of dpram is
  type mem_t is array (0 to 2 ** ADDR_W - 1) of std_logic_vector(DATA_W - 1 downto 0);
  signal mem : mem_t := (others => (others => '0'));
begin
  process (clk_a)
  begin
    if rising_edge(clk_a) then
      if we_a = '1' then
        mem(to_integer(addr_a)) <= din_a;
      end if;
    end if;
  end process;

  process (clk_b)
  begin
    if rising_edge(clk_b) then
      dout_b <= mem(to_integer(addr_b));
    end if;
  end process;
end architecture;
