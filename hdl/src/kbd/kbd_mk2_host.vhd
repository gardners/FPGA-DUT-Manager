-- kbd_mk2_host: read a MEGA65 MK-II keyboard (six TCA9555 I2C IO expanders,
-- one GPIO per key) and drive its LEDs, producing the same 80-bit "pressed"
-- bitmap (1 = pressed, index = MEGA65 matrix key) as kbd_mk1_host.
--
-- Behaviour ported from mega65-core src/vhdl/mk2_to_mk1.vhdl (LGPL, MEGA65
-- project), rewritten as a byte-level I2C master instead of upstream's
-- ~500-state bit-bang table (issue 0009 has the protocol analysis):
--   * SDA = KIO8, SCL = KIO9, both open drain here (upstream drives SCL
--     push-pull). The MK-II PCB has 1k pull-ups on both (R13/R14).
--   * Each scan: write U1 (0x20) = LEDs, then read U3, U5, U2, U4, U6
--     (0x21..0x25) input ports 0/1, then publish the bitmap.
--   * LED write: START 0x40 reg d0 d1 STOP. reg = 0x06 (configuration,
--     data 0x00 0x00 = all outputs) on the first scan and every
--     2**REINIT_LOG2 scans (hot-plug), else 0x02 (output ports).
--     d0 = {shiftlock, b1, r1, g1, capslock, b0, r0, g0},
--     d1 = {0, b3, r3, g3, 0, b2, r2, g2}; all active low.
--   * Read: START addr+W 0x00 rSTART addr+R port0(ACK) port1(NACK) STOP.
-- Differences from upstream: proper STOP after the LED write, SDA raised
-- while SCL is low before a repeated START (upstream raised both in one
-- tick), the master releases SDA in slave ACK slots, and led2_r uses the
-- nibble ov(31:28) like the other LEDs (upstream compared 8 bits).
--
-- Every bus action happens on a quarter-bit tick (QUARTER_CYCLES clocks), so
-- SCL = clk / (4 * QUARTER_CYCLES): 250 kHz at 125 MHz with the default
-- (QUARTER_CYCLES >= 4). A scan is ~280 SCL periods (~1.1 ms at 250 kHz).
--
-- hold (key 0x0063, issue 0054): no new transaction is started; held = the
-- bus is idle between transactions (after a STOP, both lines released), or
-- the block is disabled. I2C is static, so the scan resumes where it stopped.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_mk2_host is
  generic (
    QUARTER_CYCLES : positive := 125;     -- clocks per quarter SCL period
    REINIT_LOG2    : positive := 10;      -- re-send U1 config every 2**n scans
    CAPS_HOLD      : positive := 510      -- scans CAPS held before it re-toggles
  );
  port (
    clk        : in  std_logic;
    enable     : in  std_logic;           -- '0': idle, both lines released
    -- I2C, open drain: '1' = pull the line low, '0' = release
    sda_in     : in  std_logic;           -- KIO8 pin (asynchronous)
    sda_low    : out std_logic;
    scl_low    : out std_logic;
    -- LED vector in the host's order (same as kbd_mk1_host)
    leds       : in  std_logic_vector(95 downto 0);
    -- results
    pressed    : out std_logic_vector(79 downto 0);
    strobe     : out std_logic;           -- once per complete scan
    present    : out std_logic;           -- an expander ACKed in the last scan
    kbd_commit : out std_logic_vector(31 downto 0);
    hold       : in  std_logic := '0';
    held       : out std_logic
  );
end entity;

