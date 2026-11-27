-- kbd_mk1_host: read a MEGA65 MK-I keyboard (the master's own physical
-- keyboard), producing an 80-bit "pressed" bitmap, and drive its LEDs.
--
-- Protocol and timing ported from mega65-core src/vhdl/mega65kbd_to_matrix.vhdl
-- (LGPL, MEGA65 project): KIO8 is a clock with a long high sync after 128
-- bits; LED data goes out on KIO9 (MSB first, changing while the clock is
-- low); key data is sampled from KIO10 when the clock is high. The keyboard
-- answers two bits late, which is why keys 0 (DEL) and 1 (RETURN) are taken
-- from positions 76 and 77 (the keyboard duplicates them there).
-- HALF_CYCLES sets the clock half period (65 cycles at 40.5 MHz = 1.6 us
-- upstream; 200 at 125 MHz here).
--
-- hold (key 0x0063, issue 0054): the scan runs on to the sync phase (KIO8
-- high), then stops there with all lines static: the keyboard sees a long
-- sync, which only restarts its frame, so the scan resumes cleanly. held =
-- stopped.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_mk1_host is
  generic (HALF_CYCLES : positive := 200);
  port (
    clk        : in  std_logic;
    -- keyboard pins
    kio8       : out std_logic;           -- clock / sync to keyboard
    kio9       : out std_logic;           -- LED data to keyboard
    kio10      : in  std_logic;           -- key data from keyboard
    -- LED vector in the host's order (bits 95..0 = four RGB LEDs as sent by
    -- mega65kbd_to_matrix: 23..0 LED0, 47..24 LED1, ...)
    leds       : in  std_logic_vector(95 downto 0);
    -- results
    pressed    : out std_logic_vector(79 downto 0);
    strobe     : out std_logic;           -- once per complete scan
    present    : out std_logic;           -- KIO10 seen high (MK-I detected)
    kbd_commit : out std_logic_vector(31 downto 0);
    hold       : in  std_logic := '0';
    held       : out std_logic
  );
end entity;

architecture rtl of kbd_mk1_host is
  signal div      : integer range 0 to HALF_CYCLES - 1 := 0;
  signal kclk     : std_logic := '0';
  signal phase    : integer range 0 to 140 := 0;
  signal sync     : std_logic := '0';
  signal outv     : std_logic_vector(127 downto 0) := (others => '0');
  signal sampled  : std_logic_vector(127 downto 0) := (others => '1');
  signal k10_s    : std_logic_vector(1 downto 0) := "00";
  signal seen_hi  : std_logic := '0';
  signal commit_r : std_logic_vector(31 downto 0) := (others => '0');
  signal kio8_r   : std_logic := '0';
  signal frz      : std_logic;
begin
  present    <= seen_hi;
  kio8       <= kio8_r;
  frz        <= hold and sync and kio8_r;
  held       <= frz;
  kbd_commit <= commit_r;

  process (clk)
    variable k10 : std_logic;
  begin
    if rising_edge(clk) then
      strobe <= '0';
      k10_s  <= k10_s(0) & kio10;
      k10    := k10_s(1);
      if k10 = '1' then
        seen_hi <= '1';
      end if;
      if frz = '1' then
        null;                           -- held in the sync phase
      elsif div /= HALF_CYCLES - 1 then
        div <= div + 1;
      else
        div  <= 0;
        kclk <= not kclk;
        kio8_r <= kclk or sync;
        if kclk = '1' and phase < 128 then
          sampled(phase) <= k10;
        end if;
        if kclk = '0' then
          if phase /= 140 then
            phase <= phase + 1;
          else
            phase <= 0;
          end if;
          if phase = 127 then
            sync <= '1';
            outv <= x"00000000" & leds;
            -- publish the completed scan
            for k in 2 to 79 loop
              pressed(k) <= not sampled(k);
            end loop;
            pressed(0) <= not sampled(76);
            pressed(1) <= not sampled(77);
            for i in 0 to 31 loop
              commit_r(i) <= sampled(96 + i);
            end loop;
            strobe <= '1';
          elsif phase = 140 then
            sync <= '0';
          elsif phase < 127 then
            kio9 <= outv(127);
            outv <= outv(126 downto 0) & '0';
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
