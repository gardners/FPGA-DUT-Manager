-- tb_uart: uart_tx -> uart_rx loopback at several baud rates, plus a
-- receiver test against an independently timed bit-banged stream with
-- +/-2% baud error and a framing error.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart is
end entity;

architecture tb of tb_uart is
  constant CLK_HZ : real := 125.0e6;
  signal clk   : std_logic := '0';
  signal done  : boolean := false;
  signal inc   : unsigned(31 downto 0);
  signal tdata : std_logic_vector(7 downto 0) := (others => '0');
  signal tval, trdy, txd : std_logic := '0';
  signal rxd   : std_logic := '1';
  signal sel_bb : boolean := false;
  signal bb    : std_logic := '1';
  signal rdata : std_logic_vector(7 downto 0);
  signal rval, ferr : std_logic;
  signal got_count, ferr_count : natural := 0;
  signal last_byte : std_logic_vector(7 downto 0);

  function inc_for(baud : real) return unsigned is
  begin
    return to_unsigned(integer(baud * 4294967296.0 / CLK_HZ / 2.0) * 2, 32);
  end function;
begin
  clk <= not clk after 4 ns when not done;
  rxd <= bb when sel_bb else txd;

  tx : entity work.uart_tx port map (clk, inc, tdata, tval, trdy, txd);
  rx : entity work.uart_rx port map (clk, inc, rxd, rdata, rval, ferr);

  count : process (clk)
  begin
    if rising_edge(clk) then
      if rval = '1' then
        got_count <= got_count + 1;
        last_byte <= rdata;
      end if;
      if ferr = '1' then
        ferr_count <= ferr_count + 1;
      end if;
    end if;
  end process;

  stim : process
    type real_arr is array (natural range <>) of real;
    constant BAUDS : real_arr := (115200.0, 1.0e6, 2.0e6, 4.0e6);
    variable expect : natural := 0;

    procedure send_bb(b : std_logic_vector(7 downto 0); baud : real; stop : std_logic) is
      variable t : time := 1 sec / baud;
    begin
      bb <= '0'; wait for t;
      for i in 0 to 7 loop
        bb <= b(i); wait for t;
      end loop;
      bb <= stop; wait for t;
      bb <= '1'; wait for t;
    end procedure;
  begin
    for bi in BAUDS'range loop
      inc <= inc_for(BAUDS(bi));
      wait for 1 us;
      for v in 0 to 40 loop
        wait until rising_edge(clk) and trdy = '1';
        tdata <= std_logic_vector(to_unsigned((v * 37 + bi * 11) mod 256, 8));
        tval  <= '1';
        wait until rising_edge(clk);
        tval  <= '0';
        expect := expect + 1;
        -- wait for the byte to arrive
        wait until rising_edge(clk) and got_count = expect for 200 us;
        assert got_count = expect report "byte lost at baud " & real'image(BAUDS(bi)) severity failure;
        assert last_byte = std_logic_vector(to_unsigned((v * 37 + bi * 11) mod 256, 8))
          report "data mismatch" severity failure;
      end loop;
    end loop;

    -- receiver tolerance: transmitter 2% fast and 2% slow at 2 Mbaud
    inc <= inc_for(2.0e6);
    sel_bb <= true;
    wait for 2 us;
    for k in -1 to 1 loop
      send_bb(x"A5", 2.0e6 * (1.0 + 0.02 * real(k)), '1');
      expect := expect + 1;
      wait for 1 us;
      assert got_count = expect and last_byte = x"A5"
        report "tolerance test failed k=" & integer'image(k) severity failure;
    end loop;
    -- framing error: stop bit low
    send_bb(x"3C", 2.0e6, '0');
    wait for 2 us;
    assert ferr_count = 1 report "framing error not detected" severity failure;
    assert got_count = expect report "bad frame delivered" severity failure;

    report "tb_uart PASSED";
    done <= true;
    wait;
  end process;
end architecture;
