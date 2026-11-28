-- testdut_uart: UART side of the test_dut bitstream (issue 0068).
--
-- * Echo: every byte received on rxd is queued (512-byte FIFO in block
--   RAM) and sent back on txd. Bytes arriving while the FIFO is full are
--   dropped and counted.
-- * Status line once per MS_PER_STATUS milliseconds (default 1 s), never
--   interleaved with echo bytes (it starts only when the echo FIFO is
--   empty; echo bytes arriving meanwhile wait in the FIFO):
--     TESTDUT v1 build BBBBBBBB up UUUUUUUU rx RRRRRRRR tx TTTTTTTT rxline L lowms MMMMMMMM ferr FFFFFFFF drop DDDDDDDD<CR><LF>
--   BBBBBBBB = BUILD_ID (git short hash, hex). Other numbers decimal, 8 digits with leading zeros (BCD counters,
--   saturating at 99999999): up = status periods since configuration
--   (seconds), rx/tx = bytes received/sent (tx counts echo and status
--   bytes, before this line), rxline = level of rxd (the supervisor's TX)
--   at the start of the line, lowms = how long rxd has been continuously
--   low (0 while high), ferr = framing errors (a line held low counts one),
--   drop = echo bytes lost to a full FIFO. 115 bytes per
--   line (575 us at 2 Mbaud).
-- * rx_level / rx_low_ms / strobes for the board's LEDs and display.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity testdut_uart is
  generic (
    CLK_PER_MS    : positive := 100_000;                -- 100 MHz
    MS_PER_STATUS : positive := 1000;
    BAUD_INC      : unsigned(31 downto 0) := x"051E_B852"; -- 2 Mbaud @ 100 MHz
    BUILD_ID      : std_logic_vector(31 downto 0) := x"00000000"  -- shown in the line
  );
  port (
    clk       : in  std_logic;
    rxd       : in  std_logic;           -- asynchronous (supervisor's TX)
    txd       : out std_logic;
    rx_level  : out std_logic;           -- synchronised rxd
    rx_low_ms : out unsigned(31 downto 0);  -- BCD, ms continuously low
    rx_stb    : out std_logic;           -- byte received
    tx_stb    : out std_logic;           -- byte sent (accepted by uart_tx)
    sec_stb   : out std_logic            -- one per status period
  );
end entity;

architecture rtl of testdut_uart is
  -- BCD +1, saturating at 99999999
  function bcd_inc(v : unsigned(31 downto 0)) return unsigned is
    variable r : unsigned(31 downto 0) := v;
    variable carry : boolean := true;
  begin
    if v = x"99999999" then
      return v;
    end if;
    for i in 0 to 7 loop
      if carry then
        if r(4 * i + 3 downto 4 * i) = 9 then
          r(4 * i + 3 downto 4 * i) := x"0";
        else
          r(4 * i + 3 downto 4 * i) := r(4 * i + 3 downto 4 * i) + 1;
          carry := false;
        end if;
      end if;
    end loop;
    return r;
  end function;

  -- '@' = next BCD digit of the snapshot, '%' = rxline digit, '#' = next
  -- hex digit of BUILD_ID (filled in at elaboration)
  constant TEMPLATE : string :=
    "TESTDUT v1 build ######## up @@@@@@@@ rx @@@@@@@@ tx @@@@@@@@ rxline % lowms @@@@@@@@ ferr @@@@@@@@ drop @@@@@@@@" &
    character'val(13) & character'val(10);
  constant TLEN : positive := TEMPLATE'length;

  type rom_t is array (0 to TLEN - 1) of std_logic_vector(7 downto 0);
  function mk_rom return rom_t is
    variable r : rom_t;
    variable h : natural := 7;
    variable x : natural;
  begin
    for i in 0 to TLEN - 1 loop
      if TEMPLATE(TEMPLATE'low + i) = '#' then
        x := to_integer(unsigned(BUILD_ID(4 * h + 3 downto 4 * h)));
        if x < 10 then
          r(i) := std_logic_vector(to_unsigned(48 + x, 8));   -- 0-9
        else
          r(i) := std_logic_vector(to_unsigned(87 + x, 8));   -- a-f
        end if;
        if h > 0 then h := h - 1; end if;
      else
        r(i) := std_logic_vector(to_unsigned(character'pos(TEMPLATE(TEMPLATE'low + i)), 8));
      end if;
    end loop;
    return r;
  end function;
  constant ROM : rom_t := mk_rom;

  signal rx_s      : std_logic_vector(1 downto 0) := (others => '1');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rx_s : signal is "TRUE";
  signal rx_lvl    : std_logic;

  signal urx_data  : std_logic_vector(7 downto 0);
  signal urx_valid, urx_ferr : std_logic;
  signal utx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal utx_valid : std_logic := '0';
  signal utx_ready : std_logic;

  signal f_we      : std_logic := '0';
  signal f_wa, f_ra : unsigned(8 downto 0) := (others => '0');
  signal f_wd, f_rd : std_logic_vector(7 downto 0);
  signal wr_ptr, rd_ptr : unsigned(9 downto 0) := (others => '0');

  signal ms_cnt    : integer range 0 to CLK_PER_MS - 1 := 0;
  signal per_cnt   : integer range 0 to MS_PER_STATUS - 1 := 0;
  signal pending   : std_logic := '0';
  signal c_up, c_rx, c_tx, c_low, c_ferr, c_drop : unsigned(31 downto 0) := (others => '0');

  signal snap      : unsigned(191 downto 0) := (others => '0');
  signal snap_lvl  : std_logic := '0';
  signal pos       : integer range 0 to TLEN - 1 := 0;

  type state_t is (S_IDLE, S_ECHO_RD, S_ECHO_LATCH, S_SEND, S_WAIT, S_LINE);
  signal state     : state_t := S_IDLE;
  signal in_line   : std_logic := '0';
begin
  urx : entity work.uart_rx port map (clk, BAUD_INC, rxd, urx_data, urx_valid, urx_ferr);
  utx : entity work.uart_tx port map (clk, BAUD_INC, utx_data, utx_valid, utx_ready, txd);
  fifo : entity work.dpram generic map (9, 8)
    port map (clk, f_we, f_wa, f_wd, clk, f_ra, f_rd);

  rx_lvl    <= rx_s(1);
  rx_level  <= rx_lvl;
  rx_low_ms <= c_low;
  rx_stb    <= urx_valid;

  process (clk)
    variable ms_tick, tx_acc : boolean;
  begin
    if rising_edge(clk) then
      rx_s    <= rx_s(0) & rxd;
      f_we    <= '0';
      utx_valid <= '0';
      sec_stb <= '0';

      -- millisecond / status period timers
      ms_tick := ms_cnt = CLK_PER_MS - 1;
      if ms_tick then
        ms_cnt <= 0;
        if per_cnt = MS_PER_STATUS - 1 then
          per_cnt <= 0;
          pending <= '1';
          c_up    <= bcd_inc(c_up);
          sec_stb <= '1';
        else
          per_cnt <= per_cnt + 1;
        end if;
      else
        ms_cnt <= ms_cnt + 1;
      end if;

      -- line-low duration
      if rx_lvl = '1' then
        c_low <= (others => '0');
      elsif ms_tick then
        c_low <= bcd_inc(c_low);
      end if;

      -- receive into the echo FIFO
      if urx_valid = '1' then
        c_rx <= bcd_inc(c_rx);
        if wr_ptr - rd_ptr < 512 then
          f_we   <= '1';
          f_wa   <= wr_ptr(8 downto 0);
          f_wd   <= urx_data;
          wr_ptr <= wr_ptr + 1;
        else
          c_drop <= bcd_inc(c_drop);
        end if;
      end if;
      if urx_ferr = '1' then
        c_ferr <= bcd_inc(c_ferr);
      end if;

      -- transmit sequencer
      tx_acc := false;
      case state is
        when S_IDLE =>
          if pending = '1' and wr_ptr = rd_ptr then
            pending  <= '0';
            snap     <= c_up & c_rx & c_tx & c_low & c_ferr & c_drop;
            snap_lvl <= rx_lvl;
            pos      <= 0;
            in_line  <= '1';
            state    <= S_LINE;
          elsif wr_ptr /= rd_ptr then
            f_ra  <= rd_ptr(8 downto 0);
            state <= S_ECHO_RD;
          end if;
        when S_ECHO_RD =>                -- dpram read latency
          state <= S_ECHO_LATCH;
        when S_ECHO_LATCH =>
          utx_data <= f_rd;
          rd_ptr   <= rd_ptr + 1;
          in_line  <= '0';
          state    <= S_SEND;
        when S_LINE =>
          if ROM(pos) = x"40" then        -- '@'
            utx_data <= std_logic_vector(x"3" & snap(191 downto 188));
            snap     <= snap(187 downto 0) & x"0";
          elsif ROM(pos) = x"25" then     -- '%'
            utx_data <= "0011000" & snap_lvl;
          else
            utx_data <= ROM(pos);
          end if;
          state <= S_SEND;
        when S_SEND =>
          if utx_ready = '1' then
            utx_valid <= '1';
            tx_acc    := true;
            state     <= S_WAIT;
          end if;
        when S_WAIT =>                   -- until uart_tx has taken it
          if utx_ready = '0' then
            if in_line = '1' and pos /= TLEN - 1 then
              pos   <= pos + 1;
              state <= S_LINE;
            else
              in_line <= '0';
              state   <= S_IDLE;
            end if;
          end if;
      end case;
      if tx_acc then
        c_tx <= bcd_inc(c_tx);
      end if;
      tx_stb <= '1' when tx_acc else '0';
    end if;
  end process;
end architecture;
