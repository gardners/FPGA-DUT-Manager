-- kbd_mk1_device: emulate a MEGA65 MK-I keyboard towards a MEGA65 mainboard.
--
-- The serial behaviour is ported from the keyboard-facing half of
-- mega65-core src/vhdl/mk2_to_mk1.vhdl (LGPL-3.0-or-later, MEGA65 project),
-- which is proven against real mainboards running mega65kbd_to_matrix.
-- Changes: clock-rate independent sync threshold, active-high "pressed"
-- input bitmap, explicit output enable, our own keyboard id.
--
-- Protocol summary (host = MEGA65 mainboard):
--   KIO8  (in)  clock from host; held high for a long "sync" period after
--               each 128-bit frame
--   KIO9  (in)  LED data from host, sampled on KIO8 rising edges
--   KIO10 (out) key data to host, changes after KIO8 rising edges; driven
--               high during sync (which is also how hosts detect an MK-I)
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_mk1_device is
  generic (
    -- KIO8 high for this many clk cycles = sync. mk2_to_mk1 uses 248 cycles
    -- at 40.5 MHz (6.1 us); host sync lasts ~40 us, a clock half ~1.6 us.
    SYNC_CYCLES : positive := 765;          -- 6.1 us at 125 MHz
    ID_DATE     : std_logic_vector(13 downto 0) := (others => '0');
    ID_COMMIT   : std_logic_vector(31 downto 0) := x"53555056"  -- "SUPV"
  );
  port (
    clk          : in  std_logic;
    -- 80-bit key bitmap, bit k = MEGA65 matrix key k, '1' = pressed
    keys_pressed : in  std_logic_vector(79 downto 0);
    -- pins (already synchronised by the caller is NOT required; we sync here)
    kio8_in      : in  std_logic;
    kio9_in      : in  std_logic;
    kio10_out    : out std_logic;
    -- 96-bit LED vector received from the host, updated once per frame
    leds         : out std_logic_vector(95 downto 0);
    leds_strobe  : out std_logic;
    -- status
    frame_count  : out unsigned(15 downto 0)
  );
end entity;

architecture rtl of kbd_mk1_device is
  signal kio8_s, kio9_s       : std_logic_vector(1 downto 0) := (others => '0');
  signal kio8_hist            : std_logic_vector(3 downto 0) := (others => '0');
  signal last_kio8            : std_logic := '0';
  signal last_last_kio8       : std_logic := '0';
  signal high_count           : integer range 0 to SYNC_CYCLES := 0;
  signal serial_out           : std_logic_vector(127 downto 0) := (others => '1');
  signal serial_in            : std_logic_vector(127 downto 0) := (others => '0');
  signal bit_number           : integer range 0 to 255 := 0;
  signal kio10_r              : std_logic := '1';
  signal leds_r               : std_logic_vector(95 downto 0) := (others => '0');
  signal frames               : unsigned(15 downto 0) := (others => '0');
begin

  kio10_out   <= kio10_r;
  leds        <= leds_r;
  frame_count <= frames;

  process (clk)
    variable keys_n : std_logic_vector(79 downto 0);
  begin
    if rising_edge(clk) then
      leds_strobe <= '0';

      -- 2-FF synchronisers
      kio8_s <= kio8_s(0) & kio8_in;
      kio9_s <= kio9_s(0) & kio9_in;

      -- glitch filter for the clock as in mk2_to_mk1
      kio8_hist      <= kio8_hist(2 downto 0) & kio8_s(1);
      last_last_kio8 <= last_kio8;
      if kio8_hist = "1111" and kio8_s(1) = '1' and last_kio8 = '0' then
        last_kio8 <= '1';
      end if;
      if kio8_hist = "0000" and kio8_s(1) = '0' and last_kio8 = '1' then
        last_kio8 <= '0';
      end if;

      -- sync detector (saturating high-time counter)
      if kio8_s(1) = '0' then
        high_count <= 0;
      elsif high_count < SYNC_CYCLES then
        high_count <= high_count + 1;
      end if;

      keys_n := not keys_pressed;       -- protocol is active low

      if high_count = SYNC_CYCLES then
        -- Load the response frame (layout identical to mk2_to_mk1):
        --   127..48 : keys 0..79 (bit 48+i = key 79-i)
        --    47..46 : '1'
        --    45..32 : date stamp, bit 32+i = date(13-i)
        --    31..0  : commit id, byte-reversed bit order as upstream
        serial_out(47 downto 46) <= "11";
        for i in 0 to 13 loop
          serial_out(32 + i) <= ID_DATE(13 - i);
        end loop;
        for i in 0 to 31 loop
          serial_out(i) <= ID_COMMIT(24 - ((i / 8) * 8) + 7 - (i mod 8));
        end loop;
        for i in 0 to 79 loop
          serial_out(48 + i) <= keys_n(79 - i);
        end loop;
        -- DEL and RETURN are duplicated at 76/77 by the keyboard firmware
        -- (the host reads them there because of its 2-bit lag).
        serial_out(48 + (79 - 76)) <= keys_n(0);
        serial_out(48 + (79 - 77)) <= keys_n(1);
        bit_number <= 0;
        kio10_r    <= '1';
      elsif last_last_kio8 = '0' and last_kio8 = '1' then
        if bit_number /= 255 then
          bit_number <= bit_number + 1;
        end if;
        serial_in <= serial_in(126 downto 0) & kio9_s(1);
        if bit_number = 127 then
          for i in 0 to 94 loop
            leds_r(i) <= serial_in(94 - i);
          end loop;
          leds_r(95)  <= kio9_s(1);
          leds_strobe <= '1';
          frames      <= frames + 1;
        end if;
        serial_out <= serial_out(126 downto 0) & serial_out(127);
        kio10_r    <= serial_out(125);
      end if;
    end if;
  end process;

end architecture;
