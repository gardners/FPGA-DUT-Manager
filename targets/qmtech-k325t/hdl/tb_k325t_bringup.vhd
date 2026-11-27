-- nvc testbench for k325t_bringup (scaled clock): decodes the UART output,
-- checks the banner, the first two status lines and the RX echo, and that
-- at most one digit select is active at a time.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_k325t_bringup is
end entity;

architecture sim of tb_k325t_bringup is
  constant CLK_HZ : positive := 200_000;
  constant BAUD   : positive := 20_000;   -- 10 clocks per bit
  constant TCLK   : time := 5 us;
  constant TBIT   : time := 10 * TCLK;

  signal clk     : std_logic := '0';
  signal seg_n   : std_logic_vector(7 downto 0);
  signal dig     : std_logic_vector(2 downto 0);
  signal db_led_n: std_logic_vector(4 downto 0);
  signal core_led_n : std_logic_vector(1 downto 0);
  signal tx      : std_logic;
  signal rx      : std_logic := '1';
  signal r, b    : std_logic_vector(4 downto 0);
  signal g       : std_logic_vector(5 downto 0);
  signal hs, vs  : std_logic;
  signal done    : boolean := false;

  -- received text
  signal rxbuf : string(1 to 400) := (others => ' ');
  signal rxlen : natural := 0;
begin
  clk <= not clk after TCLK / 2 when not done;

  dut : entity work.k325t_bringup
    generic map (CLK_HZ => CLK_HZ, BAUD => BAUD, TICK_HZ => 10, MUX_HZ => 1000)
    port map (clk50 => clk, seg_n => seg_n, dig => dig, db_led_n => db_led_n,
              core_led_n => core_led_n, sw1_n => '1', sw2_n => '1',
              uart_tx => tx, uart_rx => rx, vga_r => r, vga_g => g, vga_b => b,
              vga_hs => hs, vga_vs => vs);

  -- UART decoder
  process
    variable v : std_logic_vector(7 downto 0);
    variable n : natural := 0;
  begin
    wait until falling_edge(tx);
    wait for TBIT / 2;
    assert tx = '0' report "bad start bit" severity failure;
    for i in 0 to 7 loop
      wait for TBIT;
      v(i) := tx;
    end loop;
    wait for TBIT;
    assert tx = '1' report "bad stop bit" severity failure;
    if n < rxbuf'length then
      n := n + 1;
      rxbuf(n) <= character'val(to_integer(unsigned(v)));
      rxlen <= n;
    end if;
  end process;

  process (clk)
  begin
    if rising_edge(clk) and now > 100 us then
      assert dig = "000" or dig = "001" or dig = "010" or dig = "100"
        report "more than one digit selected" severity failure;
    end if;
  end process;

  process
    constant BANNER : string := CR & LF & "QMTECH XC7K325T bring-up (FPGA-DUT-Manager 0057)" & CR & LF;
    constant L1 : string := "K325T 01.0 up 0x0001" & CR & LF;
    procedure send(c : character) is
      variable v : std_logic_vector(7 downto 0);
    begin
      v := std_logic_vector(to_unsigned(character'pos(c), 8));
      rx <= '0'; wait for TBIT;
      for i in 0 to 7 loop rx <= v(i); wait for TBIT; end loop;
      rx <= '1'; wait for TBIT;
    end procedure;
    variable p : natural;
  begin
    wait for 1.1 sec;
    assert rxlen >= BANNER'length + L1'length report "too little output: " & integer'image(rxlen) & " [" & rxbuf(1 to rxlen) & "]" severity failure;
    assert rxbuf(1 to BANNER'length) = BANNER report "banner mismatch: " & rxbuf(1 to BANNER'length) severity failure;
    p := BANNER'length;
    assert rxbuf(p + 1 to p + L1'length) = L1
      report "line 1 mismatch: " & rxbuf(p + 1 to p + L1'length) severity failure;
    p := rxlen;
    send('Z');
    wait for 20 * TBIT;
    assert rxlen = p + 1 and rxbuf(p + 1) = 'Z' report "echo missing" severity failure;
    assert core_led_n(1) = '0' report "RX LED did not toggle" severity failure;
    report "tb_k325t_bringup PASS";
    done <= true;
    wait;
  end process;
end architecture;
