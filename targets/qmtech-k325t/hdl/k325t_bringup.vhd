-- QMTECH XC7K325T core board + QMTECH daughter board (DB_FPGA V04):
-- bring-up design (issue 0057).
--
-- * 3-digit 7-segment display: seconds counter "SS.S" (tenths, 00.0-99.9),
--   multiplexed; SW1 holds the count, SW2 clears it.
-- * Daughter-board LEDs D1-D5: uptime seconds, binary (D5 = bit 0).
-- * Core-board LED2: 1 Hz heartbeat. LED3: toggles per received UART byte.
-- * UART TX on J11 pin 4 (8N1, BAUD): a banner after configuration, then one
--   status line per second; bytes received on J11 pin 10 are echoed.
-- * VGA 640x480@60 (25 MHz pixel clock from 50 MHz, so 59.5 Hz): 8 colour
--   bars, a grey ramp along the bottom (checks the resistor-DAC bit order),
--   and a bouncing square drawn in the inverse colour.
--
-- Active levels (daughter-board schematic): segments and LEDs active low,
-- digit selects active high (NPN high-side drivers), buttons active low.
-- Plain VHDL-2008, no vendor primitives.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k325t_bringup is
  generic (
    CLK_HZ  : positive := 50_000_000;
    BAUD    : positive := 2_000_000;
    TICK_HZ : positive := 10;        -- display counter rate (tenths)
    MUX_HZ  : positive := 3_000      -- digit multiplex step rate
  );
  port (
    clk50     : in  std_logic;
    -- 7-segment display (daughter board U3)
    seg_n     : out std_logic_vector(7 downto 0);  -- 0=a .. 6=g, 7=dp
    dig       : out std_logic_vector(2 downto 0);  -- 0 = DIG_1 (left)
    -- LEDs
    db_led_n  : out std_logic_vector(4 downto 0);  -- 0 = D1 .. 4 = D5
    core_led_n: out std_logic_vector(1 downto 0);  -- 0 = LED2, 1 = LED3
    -- buttons (daughter board SW1, SW2; external 4.7k pull-ups)
    sw1_n     : in  std_logic;
    sw2_n     : in  std_logic;
    -- UART on J11 (to/from the supervisor)
    uart_tx   : out std_logic;
    uart_rx   : in  std_logic;
    -- VGA
    vga_r     : out std_logic_vector(4 downto 0);
    vga_g     : out std_logic_vector(5 downto 0);
    vga_b     : out std_logic_vector(4 downto 0);
    vga_hs    : out std_logic;
    vga_vs    : out std_logic
  );
end entity;

