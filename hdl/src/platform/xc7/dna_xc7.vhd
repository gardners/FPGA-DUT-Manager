-- dna_xc7: read the 57-bit Artix-7 device DNA once after configuration
-- (issue 0007). DNA_PORT is clocked at clk/16 from a register (CLK must stay
-- <= 100 MHz); READ loads the shift register, then 57 SHIFT cycles deliver
-- bit 56 first on DOUT (bit 56 is already on DOUT right after READ).
-- dna is zero until valid = '1'.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.xc7_prims_pkg.all;

entity dna_xc7 is
  generic (SIM_DNA : bit_vector(56 downto 0) := (others => '0'));  -- simulation only
  port (
    clk   : in  std_logic;
    dna   : out std_logic_vector(63 downto 0);
    valid : out std_logic
  );
end entity;

architecture rtl of dna_xc7 is
  signal div   : unsigned(3 downto 0) := (others => '0');
  signal dclk  : std_logic := '0';
  signal rd, sh : std_logic := '0';
  signal dout  : std_logic;
  signal n     : integer range 0 to 63 := 0;
  signal phase : integer range 0 to 3 := 0;   -- 0 wait, 1 read, 2 shift, 3 done
  signal sreg  : std_logic_vector(56 downto 0) := (others => '0');
  signal v     : std_logic := '0';
begin
  dp : DNA_PORT generic map (SIM_DNA_VALUE => SIM_DNA)
    port map (DOUT => dout, CLK => dclk, DIN => '0', READ => rd, SHIFT => sh);
  dna   <= "0000000" & sreg when v = '1' else (others => '0');
  valid <= v;

  process (clk)
  begin
    if rising_edge(clk) then
      div <= div + 1;
      -- control changes and DOUT sampling half a DNA clock away from its
      -- rising edge (dclk rises at div = 8, falls at div = 0)
      if div = 7 then dclk <= '1'; end if;
      if div = 15 then dclk <= '0'; end if;
      if div = 3 then
        case phase is
          when 0 => rd <= '1'; phase <= 1;
          when 1 =>                     -- DOUT holds bit 56 after READ
            rd <= '0'; sh <= '1';
            sreg <= sreg(55 downto 0) & dout; n <= 1; phase <= 2;
          when 2 =>
            sreg <= sreg(55 downto 0) & dout;
            if n = 56 then sh <= '0'; phase <= 3; v <= '1'; else n <= n + 1; end if;
          when 3 => null;
        end case;
      end if;
    end if;
  end process;
end architecture;
