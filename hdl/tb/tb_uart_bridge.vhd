-- tb_uart_bridge: TX looped back to RX.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_bridge is
end entity;

architecture tb of tb_uart_bridge is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal tick : std_logic := '0';
  signal line : std_logic;
  signal oe   : std_logic;
  signal out_en, snap_en, fast : std_logic := '0';
  signal period : unsigned(15 downto 0) := to_unsigned(1000, 16);
  signal adm_valid, adm_clear, adm_done, adm_ok, wr_valid : std_logic := '0';
  signal adm_offset : unsigned(31 downto 0) := (others => '0');
  signal adm_count, adm_cmd : unsigned(15 downto 0) := (others => '0');
  signal wr_data : std_logic_vector(7 downto 0);
  signal snap_req, snap_ack : std_logic := '0';
  signal hist_addr : unsigned(9 downto 0) := (others => '0');
  signal hist_data : std_logic_vector(7 downto 0);
  signal s_rx_seq, s_tx_acc, s_tx_emit, s_rxclr, s_seq : unsigned(31 downto 0);
  signal s_free, s_ferr, s_ovf, s_rej, s_cgen : unsigned(15 downto 0);
  signal rx_seq, tx_acc : unsigned(31 downto 0);
  -- 12.5 Mbaud keeps simulation short
  constant INC : unsigned(31 downto 0) := to_unsigned(429496730, 32);
  signal req_count : natural := 0;

  type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);
  signal hist : bytes_t(0 to 639);