architecture rtl of k325t_bringup is

  type bcd_t is array (0 to 2) of unsigned(3 downto 0);

  -- counters
  signal tick_cnt  : natural range 0 to CLK_HZ / TICK_HZ - 1 := 0;
  signal tick      : std_logic := '0';
  signal tenths    : natural range 0 to TICK_HZ - 1 := 0;
  signal sec_tick  : std_logic := '0';
  signal uptime    : unsigned(15 downto 0) := (others => '0');
  signal bcd       : bcd_t := (others => (others => '0'));
  signal sw1_s, sw2_s : std_logic_vector(1 downto 0) := "11";

  -- display multiplex
  signal mux_cnt   : natural range 0 to CLK_HZ / MUX_HZ - 1 := 0;
  signal mux_sel   : natural range 0 to 2 := 0;

  -- UART
  constant BIT_CLKS : positive := CLK_HZ / BAUD;
  signal tx_shift  : std_logic_vector(9 downto 0) := (others => '1');
  signal tx_bits   : natural range 0 to 10 := 0;
  signal tx_cnt    : natural range 0 to BIT_CLKS - 1 := 0;
  signal rx_s      : std_logic_vector(2 downto 0) := "111";
  signal rx_busy   : std_logic := '0';
  signal rx_cnt    : natural range 0 to BIT_CLKS + BIT_CLKS / 2 := 0;
  signal rx_bits   : natural range 0 to 9 := 0;
  signal rx_sr     : std_logic_vector(7 downto 0) := (others => '0');
  signal echo_full : std_logic := '0';
  signal echo_byte : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_led    : std_logic := '0';

  -- message: banner first, then one status line per second
  constant BANNER : string := CR & LF & "QMTECH XC7K325T bring-up (FPGA-DUT-Manager 0057)" & CR & LF;
  constant LINE_LEN : positive := 22;  -- "K325T 12.3 up 0x0000" CR LF
  signal msg_banner : std_logic := '1';  -- banner pending / in progress
  signal msg_line   : std_logic := '0';  -- status line in progress
  signal line_req   : std_logic := '0';
  signal msg_idx    : natural range 0 to 255 := 0;
  signal snap_bcd   : bcd_t := (others => (others => '0'));
  signal snap_up    : unsigned(15 downto 0) := (others => '0');

  -- VGA
  signal pix_ce    : std_logic := '0';
  signal hcnt      : unsigned(9 downto 0) := (others => '0');
  signal vcnt      : unsigned(9 downto 0) := (others => '0');
  signal box_x     : unsigned(9 downto 0) := to_unsigned(100, 10);
  signal box_y     : unsigned(9 downto 0) := to_unsigned(60, 10);
  signal box_dx    : std_logic := '0';  -- 0 = right/down, 1 = left/up
  signal box_dy    : std_logic := '0';

  function seg7(d : unsigned(3 downto 0)) return std_logic_vector is
    -- bit 0 = a ... bit 6 = g, '1' = lit
  begin
    case to_integer(d) is
      when 0 => return "0111111";
      when 1 => return "0000110";
      when 2 => return "1011011";
      when 3 => return "1001111";
      when 4 => return "1100110";
      when 5 => return "1101101";
      when 6 => return "1111101";
      when 7 => return "0000111";
      when 8 => return "1111111";
      when 9 => return "1101111";
      when others => return "1000000";  -- '-'
    end case;
  end function;

  function hexchar(n : unsigned(3 downto 0)) return character is
    constant H : string(1 to 16) := "0123456789ABCDEF";
  begin
    return H(to_integer(n) + 1);
  end function;

  function line_char(i : natural; b : bcd_t; up : unsigned(15 downto 0)) return character is
    constant FIX : string(1 to LINE_LEN) := "K325T xx.x up 0x....##"; -- x . # replaced below (## = CR LF)
  begin
    case i is
      when 6  => return hexchar(b(0));
      when 7  => return hexchar(b(1));
      when 9  => return hexchar(b(2));
      when 16 => return hexchar(up(15 downto 12));
      when 17 => return hexchar(up(11 downto 8));
      when 18 => return hexchar(up(7 downto 4));
      when 19 => return hexchar(up(3 downto 0));
      when 20 => return CR;
      when 21 => return LF;
      when others => return FIX(i + 1);
    end case;
  end function;

