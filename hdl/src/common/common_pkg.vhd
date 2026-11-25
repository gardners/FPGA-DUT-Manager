-- Shared helpers: CRC-32 (Ethernet), bit/byte utilities.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package common_pkg is
  subtype byte_t is std_logic_vector(7 downto 0);
  type byte_array_t is array (natural range <>) of byte_t;

  -- Ethernet CRC-32 (reflected, poly 0xEDB88320), one byte, LSB first.
  -- State starts at x"FFFFFFFF"; FCS on the wire = not state, LSB first.
  function crc32_byte(crc : std_logic_vector(31 downto 0); d : byte_t)
    return std_logic_vector;
  -- Residue left in the state after running CRC over data+FCS of a good frame.
  constant CRC32_RESIDUE : std_logic_vector(31 downto 0) := x"DEBB20E3";
  -- product identity shown on the console (owner 2026-11-25)
  constant PRODUCT_NAME    : string := "MEGA KVM";
  constant PRODUCT_VERSION : string := "0.1";
  -- lower-case hex of a 32-bit value (e.g. the build id)
  function hex32(v : std_logic_vector(31 downto 0)) return string;

  function clog2(n : positive) return natural;
  function to_slv(n : natural; w : positive) return std_logic_vector;
  function reverse(v : std_logic_vector) return std_logic_vector;
  -- one's complement 16-bit add with end-around carry
  function ones_add(a, b : unsigned(15 downto 0)) return unsigned;
end package;

package body common_pkg is
  function hex32(v : std_logic_vector(31 downto 0)) return string is
    constant HX : string(1 to 16) := "0123456789abcdef";
    variable r  : string(1 to 8);
  begin
    for k in 0 to 7 loop
      r(k + 1) := HX(to_integer(unsigned(v(31 - 4 * k downto 28 - 4 * k))) + 1);
    end loop;
    return r;
  end function;

  function crc32_byte(crc : std_logic_vector(31 downto 0); d : byte_t)
    return std_logic_vector is
    variable c : std_logic_vector(31 downto 0) := crc;
  begin
    for i in 0 to 7 loop
      if (c(0) xor d(i)) = '1' then
        c := ('0' & c(31 downto 1)) xor x"EDB88320";
      else
        c := '0' & c(31 downto 1);
      end if;
    end loop;
    return c;
  end function;

  function clog2(n : positive) return natural is
    variable r : natural := 0;
    variable v : natural := 1;
  begin
    while v < n loop
      v := v * 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  function to_slv(n : natural; w : positive) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(n, w));
  end function;

  function reverse(v : std_logic_vector) return std_logic_vector is
    variable r : std_logic_vector(v'reverse_range);
  begin
    for i in v'range loop
      r(i) := v(i);
    end loop;
    return r;
  end function;

  function ones_add(a, b : unsigned(15 downto 0)) return unsigned is
    variable s : unsigned(16 downto 0);
  begin
    s := ('0' & a) + ('0' & b);
    return s(15 downto 0) + s(16 downto 16);
  end function;
end package body;
