-- Raster capture line descriptor shared by raster_capture (producer) and
-- net_tx (consumer), issue 0023 / ADR 0005 section 8.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package raster_pkg is
  -- one captured (committed) active line in the pixel ring
  type rast_desc_t is record
    start    : unsigned(15 downto 0);   -- first pixel's ring address
    count    : unsigned(10 downto 0);   -- pixels stored (active_count, <= 1024)
    frame    : unsigned(31 downto 0);   -- increments at line 0
    line     : unsigned(15 downto 0);   -- 0 = first active line
    flags    : std_logic_vector(7 downto 0);  -- ADR 0005 s8 flags, b5 = drops /= 0
    drops    : unsigned(7 downto 0);    -- lines dropped before this one (saturating)
    hs_start : unsigned(15 downto 0);   -- HSYNC active from (first active pixel = 0)
    hs_end   : unsigned(15 downto 0);   -- HSYNC inactive from (half-open)
  end record;
  constant RAST_DESC_W : natural := 16 + 11 + 32 + 16 + 8 + 8 + 16 + 16;
  constant RAST_DESC_NONE : rast_desc_t := ((others => '0'), (others => '0'), (others => '0'),
    (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'));

  -- raster flags (ADR 0005 s8)
  constant RF_VSYNC   : natural := 0;
  constant RF_VPOL    : natural := 1;
  constant RF_HPOL    : natural := 2;
  constant RF_ACTIVE  : natural := 3;
  constant RF_FIRST   : natural := 4;
  constant RF_DROPPED : natural := 5;
  constant RF_LOCKED  : natural := 6;

  function to_slv(d : rast_desc_t) return std_logic_vector;
  function to_desc(v : std_logic_vector(RAST_DESC_W - 1 downto 0)) return rast_desc_t;
end package;

package body raster_pkg is
  function to_slv(d : rast_desc_t) return std_logic_vector is
  begin
    return std_logic_vector(d.start) & std_logic_vector(d.count) & std_logic_vector(d.frame) &
           std_logic_vector(d.line) & d.flags & std_logic_vector(d.drops) &
           std_logic_vector(d.hs_start) & std_logic_vector(d.hs_end);
  end function;

  function to_desc(v : std_logic_vector(RAST_DESC_W - 1 downto 0)) return rast_desc_t is
    variable d : rast_desc_t;
  begin
    d.start    := unsigned(v(122 downto 107));
    d.count    := unsigned(v(106 downto 96));
    d.frame    := unsigned(v(95 downto 64));
    d.line     := unsigned(v(63 downto 48));
    d.flags    := v(47 downto 40);
    d.drops    := unsigned(v(39 downto 32));
    d.hs_start := unsigned(v(31 downto 16));
    d.hs_end   := unsigned(v(15 downto 0));
    return d;
  end function;
end package body;
