-- tb_host_vlan: host VLAN (key 0x0046, issue 0062) through the whole core.
--
-- Frames from a vector file go into supervisor_core's GMII RX; every GMII
-- TX frame is captured (preamble stripped) to a file. The semantic checks
-- (which frames carry which 802.1Q tag, DHCP on the VLAN, replies on the
-- request's VLAN, recovery path, drops) are in
-- tests/scenarios/tb_host_vlan.py. Here: framing (preamble, IFG, minimum
-- size: 64 bytes + FCS for a tagged frame) and the text display writes
-- (TEXT_WRITE, UDP 6508, follows the host VLAN in text_rx_tap).
-- DUT0: UART looped back, JTAG connected to a TAP model.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_host_vlan is
  generic (
    VEC_IN  : string := "host_vlan_vectors.txt";
    CAP_OUT : string := "host_vlan_capture.txt";
    RUN_US  : natural := 10000
  );
end entity;

architecture tb of tb_host_vlan is
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
  signal good, bad : unsigned(15 downto 0);
  signal tap_rises : natural;
  signal pk_tck, pk_tms, pk_tdi, pk_joe : std_logic;
  signal captured : natural := 0;
  signal text_we : std_logic;
  signal text_addr : unsigned(14 downto 0);
  signal text_data : std_logic_vector(7 downto 0);
  signal text_n : natural := 0;
  signal text_s : string(1 to 8) := (others => ' ');
begin
  clk_sys <= not clk_sys after 4 ns when not done;
  clk_rx  <= not clk_rx after 4.0016 ns when not done;   -- 200 ppm offset

  dut : entity work.supervisor_core
    generic map (CLK_HZ => 125_000_000, BUILD_ID => x"C0DE0062",
                 DHCP_FALLBACK_MS => 1, DHCP_MS_PER_S => 1, THUMB_MS_PER_S => 1)
    port map (
      clk_sys => clk_sys, clk_rx => clk_rx,
      rx_dv => rx_dv, rx_er => rx_er, rxd => rxd, tx_en => tx_en, txd => txd,
      dna => x"0123456789ABCDEF", dip => x"10", link_flags => x"03",
      vio_sense => "11", kb3v3_sense => "11",
      jtck => jtck, jtms => jtms, jtdi => jtdi, jtdo => jtdo, jtag_oe => joe,
      utx => utx, utx_oe => uoe, urx => urx,
      kio8 => "00", kio9 => "00", kio10 => kio10, kio10_oe => kio10_oe,
      pk_kio8 => open, pk_kio9 => open, pk_kio8_oe => open, pk_kio9_oe => open,
      pk_kio8_in => '1', pk_kio10 => '0', buttons => "0000",
      pk_tck => pk_tck, pk_tms => pk_tms, pk_tdi => pk_tdi, pk_jtag_oe => pk_joe, pk_tdo => '0',
      leds => open, text_we => text_we, text_addr => text_addr, text_data => text_data,
      addr_src0 => open, addr_src1 => open, ep_enable_o => open, stat_rx_good => good, stat_rx_bad => bad,
      pt_request => open, con_screen => open, con_slots => open, pwr_ctl => open, pwr_set => open,
      thumb_mem_req => open, thumb_seen => open, thumb_fresh => open, thumb_cur => open,
      thumb_quarter => open, vid_machine => open, vid_machine_ok => open, full_on => open,
      full_buf => open, full_width => open, full_height => open, rx_ps_en => open);

  urx(0) <= utx(0);
  urx(1) <= '1';
  jtdo(1) <= '0';
  tap : entity work.tap_model port map (jtck(0), jtms(0), jtdi(0), jtdo(0), tap_rises);

  -- text display writes (clk_rx domain)
  process (clk_rx)
  begin
    if rising_edge(clk_rx) then
      if text_we = '1' then
        assert text_n < 8 report "too many text writes" severity failure;
        text_s(text_n + 1) <= character'val(to_integer(unsigned(text_data)));
        text_n <= text_n + 1;
      end if;
    end if;
  end process;

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
    type buf_t is array (0 to 9015) of std_logic_vector(7 downto 0);
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
        for i in 0 to 6 loop
          assert buf(i) = x"55" report "bad preamble" severity failure;
        end loop;
        assert buf(7) = x"D5" report "bad SFD" severity failure;
        assert n - 8 >= 64 report "runt frame" severity failure;
        if buf(20) = x"81" and buf(21) = x"00" then
          -- 802.1Q: 64 bytes + FCS, so the frame is not a runt once untagged
          assert n - 8 >= 68 report "tagged frame shorter than 68 bytes" severity failure;
        end if;
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
      integer'image(to_integer(good)) & " bad " & integer'image(to_integer(bad)) &
      "; text '" & text_s(1 to text_n) & "'";
    assert bad = 0 report "RX CRC errors/drops" severity failure;
    -- untagged "AB" with key 0, tagged "CD" with key 1650; the untagged "EF"
    -- with key 1650 and the tagged "GH" with key 0 again are dropped
    assert text_n = 4 and text_s(1 to 4) = "ABCD"
      report "text writes '" & text_s(1 to text_n) & "' (want 'ABCD')" severity failure;
    report "tb_host_vlan PASSED (frame-level); run tb_host_vlan.py check";
    done <= true;
    wait;
  end process;
end architecture;
