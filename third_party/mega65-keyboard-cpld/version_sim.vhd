-- Simulation stand-in for the keyboard CPLD's generated src/version.vhdl
-- (version.sh writes it from `git describe` and the date at build time).
-- Fixed values here so the testbenches can check them: commit 2ed09bd3,
-- date stamp 2527 (the values of the upstream build 2ed09bd).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package version is
  constant git_version : unsigned(31 downto 0) := x"2ed09bd3";
  constant git_date : unsigned(13 downto 0) := to_unsigned(2527, 14);
end version;
