-- dut_out_gate: output enables for one DUT's supervisor-driven pins
-- (UART TXD, KIO10, JTAG TCK/TMS/TDI), issue 0056.
--
-- * out-policy (MGMT key 0x0060): 0 auto (power sense), 1 force UART/KIO10
--   on (JTAG still follows the sense), 2 force everything off, JTAG
--   included (the host sets 2 before it cuts the DUT's power).
-- * Power-off hold: when the supervisor's own shield power control (key
--   0x0062) switches this DUT's CTRL bit off (pwr_eff 1 -> 0 while the
--   shield answers), or the bit is already off when the shield first
--   answers and the DUT is not sensed powered, all outputs are forced off
--   from that clock on (before the I2C write drops CTRL). The hold ends
--   when the bit is on again, or the sense goes low and then high again
--   (the DUT powered from somewhere else). Without a shield (shd_present
--   '0') pwr_eff is ignored. The hold overrides out-policy 1.
--
-- tx_low (issue 0067): the DUT is known to be powered off (out-policy 2 or
-- the power-off hold): UART TXD is driven low then instead of tri-stated,
-- so a dead DUT's RX sees a defined low and is never fed from a high line.
-- A merely low sense (policy 0) still tri-states (an unwired VIO row on a
-- powered DUT must not see a permanent UART break).
--
-- jtag_pow feeds jtag_engine's "powered": while it is low the engine
-- refuses requests (status unpowered), aborts a running one and tri-states.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;

entity dut_out_gate is
  port (
    clk         : in  std_logic;
    policy      : in  std_logic_vector(7 downto 0);   -- key 0x0060
    powered     : in  std_logic;                      -- synchronised sense
    shd_present : in  std_logic;                      -- shield answered
    pwr_eff     : in  std_logic;                      -- CTRL bit for this DUT
    out_en      : out std_logic;                      -- UART TXD, KIO10
    jtag_pow    : out std_logic;                      -- jtag_engine powered
    hold        : out std_logic;                      -- power-off hold active
    tx_low      : out std_logic                       -- drive UART TXD low (known off)
  );
end entity;

architecture rtl of dut_out_gate is
  signal hold_r    : std_logic := '0';
  signal pres_prev : std_logic := '0';
  signal pwr_prev  : std_logic := '0';
  signal pow_prev  : std_logic := '0';
  signal off       : std_logic;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      pres_prev <= shd_present;
      pwr_prev  <= pwr_eff;
      pow_prev  <= powered;
      if shd_present = '1' and pwr_eff = '0' and
         ((pres_prev = '1' and pwr_prev = '1') or
          (pres_prev = '0' and powered = '0')) then
        hold_r <= '1';
      elsif pwr_eff = '1' or (pow_prev = '0' and powered = '1') then
        hold_r <= '0';
      end if;
    end if;
  end process;

  off      <= '1' when hold_r = '1' or policy = x"02" else '0';
  out_en   <= '0' when off = '1' else
              '1' when policy = x"01" else
              powered;
  jtag_pow <= powered and not off;
  hold     <= hold_r;
  tx_low   <= off;
end architecture;
