-- tb_test_dut_top: smoke test of the test_dut top level (issue 0068):
-- "powered" output and DIP 0, UART echo through the pins (USB UART mirror
-- included), IDCODE through the TAP pins, LEDs and the 7-segment display
-- ("tdut", "r Lo" while the RX line is held low). Shortened timing:
-- 1 "ms" = 100 cycles; no status line within the run.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_test_dut_top is
end entity;

architecture tb of tb_test_dut_top is
  constant INC : unsigned(31 downto 0) := x"1999_999A";  -- 10 Mbaud @ 100 MHz
  constant ID  : std_logic_vector(31 downto 0) := x"7E57D001";
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal led, seg : std_logic_vector(7 downto 0);
  signal seg_en : std_logic_vector(3 downto 0);
  signal dip : std_logic_vector(7 downto 0) := (others => '0');
  signal usb_tx, utx, urx, pow, tck, tms, tdi, tdo : std_logic;
  signal spare : std_logic := '0';
  signal hold_low : boolean := false;
  signal s_data, m_data : std_logic_vector(7 downto 0) := (others => '0');
  signal s_valid, s_ready, s_txd, m_valid, m_ferr : std_logic := '0';
  signal got : std_logic_vector(7 downto 0) := (others => '0');
  signal ngot : natural := 0;
  signal jtck, jtms, jtdi : std_logic := '0';

  -- active-low seg pins (G F A B DP C D E) for a gfedcba pattern, DP off
  function pins(lit : std_logic_vector(6 downto 0)) return std_logic_vector is
    variable s : std_logic_vector(7 downto 0);
  begin
    s := not (lit(4) & lit(3) & lit(2) & '0' & lit(1) & lit(0) & lit(5) & lit(6));
    return s;
  end function;
begin
  clk <= not clk after 5 ns when not done;
  urx <= '0' when hold_low else s_txd;
  tck <= jtck; tms <= jtms; tdi <= jtdi;

  dut : entity work.test_dut_top
    generic map (CLK_PER_MS => 100, MS_PER_STATUS => 1000, BAUD_INC => INC, IDCODE => ID)
    port map (clk100 => clk, led => led, seg => seg, seg_en => seg_en, dip => dip,
              usb_uart_tx => usb_tx, dut_uart_tx => utx, dut_uart_rx => urx,
              dut_powered => pow, dut_tck => tck, dut_tms => tms, dut_tdi => tdi,
              dut_tdo => tdo, dut_spare => spare);

  stx : entity work.uart_tx port map (clk, INC, s_data, s_valid, s_ready, s_txd);
  mrx : entity work.uart_rx port map (clk, INC, utx, m_data, m_valid, m_ferr);

  mon : process (clk)
  begin
    if rising_edge(clk) then
      assert usb_tx = utx report "USB UART mirror differs" severity failure;
      if m_valid = '1' then
        got <= m_data; ngot <= ngot + 1;
      end if;
    end if;
  end process;

  stim : process
    variable o : std_logic;
    variable v : std_logic_vector(31 downto 0);
    procedure clock(m, d : std_logic) is
    begin
      jtms <= m; jtdi <= d; wait for 48 ns;
      jtck <= '1'; wait for 32 ns;
      o := tdo; wait for 16 ns;
      jtck <= '0';
    end procedure;
    -- digit k's segment pins, DP masked out
    procedure check_digit(k : natural; lit : std_logic_vector(6 downto 0); what : string) is
    begin
      wait until rising_edge(clk) and seg_en = not std_logic_vector(to_unsigned(2 ** k, 4));
      wait until rising_edge(clk);
      assert (seg or "00010000") = (pins(lit) or "00010000")
        report what & ": digit " & integer'image(k) & " pins " & to_string(seg) severity failure;
    end procedure;
  begin
    wait for 1 us;
    assert pow = '1' and led(7) = '1' report "powered not driven high" severity failure;
    dip(0) <= '1';
    wait for 100 ns;
    assert pow = '0' and led(7) = '0' report "DIP 0 does not clear powered" severity failure;
    dip(0) <= '0';
    wait for 100 ns;
    assert pow = '1' report "powered not back" severity failure;

    -- display "tdut"
    check_digit(0, "1111000", "t"); check_digit(1, "1011110", "d");
    check_digit(2, "0011100", "u"); check_digit(3, "1111000", "t");
    assert led(1) = '1' and led(2) = '0' report "rx LEDs idle" severity failure;

    -- echo
    wait until rising_edge(clk) and s_ready = '1';
    s_data <= x"A7"; s_valid <= '1';
    wait until rising_edge(clk);
    s_valid <= '0';
    wait until ngot = 1 for 10 us;
    assert ngot = 1 and got = x"A7" report "no echo" severity failure;
    assert led(3) = '1' and led(4) = '1' report "rx/tx activity LEDs" severity failure;

    -- IDCODE: TLR, RTI, Select-DR, Capture-DR, Shift-DR, 32 bits
    for i in 1 to 5 loop clock('1', '0'); end loop;
    wait for 100 ns;
    assert led(6) = '0' report "TAP not in TLR" severity failure;
    clock('0', '0'); clock('1', '0'); clock('0', '0'); clock('0', '0');
    for i in 0 to 31 loop
      if i = 31 then clock('1', '0'); else clock('0', '0'); end if;
      v(i) := o;
    end loop;
    clock('1', '0'); clock('0', '0');
    assert v = ID report "IDCODE via pins: " & to_hstring(v) severity failure;
    assert led(5) = '1' and led(6) = '1' report "TCK/TAP LEDs" severity failure;

    -- RX held low >= 10 ms: LED 2, "r Lo"
    hold_low <= true;
    wait for 20 us;  -- 20 "ms"
    assert led(1) = '0' and led(2) = '1' report "rx low LEDs" severity failure;
    check_digit(0, "1010000", "r"); check_digit(1, "0000000", "blank");
    check_digit(2, "0111000", "L"); check_digit(3, "1011100", "o");
    hold_low <= false;
    wait for 1 us;
    assert led(2) = '0' report "rx low LED stuck" severity failure;
    report "tb_test_dut_top PASSED";
    done <= true;
    wait;
  end process;
end architecture;
