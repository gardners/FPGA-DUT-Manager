-- Simulation model of the Lattice MachXO2 internal oscillator OSCH, analysed
-- into library `machxo2` (the keyboard CPLD source says `library machxo2;
-- use machxo2.all;` and declares the OSCH component itself), for the
-- keyboard-CPLD testbenches (issue 0046). Simulation only.
--
-- NOM_FREQ is the MHz string of the real primitive ("12.09", "24.18", ...).
-- The clock starts with a rising edge at time 0, and the half period is
-- 1 / (2 * NOM_FREQ) rounded to 1 ps, so 24.18 is exactly twice 12.09
-- (20678 ps vs 41356 ps) and the edges of the two line up: the MK-I
-- compatibility testbench relies on it. osch_trim_ppm (package below)
-- stretches the period at run time to model the +/-5.5 % tolerance
-- (positive = slower clock).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
package osch_sim_pkg is
  signal osch_trim_ppm : integer := 0;
  -- testbenches set this at the end: the oscillator stops, so the
  -- simulation runs out of events
  signal osch_stop : boolean := false;
end package;

library ieee;
use ieee.std_logic_1164.all;
use work.osch_sim_pkg.all;

entity OSCH is
  generic (NOM_FREQ : string := "2.08");
  port (
    STDBY    : in  std_logic;
    OSC      : out std_logic := '0';
    SEDSTDBY : out std_logic
  );
end entity;

architecture sim of OSCH is
  -- "12.09" -> 1209 (hundredths of a MHz)
  function centi_mhz(s : string) return natural is
    variable v : natural := 0;
    variable frac : integer := -1;
  begin
    for i in s'range loop
      if s(i) = '.' then
        frac := 0;
      elsif s(i) >= '0' and s(i) <= '9' then
        v := v * 10 + character'pos(s(i)) - character'pos('0');
        if frac >= 0 then
          frac := frac + 1;
        end if;
      end if;
    end loop;
    if frac < 0 then
      frac := 0;
    end if;
    for i in frac to 1 loop
      v := v * 10;
    end loop;
    return v;
  end function;
  -- half period in ps: 1e12 / (2 * f) = 5e9 / centi_mhz ... in ps:
  -- f = c * 1e4 Hz -> half = 1e12 / (2 * c * 1e4) ps = 5e7 / c ps
  constant HALF_PS : natural := (50_000_000 + centi_mhz(NOM_FREQ) / 2) / centi_mhz(NOM_FREQ);
begin
  SEDSTDBY <= '0';
  process
    variable h : time;
  begin
    OSC <= '1';
    while not osch_stop loop
      h := HALF_PS * 1 ps;
      h := h + (h * osch_trim_ppm) / 1_000_000;
      if STDBY = '1' then
        OSC <= '0';
        wait until STDBY = '0';
      end if;
      wait for h;
      OSC <= '0';
      wait for h;
      OSC <= '1';
    end loop;
    wait;
  end process;
end architecture;