architecture rtl of kbd_mk2_host is
  -- port bit -> matrix key per expander (a = 1..5), -1 = not a matrix key.
  -- Specials handled separately: U3 bit 7 = SHIFT LOCK, U5 bits 4/5 = GPIO,
  -- U6 bit 14 = CAPS LOCK (raw key -> 78). DEL (0) and RETURN (1) are
  -- duplicated to 76/77 at publish time.
  type map_t is array (1 to 5, 0 to 15) of integer range -1 to 79;
  constant KEYMAP : map_t := (
    -- U3 (0x21)
    1 => (-1, 9, 62, 65, 18, 13, 10, -1, 20, 23, 12, 15, 61, 58, 14, 57),
    -- U5 (0x22)
    2 => (2, 7, 73, 74, -1, -1, 55, 52, 75, 54, 49, 46, 1, 53, 50, 45),
    -- U2 (0x23)
    3 => (67, 70, 69, 68, 0, 51, 48, 43, 41, 38, 33, 30, 40, 35, 6, 3),
    -- U4 (0x24)
    4 => (42, 36, 37, 39, 28, 31, 47, 44, 60, 21, 17, 26, 22, 29, 25, 34),
    -- U6 (0x25)
    5 => (4, 5, 32, 27, 24, 19, 16, 11, 8, 59, 56, 63, 71, 66, 78, 64));

  type st_t is (S_NEXT, S_START, S_BYTE, S_STOP);
  signal st       : st_t := S_NEXT;
  signal div      : integer range 0 to QUARTER_CYCLES - 1 := 0;
  signal qtick    : std_logic := '0';
  signal q        : unsigned(1 downto 0) := "00";        -- quarter in bit
  signal bitn     : integer range 0 to 8 := 0;
  signal tx       : std_logic_vector(8 downto 0) := (others => '1');
  signal rx       : std_logic_vector(8 downto 0) := (others => '1');
  signal step     : integer range 0 to 7 := 0;           -- op within transaction
  signal xact     : integer range 0 to 5 := 0;           -- 0 LED write, 1..5 reads
  signal busy     : std_logic := '0';                    -- op issued, not done
  signal sda_s    : std_logic_vector(1 downto 0) := "11";
  signal sda_r, scl_r : std_logic := '0';
  signal port0    : std_logic_vector(7 downto 0) := (others => '1');
  signal portv    : std_logic_vector(15 downto 0) := (others => '1');
  signal map_stb  : std_logic := '0';
  signal map_a    : integer range 1 to 5 := 1;
  signal pub_stb  : std_logic := '0';
  signal raw      : std_logic_vector(79 downto 0) := (others => '1');  -- '0' = down
  signal acked    : std_logic := '0';
  signal present_r: std_logic := '0';
  -- locks and LEDs
  signal sl_prev  : std_logic := '1';
  signal sl_n     : std_logic := '1';                    -- '0' = shift locked
  signal caps_hist: std_logic_vector(7 downto 0) := (others => '1');
  signal caps_held: integer range 0 to CAPS_HOLD + 1 := 0;
  signal caps     : std_logic := '0';                    -- '1' = caps locked
  signal pwm_cnt  : unsigned(3 downto 0) := (others => '0');
  signal led_d0   : std_logic_vector(7 downto 0) := (others => '1');
  signal led_d1   : std_logic_vector(7 downto 0) := x"77";
  signal reinit   : std_logic := '1';
  signal scan_cnt : unsigned(REINIT_LOG2 - 1 downto 0) := (others => '0');

  -- '0' = LED on when the PWM nibble ov(hi downto hi-3) exceeds the counter;
  -- ov(i) = leds(95 - i) (the MK-I serial order, as in mk2_to_mk1)
  function led_off(l : std_logic_vector(95 downto 0); hi : natural; c : unsigned(3 downto 0))
    return std_logic is
    variable n : unsigned(3 downto 0);
  begin
    for j in 0 to 3 loop
      n(j) := l(95 - (hi - 3 + j));
    end loop;
    if n > c then return '0'; else return '1'; end if;
  end function;