begin
  clk <= not clk after 4 ns when not done;
  process
  begin
    while not done loop
      wait for 992 ns; wait until rising_edge(clk); tick <= '1';
      wait until rising_edge(clk); tick <= '0';
    end loop;
    wait;
  end process;

  dut : entity work.uart_bridge
    generic map (MIN_SPACING_US => 20)
    port map (
      clk => clk, tick_1us => tick, baud_inc => INC, out_enable => out_en,
      snap_enable => snap_en, fast_mode => fast, snap_period_us => period,
      txd => line, txd_oe => oe, rxd => line,
      adm_valid => adm_valid, adm_offset => adm_offset, adm_count => adm_count,
      adm_clear => adm_clear, adm_cmd_id => adm_cmd, adm_done => adm_done,
      adm_ok => adm_ok, wr_valid => wr_valid, wr_data => wr_data,
      snap_req => snap_req, snap_ack => snap_ack, hist_addr => hist_addr,
      hist_data => hist_data,
      snap_rx_seq => s_rx_seq, snap_tx_accepted => s_tx_acc,
      snap_tx_emitted => s_tx_emit, snap_tx_free => s_free,
      snap_framing_errs => s_ferr, snap_rx_overflows => s_ovf,
      snap_tx_rejects => s_rej, snap_clear_gen => s_cgen,
      snap_rx_seq_clear => s_rxclr, snap_seq => s_seq,
      rx_seq_o => rx_seq, tx_accepted_o => tx_acc);

  process (clk)
  begin
    if rising_edge(clk) and snap_req = '1' and snap_ack = '0' then
      null;
    end if;
  end process;

  stim : process
    variable ok : boolean;

    procedure admit(off : natural; data : bytes_t; clear : std_logic; cmd : natural;
                    expect_ok : boolean) is
    begin
      wait until rising_edge(clk);
      adm_valid <= '1'; adm_offset <= to_unsigned(off, 32);
      adm_count <= to_unsigned(data'length, 16); adm_clear <= clear;
      adm_cmd <= to_unsigned(cmd, 16);
      wait until rising_edge(clk);
      adm_valid <= '0';
      wait until rising_edge(clk) and adm_done = '1';
      assert (adm_ok = '1') = expect_ok report "admission result unexpected" severity failure;
      if adm_ok = '1' then
        for i in data'range loop
          wr_valid <= '1'; wr_data <= data(i);
          wait until rising_edge(clk);
        end loop;
        wr_valid <= '0';
      end if;
    end procedure;

    procedure take_snapshot is
    begin
      wait until rising_edge(clk);
      snap_ack <= '1';
      wait until rising_edge(clk);
      snap_ack <= '0';
      for a in 0 to 640 loop
        if a < 640 then hist_addr <= to_unsigned(a, 10); end if;
        wait until rising_edge(clk);
        if a > 0 then hist(a - 1) <= hist_data; end if;
      end loop;
      wait until rising_edge(clk);
    end procedure;

    function str_bytes(s : string) return bytes_t is
      variable r : bytes_t(0 to s'length - 1);
    begin
      for i in s'range loop
        r(i - s'low) := std_logic_vector(to_unsigned(character'pos(s(i)), 8));
      end loop;
      return r;
    end function;

    variable big : bytes_t(0 to 999);
    variable sent : natural := 0;
  begin
    wait for 100 ns;
    -- 1. outputs disabled: admitted bytes wait in the ring
    admit(0, str_bytes("HELLO"), '0', 1, true);
    wait for 20 us;
    assert rx_seq = 0 report "TX while out_enable=0" severity failure;
    out_en <= '1';
    wait for 10 us;
    assert rx_seq = 5 report "loopback count " & integer'image(to_integer(rx_seq)) severity failure;
    sent := 5;

    -- 2. snapshot contents
    take_snapshot;
    assert s_rx_seq = 5 and s_tx_acc = 5 and s_tx_emit = 5 report "counters" severity failure;
    for i in 0 to 506 loop
      assert hist(i) = x"00" report "rx padding not zero at " & integer'image(i) severity failure;
    end loop;
    for i in 0 to 4 loop
      assert hist(507 + i) = str_bytes("HELLO")(i) report "rx history byte " & integer'image(i) severity failure;
      assert hist(635 + i) = str_bytes("HELLO")(i) report "tx history byte " & integer'image(i) severity failure;
    end loop;
    for i in 512 to 634 loop
      assert hist(i) = x"00" report "tx padding" severity failure;
    end loop;

    -- 3. wrong offset rejected, expedited snapshot requested
    snap_en <= '1'; period <= to_unsigned(60000, 16);
    admit(3, str_bytes("X"), '0', 2, false);
    wait for 25 us;
    assert snap_req = '1' report "no expedited snapshot after reject" severity failure;
    take_snapshot;
    assert s_rej = 1 report "reject not counted" severity failure;

    -- 4. clear history (idempotent by cmd_id)
    admit(5, str_bytes(""), '1', 77, true);
    admit(5, str_bytes(""), '1', 77, true);
    take_snapshot;
    assert s_cgen = 1 report "clear generation " & integer'image(to_integer(s_cgen)) severity failure;
    assert s_rxclr = 5 report "rx_seq_at_clear" severity failure;
    for i in 0 to 511 loop
      assert hist(i) = x"00" report "history not cleared" severity failure;
    end loop;
    admit(5, str_bytes("AB"), '0', 3, true);
    wait for 5 us;
    take_snapshot;
    assert hist(510) = x"41" and hist(511) = x"42" and hist(509) = x"00"
      report "post-clear history" severity failure;
    sent := 7;

    -- 5. too large for free space is rejected (ring 2048)
    out_en <= '0';
    for i in big'range loop big(i) := std_logic_vector(to_unsigned(i mod 251, 8)); end loop;
    admit(7, big, '0', 4, true);           -- 1000 queued
    admit(1007, big, '0', 5, true);        -- 2000 queued
    admit(2007, big(0 to 99), '0', 6, false);  -- 100 > 48 free
    out_en <= '1';
    wait until rx_seq = 2007 for 2 ms;
    assert rx_seq = 2007 report "ring drain incomplete: " & integer'image(to_integer(rx_seq)) severity failure;
    take_snapshot;
    -- last 512 RX bytes are big(488..999)
    for i in 0 to 511 loop
      assert hist(i) = big(488 + i) report "wrapped history mismatch at " & integer'image(i) severity failure;
    end loop;

    -- 6. periodic snapshots every 50 us when enabled
    period <= to_unsigned(50, 16);
    wait for 1 us;
    for n in 1 to 3 loop
      wait until snap_req = '1' for 80 us;
      assert snap_req = '1' report "periodic snapshot missing" severity failure;
      take_snapshot;
    end loop;

    report "tb_uart_bridge PASSED";
    done <= true;
    wait;
  end process;
end architecture;
