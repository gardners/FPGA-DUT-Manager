-- rx_frame_observer: per-frame good/bad events for the RX phase hunter
-- (issue 0028), in the RX clock domain.
--
-- A frame is "seen" when RX_CTL (rx_dv) stays high for at least MIN_CYC
-- cycles -- this works even when the sample phase is so wrong that the
-- preamble/SFD is never recognised. Its verdict is good when the MAC reports
-- stat_good within WINDOW cycles after rx_dv falls, otherwise bad. Frames
-- the MAC dropped for lack of a free slot (stat_drop) produce no event.
-- Outputs are toggles (tog_good / tog_bad) for a 2-FF crossing.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rx_frame_observer is
  generic (MIN_CYC : positive := 64; WINDOW : positive := 4);
  port (
    clk       : in  std_logic;
    rx_dv     : in  std_logic;
    stat_good : in  std_logic;
    stat_drop : in  std_logic;
    tog_good  : out std_logic;
    tog_bad   : out std_logic
  );
end entity;

architecture rtl of rx_frame_observer is
  signal dv_d    : std_logic := '0';
  signal len     : integer range 0 to MIN_CYC := 0;
  signal pend    : std_logic := '0';
  signal dropped : std_logic := '0';
  signal wait_n  : integer range 0 to WINDOW := 0;
  signal tg, tb  : std_logic := '0';
begin
  tog_good <= tg;
  tog_bad  <= tb;

  process (clk)
  begin
    if rising_edge(clk) then
      dv_d <= rx_dv;
      if stat_drop = '1' then dropped <= '1'; end if;
      if rx_dv = '1' then
        if len < MIN_CYC then len <= len + 1; end if;
      end if;
      if dv_d = '1' and rx_dv = '0' then          -- end of a frame
        len <= 0;
        if len = MIN_CYC and dropped = '0' and stat_drop = '0' then
          pend <= '1'; wait_n <= 0;
        end if;
        if pend = '0' then dropped <= '0'; end if;
      end if;
      if pend = '1' then
        if stat_good = '1' then
          tg <= not tg; pend <= '0'; dropped <= '0';
        elsif stat_drop = '1' then
          pend <= '0'; dropped <= '0';
        elsif wait_n = WINDOW - 1 then
          tb <= not tb; pend <= '0'; dropped <= '0';
        else
          wait_n <= wait_n + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