begin
  sda_low    <= sda_r;
  scl_low    <= scl_r;
  present    <= present_r;
  held       <= hold when enable = '0' or (st = S_NEXT and busy = '0' and step = 0 and
                                            pub_stb = '0' and map_stb = '0') else '0';
  kbd_commit <= x"4D4B4949";              -- "MKII", as mk2_to_mk1 reports

  process (clk)
    variable bits : std_logic_vector(15 downto 0);
    variable k    : integer;
  begin
    if rising_edge(clk) then
      strobe  <= '0';
      map_stb <= '0';
      pub_stb <= '0';
      sda_s   <= sda_s(0) & sda_in;

      if div /= QUARTER_CYCLES - 1 then
        div <= div + 1; qtick <= '0';
      else
        div <= 0; qtick <= '1';
      end if;

      ------------------------------------------------------------ bus engine
      if enable = '0' then
        st <= S_NEXT; busy <= '0'; step <= 0; xact <= 0;
        sda_r <= '0'; scl_r <= '0'; q <= "00";
        present_r <= '0'; reinit <= '1'; acked <= '0';
      else
        case st is
          when S_NEXT =>
            -- sequencer: issue the next op of the current transaction
            if busy = '1' then
              busy <= '0';
              -- op finished: collect results
              if step = 1 or (xact /= 0 and step = 4) then
                if rx(0) = '0' then acked <= '1'; end if;
              end if;
              if xact /= 0 and step = 5 then
                port0 <= rx(8 downto 1);
              end if;
              if xact /= 0 and step = 6 then
                portv <= rx(8 downto 1) & port0;
              end if;
              if (xact = 0 and step = 5) or step = 7 then
                -- STOP done: transaction complete
                step <= 0;
                if xact /= 0 then
                  map_stb <= '1'; map_a <= xact;
                end if;
                if xact = 5 then
                  xact <= 0;               -- publish follows the U6 mapping
                else
                  xact <= xact + 1;
                end if;
              else
                step <= step + 1;
              end if;
            elsif pub_stb = '0' and map_stb = '0' and not (hold = '1' and step = 0) then
              busy <= '1'; q <= "00"; bitn <= 0;
              if step = 0 or (xact /= 0 and step = 3) then
                st <= S_START;
              elsif (xact = 0 and step = 5) or step = 7 then
                st <= S_STOP;
              else
                st <= S_BYTE;
                if xact = 0 then
                  case step is
                    when 1 => tx <= x"40" & '1';
                    when 2 =>
                      if reinit = '1' then tx <= x"06" & '1'; else tx <= x"02" & '1'; end if;
                    when 3 =>
                      if reinit = '1' then tx <= x"00" & '1'; else tx <= led_d0 & '1'; end if;
                    when others =>
                      if reinit = '1' then tx <= x"00" & '1'; else tx <= led_d1 & '1'; end if;
                  end case;
                else
                  case step is
                    when 1 => tx <= "0100" & std_logic_vector(to_unsigned(xact, 3)) & '0' & '1';
                    when 2 => tx <= x"00" & '1';
                    when 4 => tx <= "0100" & std_logic_vector(to_unsigned(xact, 3)) & '1' & '1';
                    when 5 => tx <= x"FF" & '0';   -- read port 0, ACK
                    when others => tx <= x"FF" & '1';  -- read port 1, NACK
                  end case;
                end if;
              end if;
            end if;

          when S_START =>     -- SDA up (SCL low or high), SCL up, SDA down, SCL down
            if qtick = '1' then
              q <= q + 1;
              case q is
                when "00" => sda_r <= '0';
                when "01" => scl_r <= '0';
                when "10" => sda_r <= '1';
                when others => scl_r <= '1'; st <= S_NEXT;
              end case;
            end if;

          when S_BYTE =>      -- 9 bits: data MSB first, then the ACK slot
            if qtick = '1' then
              q <= q + 1;
              case q is
                when "00" => sda_r <= not tx(8);
                when "01" => scl_r <= '0';
                when "10" => rx <= rx(7 downto 0) & sda_s(1);
                when others =>
                  scl_r <= '1';
                  tx <= tx(7 downto 0) & '1';
                  if bitn = 8 then
                    st <= S_NEXT;
                  else
                    bitn <= bitn + 1;
                  end if;
              end case;
            end if;

          when S_STOP =>      -- SDA down (SCL low), SCL up, SDA up
            if qtick = '1' then
              q <= q + 1;
              case q is
                when "00" => sda_r <= '1';
                when "01" => scl_r <= '0';
                when "10" => sda_r <= '0';
                when others => st <= S_NEXT;
              end case;
            end if;
        end case;

        if pub_stb = '1' then
          present_r <= acked;
          acked     <= '0';
          scan_cnt  <= scan_cnt + 1;
          reinit    <= '0';
          if scan_cnt = (scan_cnt'range => '1') then reinit <= '1'; end if;
        end if;
      end if;

      ------------------------------------------------------------ key mapping
      if map_stb = '1' then
        if map_a = 5 then
          pub_stb <= '1';
        end if;
        bits := portv;
        for a in 1 to 5 loop
          if map_a = a then
            for b in 0 to 15 loop
              k := KEYMAP(a, b);
              if k >= 0 then
                raw(k) <= bits(b);
              end if;
            end loop;
          end if;
        end loop;
        if map_a = 1 then
          -- SHIFT LOCK toggles on each press
          sl_prev <= bits(7);
          if bits(7) = '0' and sl_prev = '1' then
            sl_n <= not sl_n;
          end if;
        end if;
        if map_a = 5 then
          -- CAPS LOCK: toggle on a press after 8 released scans, and again
          -- once it has been held for CAPS_HOLD scans (turbo use)
          caps_hist <= caps_hist(6 downto 0) & bits(14);
          if caps_hist = x"00" then
            if caps_held <= CAPS_HOLD then
              caps_held <= caps_held + 1;
            end if;
            if caps_held = CAPS_HOLD then
              caps <= not caps;
            end if;
          else
            caps_held <= 0;
          end if;
          if bits(14) = '0' and caps_hist = x"FF" then
            caps <= not caps;
          end if;
        end if;
      end if;

      ------------------------------------------------------------ publish
      if pub_stb = '1' then
        for i in 0 to 79 loop
          pressed(i) <= not raw(i);
        end loop;
        pressed(15) <= not (raw(15) and sl_n);
        pressed(72) <= caps;
        pressed(76) <= not raw(0);
        pressed(77) <= not raw(1);
        strobe <= '1';
        -- next LED frame (PWM step per scan)
        pwm_cnt <= pwm_cnt + 1;
        led_d0 <= sl_n & led_off(leds, 55, pwm_cnt) & led_off(leds, 63, pwm_cnt) &
                  led_off(leds, 71, pwm_cnt) & (not caps) & led_off(leds, 79, pwm_cnt) &
                  led_off(leds, 87, pwm_cnt) & led_off(leds, 95, pwm_cnt);
        led_d1 <= '0' & led_off(leds, 15, pwm_cnt) & led_off(leds, 7, pwm_cnt) &
                  led_off(leds, 23, pwm_cnt) & '0' & led_off(leds, 39, pwm_cnt) &
                  led_off(leds, 31, pwm_cnt) & led_off(leds, 47, pwm_cnt);
      end if;
    end if;
  end process;
end architecture;
