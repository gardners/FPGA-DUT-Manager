-- tb_testdut_uart: test_dut UART echo and status line (issue 0068) with
-- shortened timing: 100 MHz clock, 1 "ms" = 1000 cycles, a status line
-- every 20 "ms" (200 us), 10 Mbaud. Checks the exact status line text,
-- echo, that echo bytes arriving during a line wait until it is complete,
-- the counters, and rxline/lowms/ferr while the RX line is held low.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_testdut_uart is
end entity;

architecture tb of tb_testdut_uart is
  constant INC : unsigned(31 downto 0) := x"1999_999A";  -- 10 Mbaud @ 100 MHz
  constant LINE_LEN : positive := 115;
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  -- stimulus UART (the "supervisor")
  signal s_data : std_logic_vector(7 downto 0) := (others => '0');
  signal s_valid, s_ready, s_txd : std_logic := '0';
  signal hold_low : boolean := false;
  signal rxd, txd : std_logic;
  -- monitor
  signal m_data : std_logic_vector(7 downto 0);
  signal m_valid, m_ferr : std_logic;
  signal buf : string(1 to 1000) := (others => ' ');
  signal n   : natural := 0;
  signal rx_level, rx_stb, tx_stb, sec_stb : std_logic;
  signal rx_low_ms : unsigned(31 downto 0);

  function dec8(v : natural) return string is
    variable s : string(1 to 8);
    variable x : natural := v;
  begin
    for i in 8 downto 1 loop
      s(i) := character'val(character'pos('0') + x mod 10);
      x := x / 10;
    end loop;
    return s;
  end function;
  function line(up, rx, tx : natural; lvl : character; low, ferr, drop : natural) return string is
  begin
    return "TESTDUT v1 build 0123abcd up " & dec8(up) & " rx " & dec8(rx) & " tx " & dec8(tx) &
           " rxline " & lvl & " lowms " & dec8(low) & " ferr " & dec8(ferr) &
           " drop " & dec8(drop) & character'val(13) & character'val(10);
  end function;
begin
  clk <= not clk after 5 ns when not done;
  rxd <= '0' when hold_low else s_txd;

  dut : entity work.testdut_uart
    generic map (CLK_PER_MS => 1000, MS_PER_STATUS => 20, BAUD_INC => INC, BUILD_ID => x"0123ABCD")
    port map (clk, rxd, txd, rx_level, rx_low_ms, rx_stb, tx_stb, sec_stb);

  stx : entity work.uart_tx port map (clk, INC, s_data, s_valid, s_ready, s_txd);
  mrx : entity work.uart_rx port map (clk, INC, txd, m_data, m_valid, m_ferr);

  mon : process (clk)
  begin
    if rising_edge(clk) then
      assert m_ferr /= '1' report "framing error on test_dut TX" severity failure;
      if m_valid = '1' then
        buf(n + 1) <= character'val(to_integer(unsigned(m_data)));
        n <= n + 1;
      end if;
    end if;
  end process;

  stim : process
    procedure send(s : string) is
    begin
      for i in s'range loop
        wait until rising_edge(clk) and s_ready = '1';
        s_data  <= std_logic_vector(to_unsigned(character'pos(s(i)), 8));
        s_valid <= '1';
        wait until rising_edge(clk);
        s_valid <= '0';
        wait until rising_edge(clk);
      end loop;
    end procedure;
    procedure expect(at : positive; s : string; what : string) is
    begin
      assert buf(at to at + s'length - 1) = s
        report what & ": got """ & buf(at to at + s'length - 1) & """ expected """ & s & """"
        severity failure;
    end procedure;
    variable l3a, l3b : string(1 to LINE_LEN);
  begin
    -- line 1: nothing received yet, line high
    wait until n = LINE_LEN for 400 us;
    expect(1, line(1, 0, 0, '1', 0, 0, 0), "line 1");
    -- echo
    send("Hello");
    wait until n = LINE_LEN + 5 for 50 us;
    expect(LINE_LEN + 1, "Hello", "echo");
    -- bytes arriving during line 2 are echoed after it
    wait until n = LINE_LEN + 5 + 20 for 300 us;
    send("xy");
    wait until n = 2 * LINE_LEN + 7 for 200 us;
    expect(LINE_LEN + 6, line(2, 5, 120, '1', 0, 0, 0), "line 2");
    expect(2 * LINE_LEN + 6, "xy", "echo after line");
    -- hold the RX line low (the supervisor's TX low, issue 0067)
    hold_low <= true;
    wait for 30 us;
    assert rx_level = '0' report "rx_level not low" severity failure;
    wait until n = 3 * LINE_LEN + 7 for 300 us;
    -- lowms is 8 or 9 depending on the ms tick phase
    l3a := line(3, 7, 237, '0', 8, 1, 0);
    l3b := line(3, 7, 237, '0', 9, 1, 0);
    assert buf(2 * LINE_LEN + 8 to 3 * LINE_LEN + 7) = l3a or
           buf(2 * LINE_LEN + 8 to 3 * LINE_LEN + 7) = l3b
      report "line 3: got """ & buf(2 * LINE_LEN + 8 to 3 * LINE_LEN + 7) & """" severity failure;
    assert rx_low_ms >= x"00000010" report "rx_low_ms not counting" severity failure;
    hold_low <= false;
    wait for 1 us;
    assert rx_low_ms = 0 and rx_level = '1' report "low duration not cleared" severity failure;
    wait until n = 4 * LINE_LEN + 7 for 300 us;
    expect(3 * LINE_LEN + 8, line(4, 7, 352, '1', 0, 1, 0), "line 4");
    report "tb_testdut_uart PASSED";
    done <= true;
    wait;
  end process;
end architecture;
