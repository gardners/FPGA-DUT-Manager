-- tb_dna_xc7: dna_xc7 reads all 57 bits in order (behavioural DNA_PORT).
library ieee;
use ieee.std_logic_1164.all;

entity tb_dna_xc7 is
end entity;

architecture tb of tb_dna_xc7 is
  constant V : std_logic_vector(56 downto 0) := '1' & x"23456789ABCDEF";
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal dna : std_logic_vector(63 downto 0);
  signal valid : std_logic;
begin
  clk <= not clk after 4 ns when not done;
  dut : entity work.dna_xc7 generic map (SIM_DNA => to_bitvector(V)) port map (clk, dna, valid);
  process
  begin
    wait until valid = '1' for 100 us;
    assert valid = '1' report "dna never valid" severity failure;
    assert dna = "0000000" & V report "dna mismatch: " & to_hstring(dna) severity failure;
    report "tb_dna_xc7 PASSED";
    done <= true;
    wait;
  end process;
end architecture;
