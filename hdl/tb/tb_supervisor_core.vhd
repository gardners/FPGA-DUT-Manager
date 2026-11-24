-- tb_supervisor_core: drive Ethernet frames from a vector file into the core's
-- GMII RX, capture every GMII TX frame (preamble stripped) to a file, and
-- check FCS framing. Semantic checks: tests/core_scenario.py check.
-- DUT0: UART looped back, JTAG connected to a TAP model; both DUTs powered.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_supervisor_core is
  generic (
    VEC_IN  : string := "core_vectors.txt";
    CAP_OUT : string := "core_capture.txt";
    RUN_US  : natural := 3300
  );
end entity;

architecture tb of tb_supervisor_core is
  signal clk_sys : std_logic := '0';
  signal clk_rx  : std_logic := '0';
  signal done    : boolean := false;
  signal rx_dv, rx_er : std_logic := '0';
  signal rxd     : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_en   : std_logic;
  signal txd     : std_logic_vector(7 downto 0);
  signal jtck, jtms, jtdi, jtdo, joe : std_logic_vector(1 downto 0);
  signal utx, uoe, urx : std_logic_vector(1 downto 0);
  signal kio10, kio10_oe : std_logic_vector(1 downto 0);
  signal leds : std_logic_vector(7 downto 0);
  signal good, bad : unsigned(15 downto 0);
  signal tap_rises : natural;
  signal captured : natural := 0;
begin
  clk_sys <= not clk_sys after 4 ns when not done;
  clk_rx  <= not clk_rx after 4.0016 ns when not done;   -- 200 ppm offset

  dut : entity work.supervisor_core
    generic map (CLK_HZ => 125_000_000, BUILD_ID => x"C0DE0001",
                 DHCP_FALLBACK_MS => 1, DHCP_MS_PER_S => 1)
    port map (
      clk_sys => clk_sys, clk_rx => clk_rx,
      rx_dv => rx_dv, rx_er => rx_er, rxd => rxd, tx_en => tx_en, txd => txd,
      dna => x"0123456789ABCDEF", dip => x"10", link_flags => x"03",
      vio_sense => "11", kb3v3_sense => "11",
      jtck => jtck, jtms => jtms, jtdi => jtdi, jtdo => jtdo, jtag_oe => joe,
      utx => utx, utx_oe => uoe, urx => urx,
      kio8 => "00", kio9 => "00", kio10 => kio10, kio10_oe => kio10_oe,
      leds => leds, stat_rx_good => good, stat_rx_bad => bad);

  urx(0) <= utx(0);
  urx(1) <= '1';
  jtdo(1) <= '0';
  tap : entity work.tap_model port map (jtck(0), jtms(0), jtdi(0), jtdo(0), tap_rises);

  -- RX driver
  drive : process
    file fin : text open read_mode is VEC_IN;
    variable l : line;
    variable delay, n : integer;
    variable b : std_logic_vector(7 downto 0);
    type buf_t is array (0 to 2047) of std_logic_vector(7 downto 0);
    variable buf : buf_t;
  begin
    wait for 2 us;
    while not endfile(fin) loop
      readline(fin, l);
      read(l, delay);
      read(l, n);
      for i in 0 to n - 1 loop
        hread(l, b);
        buf(i) := b;
      end loop;
      wait for delay * 1 us;
      wait until rising_edge(clk_rx);
      for i in 0 to 7 loop
        rx_dv <= '1';
        if i = 7 then rxd <= x"D5"; else rxd <= x"55"; end if;
        wait until rising_edge(clk_rx);
      end loop;
      for i in 0 to n - 1 loop
        rxd <= buf(i);
        wait until rising_edge(clk_rx);
      end loop;
      rx_dv <= '0';
      rxd <= x"00";
      for i in 0 to 11 loop
        wait until rising_edge(clk_rx);
      end loop;
    end loop;
    wait;
  end process;

  -- TX capture
  cap : process
    file fout : text open write_mode is CAP_OUT;
    variable l : line;
    type buf_t is array (0 to 2047) of std_logic_vector(7 downto 0);
    variable buf : buf_t;
    variable n : natural;
    variable gap : natural;
  begin
    loop
      wait until rising_edge(clk_sys);
      exit when done;
      if tx_en = '1' then
        n := 0;
        while tx_en = '1' loop
          buf(n) := txd;
          n := n + 1;
          wait until rising_edge(clk_sys);
        end loop;
        -- preamble check: 7x55 D5
        for i in 0 to 6 loop
          assert buf(i) = x"55" report "bad preamble" severity failure;
        end loop;
        assert buf(7) = x"D5" report "bad SFD" severity failure;
        assert n - 8 >= 64 report "runt frame" severity failure;
        -- IFG: tx_en must stay low for >= 12 cycles
        gap := 0;
        while tx_en = '0' and gap < 12 loop
          wait until rising_edge(clk_sys);
          gap := gap + 1;
        end loop;
        assert gap >= 12 or done report "IFG too short" severity failure;
        write(l, n - 8);
        for i in 8 to n - 1 loop
          write(l, string'(" "));
          hwrite(l, buf(i));
        end loop;
        writeline(fout, l);
        captured <= captured + 1;
      end if;
    end loop;
    wait;
  end process;

  stop : process
  begin
    wait for RUN_US * 1 us;
    report "captured " & integer'image(captured) & " frames; rx good " &
      integer'image(to_integer(good)) & " bad " & integer'image(to_integer(bad));
    assert bad = 0 report "RX CRC errors/drops" severity failure;
    assert good = 18 report "expected 18 good RX frames" severity failure;
    report "tb_supervisor_core PASSED (frame-level); run core_scenario.py check";
    done <= true;
    wait;
  end process;
end architecture;
