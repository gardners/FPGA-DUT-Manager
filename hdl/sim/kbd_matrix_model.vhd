-- kbd_matrix_model: the MEGA65 MK-I keyboard's passive key matrix as the
-- keyboard CPLD sees it (simulation only, issue 0046). The CPLD drives one
-- of SCAN_OUT(9..0) low at a time and reads SCAN_IN(7..0) (pulled up, '0'
-- = a closed key on the active row). keys(8 * row + col) = '1' closes the
-- switch between SCAN_OUT(row) and SCAN_IN(col).
library ieee;
use ieee.std_logic_1164.all;

entity kbd_matrix_model is
  port (
    scan_out : in  std_logic_vector(9 downto 0);
    keys     : in  std_logic_vector(79 downto 0);
    scan_in  : out std_logic_vector(7 downto 0)
  );
end entity;

architecture sim of kbd_matrix_model is
begin
  process (scan_out, keys)
    variable v : std_logic;
  begin
    for c in 0 to 7 loop
      v := '1';
      for r in 0 to 9 loop
        if scan_out(r) = '0' and keys(8 * r + c) = '1' then
          v := '0';
        end if;
      end loop;
      scan_in(c) <= v;
    end loop;
  end process;
end architecture;