begin

  ---------------------------------------------------------------------------
  -- Time base, BCD counter (bcd(0) = tens of seconds, bcd(2) = tenths)
  ---------------------------------------------------------------------------
  process (clk50)
  begin
    if rising_edge(clk50) then
      sw1_s <= sw1_s(0) & sw1_n;
      sw2_s <= sw2_s(0) & sw2_n;
      tick <= '0';
      sec_tick <= '0';
      if tick_cnt = CLK_HZ / TICK_HZ - 1 then
        tick_cnt <= 0;
        tick <= '1';
      else
        tick_cnt <= tick_cnt + 1;
      end if;

      if tick = '1' then
        if tenths = TICK_HZ - 1 then
          tenths <= 0;
          sec_tick <= '1';
          uptime <= uptime + 1;
        else
          tenths <= tenths + 1;
        end if;
        if sw1_s(1) = '1' then  -- not held
          if bcd(2) = 9 then
            bcd(2) <= x"0";
            if bcd(1) = 9 then
              bcd(1) <= x"0";
              if bcd(0) = 9 then bcd(0) <= x"0"; else bcd(0) <= bcd(0) + 1; end if;
            else
              bcd(1) <= bcd(1) + 1;
            end if;
          else
            bcd(2) <= bcd(2) + 1;
          end if;
        end if;
      end if;
      if sw2_s(1) = '0' then
        bcd <= (others => x"0");
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- 7-segment multiplex (one digit at a time, short blanking between)
  ---------------------------------------------------------------------------
  process (clk50)
    variable s : std_logic_vector(6 downto 0);
  begin
    if rising_edge(clk50) then
      if mux_cnt = CLK_HZ / MUX_HZ - 1 then
        mux_cnt <= 0;
        if mux_sel = 2 then mux_sel <= 0; else mux_sel <= mux_sel + 1; end if;
      else
        mux_cnt <= mux_cnt + 1;
      end if;
      s := seg7(bcd(mux_sel));
      seg_n(6 downto 0) <= not s;
      if mux_sel = 1 then seg_n(7) <= '0'; else seg_n(7) <= '1'; end if;  -- "SS.S"
      dig <= (others => '0');
      if mux_cnt > 64 and mux_cnt < CLK_HZ / MUX_HZ - 64 then  -- ghosting guard
        dig(mux_sel) <= '1';
      end if;
    end if;
  end process;

  g_led : for i in 0 to 4 generate  -- D5 = bit 0 (rightmost LED = LSB)
    db_led_n(i) <= not uptime(4 - i);
  end generate;
  core_led_n(0) <= '0' when tenths < TICK_HZ / 2 else '1';
  core_led_n(1) <= not rx_led;

  ---------------------------------------------------------------------------
  -- UART: RX with echo, TX of banner, status lines and echoed bytes
  ---------------------------------------------------------------------------
  process (clk50)
    variable c : character;
  begin
    if rising_edge(clk50) then
      -- receiver
      rx_s <= rx_s(1 downto 0) & uart_rx;
      if rx_busy = '0' then
        if rx_s(2) = '0' then  -- start bit edge
          rx_busy <= '1';
          rx_cnt  <= BIT_CLKS + BIT_CLKS / 2 - 1;  -- middle of bit 0
          rx_bits <= 0;
        end if;
      elsif rx_cnt = 0 then
        rx_cnt <= BIT_CLKS - 1;
        if rx_bits = 8 then
          rx_busy <= '0';
          if rx_s(2) = '1' then  -- valid stop bit
            echo_full <= '1';
            echo_byte <= rx_sr;
            rx_led <= not rx_led;
          end if;
        else
          rx_sr   <= rx_s(2) & rx_sr(7 downto 1);
          rx_bits <= rx_bits + 1;
        end if;
      else
        rx_cnt <= rx_cnt - 1;
      end if;

      -- transmitter
      if sec_tick = '1' then
        line_req <= '1';
      end if;
      if tx_bits /= 0 then
        if tx_cnt = 0 then
          tx_cnt   <= BIT_CLKS - 1;
          tx_shift <= '1' & tx_shift(9 downto 1);
          tx_bits  <= tx_bits - 1;
        else
          tx_cnt <= tx_cnt - 1;
        end if;
      else
        -- idle: pick the next byte
        if msg_banner = '1' then
          c := BANNER(msg_idx + 1);
          tx_shift <= '1' & std_logic_vector(to_unsigned(character'pos(c), 8)) & '0';
          tx_bits <= 10; tx_cnt <= BIT_CLKS - 1;
          if msg_idx = BANNER'length - 1 then msg_idx <= 0; msg_banner <= '0';
          else msg_idx <= msg_idx + 1; end if;
        elsif msg_line = '1' then
          c := line_char(msg_idx, snap_bcd, snap_up);
          tx_shift <= '1' & std_logic_vector(to_unsigned(character'pos(c), 8)) & '0';
          tx_bits <= 10; tx_cnt <= BIT_CLKS - 1;
          if msg_idx = LINE_LEN - 1 then msg_idx <= 0; msg_line <= '0';
          else msg_idx <= msg_idx + 1; end if;
        elsif echo_full = '1' then
          tx_shift <= '1' & echo_byte & '0';
          tx_bits <= 10; tx_cnt <= BIT_CLKS - 1;
          echo_full <= '0';
        elsif line_req = '1' then
          line_req <= '0';
          msg_line <= '1';
          msg_idx  <= 0;
          snap_bcd <= bcd;
          snap_up  <= uptime;
        end if;
      end if;
    end if;
  end process;
  uart_tx <= tx_shift(0) when tx_bits /= 0 else '1';

  ---------------------------------------------------------------------------
  -- VGA 640x480: h 640+16+96+48 = 800, v 480+10+2+33 = 525, sync negative
  ---------------------------------------------------------------------------
  process (clk50)
    variable x, y : unsigned(9 downto 0);
    variable r, b : unsigned(4 downto 0);
    variable g    : unsigned(5 downto 0);
    variable bar  : unsigned(2 downto 0);
  begin
    if rising_edge(clk50) then
      pix_ce <= not pix_ce;
      if pix_ce = '1' then
        if hcnt = 799 then
          hcnt <= (others => '0');
          if vcnt = 524 then
            vcnt <= (others => '0');
            -- move the box once per frame
            if box_dx = '0' then
              if box_x >= 640 - 48 - 2 then box_dx <= '1'; end if;
              box_x <= box_x + 2;
            else
              if box_x <= 2 then box_dx <= '0'; end if;
              box_x <= box_x - 2;
            end if;
            if box_dy = '0' then
              if box_y >= 400 - 48 - 1 then box_dy <= '1'; end if;
              box_y <= box_y + 1;
            else
              if box_y <= 1 then box_dy <= '0'; end if;
              box_y <= box_y - 1;
            end if;
          else
            vcnt <= vcnt + 1;
          end if;
        else
          hcnt <= hcnt + 1;
        end if;

        x := hcnt; y := vcnt;
        if x < 640 and y < 480 then
          if y >= 400 then
            -- grey ramp: 32 steps of 20 pixels, same code on all channels
            r := resize(x / 20, 5);
            g := r & '0';
            b := r;
          else
            bar := resize(x / 80, 3);  -- 0 white .. 7 black (SMPTE order)
            -- table: white yellow cyan green magenta red blue black
            case to_integer(bar) is
              when 0 => r := "11111"; g := "111111"; b := "11111";
              when 1 => r := "11111"; g := "111111"; b := "00000";
              when 2 => r := "00000"; g := "111111"; b := "11111";
              when 3 => r := "00000"; g := "111111"; b := "00000";
              when 4 => r := "11111"; g := "000000"; b := "11111";
              when 5 => r := "11111"; g := "000000"; b := "00000";
              when 6 => r := "00000"; g := "000000"; b := "11111";
              when others => r := "00000"; g := "000000"; b := "00000";
            end case;
            if x >= box_x and x < box_x + 48 and y >= box_y and y < box_y + 48 then
              r := not r; g := not g; b := not b;
            end if;
          end if;
          vga_r <= std_logic_vector(r);
          vga_g <= std_logic_vector(g);
          vga_b <= std_logic_vector(b);
        else
          vga_r <= (others => '0');
          vga_g <= (others => '0');
          vga_b <= (others => '0');
        end if;
        if x >= 656 and x < 752 then vga_hs <= '0'; else vga_hs <= '1'; end if;
        if y >= 490 and y < 492 then vga_vs <= '0'; else vga_vs <= '1'; end if;
      end if;
    end if;
  end process;

end architecture;
