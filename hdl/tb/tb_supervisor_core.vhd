-- tb_supervisor_core: drive Ethernet frames from a vector file into the core's
-- GMII RX, capture every GMII TX frame (preamble stripped) to a file, and
-- check FCS framing. Semantic checks: tests/core_scenario.py check.
-- DUT0: UART looped back, JTAG connected to a TAP model; both DUTs powered.
-- HDMI IN: video_timing at 27 MHz, 720 x 8 active of 858 x 12, negative
-- syncs, pixel pattern R = x, G = y, B = (7x + 31y + 5) mod 256 (raster
-- capture, issue 0023; the scenario enables capture and rebuilds frames).
-- Passthrough request (issue 0032) is looped back as shown.
-- Thumbnails (issues 0035/0038): the three frame-store ports share one
-- mem_model; the scenario forces relay streaming to the host and sends a
-- peer's picture of machine 5, checked here through the status ports.
-- Neighbour link (issue 0069): a second neighbour_link instance plays the
-- other supervisor (B = 0, so the core, B = 1, is secondary); HELLOs every
-- 1 ms (NB_HELLO_MS => 1). The heartbeat neighbour block is checked by the
-- scenario, the peer's view of the core here.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.mem_pkg.all;
use work.net_pkg.all;

entity tb_supervisor_core is
  generic (
    VEC_IN  : string := "core_vectors.txt";
    CAP_OUT : string := "core_capture.txt";
    RUN_US  : natural := 4800
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
  signal tap_rises, ktap_rises : natural;
  signal pk_tck, pk_tms, pk_tdi, pk_tdo, pk_joe, pk_jen : std_logic;
  signal pk_jtagen_seen_low : boolean := false;
  signal captured : natural := 0;
  signal pclk : std_logic := '0';
  signal vx, vy : unsigned(10 downto 0);
  signal vde, vhs, vvs : std_logic;
  signal vrgb : std_logic_vector(23 downto 0);
  signal pt_req : std_logic;
  signal pt_seen : boolean := false;
  signal full_on : std_logic;
  signal full_seen : boolean := false;
  signal mreq : mem_req_arr_t(0 to 2);
  signal mrsp : mem_rsp_arr_t(0 to 2);
  signal th_seen, th_fresh, th_cur, th_q : std_logic_vector(31 downto 0);
  signal nb_core_tx, nb_peer_tx, nb_tick : std_logic := '0';
  signal nb_peer, nb_core : nb_status_t;
begin
  clk_sys <= not clk_sys after 4 ns when not done;
  clk_rx  <= not clk_rx after 4.0016 ns when not done;   -- 200 ppm offset
  pclk    <= not pclk after 18.5 ns when not done;       -- 27.03 MHz

  vtim : entity work.video_timing
    generic map (H_ACTIVE => 720, H_FP => 16, H_SYNC => 62, H_BP => 60,
                 V_ACTIVE => 8, V_FP => 1, V_SYNC => 2, V_BP => 1, SYNC_POL => '0')
    port map (pclk, vx, vy, vde, vhs, vvs, open);
  vrgb <= std_logic_vector(vx(7 downto 0)) & std_logic_vector(vy(7 downto 0)) &
          std_logic_vector(to_unsigned((to_integer(vx) * 7 + to_integer(vy) * 31 + 5) mod 256, 8));

  dut : entity work.supervisor_core
    generic map (CLK_HZ => 125_000_000, BUILD_ID => x"C0DE0001",
                 DHCP_FALLBACK_MS => 1, DHCP_MS_PER_S => 1, THUMB_MS_PER_S => 1,
                 NB_HELLO_MS => 1, NB_LOST_MS => 3)
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
      pk_tck => pk_tck, pk_tms => pk_tms, pk_tdi => pk_tdi, pk_jtag_oe => pk_joe, pk_tdo => pk_tdo,
      pk_jtagen_o => pk_jen,
      leds => leds, text_we => open, text_addr => open, text_data => open,
      addr_src0 => open, addr_src1 => open, ep_enable_o => open, stat_rx_good => good, stat_rx_bad => bad,
      vid_present => '1', vid_locked => '1',
      vid_h_total => to_unsigned(858, 16), vid_v_total => to_unsigned(12, 16),
      vid_h_active => to_unsigned(720, 16), vid_v_active => to_unsigned(8, 16),
      vid_pixel_hz => to_unsigned(27_027_027, 32),
      vin_pclk => pclk, vin_rgb => vrgb, vin_de => vde, vin_hs => vhs, vin_vs => vvs,
      -- passthrough (0032): shown as soon as requested (no clock switch here)
      pt_request => pt_req, pt_active => pt_req,
      thumb_mem_req => mreq, thumb_mem_rsp => mrsp,
      thumb_seen => th_seen, thumb_fresh => th_fresh, thumb_cur => th_cur, thumb_quarter => th_q,
      full_on => full_on,
      nb_txd => nb_core_tx, nb_rxd => nb_peer_tx, nb_status => nb_core);

  -- the unit's other supervisor (issue 0069)
  nb_ticker : process (clk_sys)
    variable n : natural := 0;
  begin
    if rising_edge(clk_sys) then
      nb_tick <= '0';
      if n = 124_999 then n := 0; nb_tick <= '1'; else n := n + 1; end if;
    end if;
  end process;
  nb_other : entity work.neighbour_link
    generic map (HELLO_MS => 1, LOST_MS => 3)
    port map (clk => clk_sys, tick_1ms => nb_tick, dip => x"0A", dna => x"0000_0000_0000_0077",
              build_id => x"C0DE0077", boot_id => x"0000B007", txd => nb_peer_tx, rxd => nb_core_tx,
              status => nb_peer);
  mm : entity work.mem_mux_model generic map (N => 3, ADDR_BITS => 17, LATENCY => 20, STALL_EVERY => 7)
    port map (clk => clk_sys, req => mreq, rsp => mrsp);
  pt_seen <= true when pt_req = '1';
  full_seen <= true when full_on = '1';

  urx(0) <= utx(0);
  urx(1) <= '1';
  jtdo(1) <= '0';
  tap : entity work.tap_model port map (jtck(0), jtms(0), jtdi(0), jtdo(0), tap_rises);
  -- the physical keyboard's CPLD (ADR 0014); its pins are only driven while
  -- the keyboard JTAG target is enabled
  ktap : entity work.tap_model generic map (IDCODE => x"012BA043")
    port map (pk_tck, pk_tms, pk_tdi, pk_tdo, ktap_rises);
  assert pk_joe /= '0' or pk_tck /= '1' report "keyboard TCK moved while disabled" severity failure;
  pk_jtagen_seen_low <= true when pk_joe = '1' and pk_jen = '0';

  -- RX driver
  drive : process
    file fin : text open read_mode is VEC_IN;
    variable l : line;
    variable delay, n : integer;
    variable b : std_logic_vector(7 downto 0);
    type buf_t is array (0 to 9015) of std_logic_vector(7 downto 0);
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
    -- two drops: the deliberately oversize JTAG_REQ (issue 0059) and the
    -- 2214-byte relay frame (longer than a MAC slot, taken by thumb_rx_tap)
    assert bad = 2 report "RX CRC errors/drops" severity failure;
    assert good = 64 report "expected 64 good RX frames" severity failure;
    assert pk_jtagen_seen_low report "JTAGEN never driven low in key 0x0061 mode 3" severity failure;
    -- thumbnails: local machines 0 (DUT0, video target: captured) and 3
    -- (DUT1) seen; machine 5's picture from a peer stored at 1/4 scale
    assert th_seen(0) = '1' and th_seen(3) = '1' and th_seen(5) = '1'
      report "thumbnail seen bits " & to_hstring(th_seen) severity failure;
    assert th_fresh(0) = '1' and th_fresh(5) = '1' and th_q(5) = '1' and th_q(0) = '0'
      report "thumbnail fresh/quarter bits " & to_hstring(th_fresh) & " " & to_hstring(th_q) severity failure;
    -- video present, video target DUT0, auto screen: passthrough requested
    -- until the last frame forces the editable screen (key 0x0035)
    assert pt_seen report "passthrough never requested" severity failure;
    -- issue 0060: DUT1's machine 3 (no local video) relayed: 1/4 thumbnail
    -- stored, and as the video target its 1/1 pictures shown full-screen
    assert th_fresh(3) = '1' or th_q(3) = '1' report "relayed thumbnail of local machine 3 not stored" severity failure;
    assert full_seen report "full view never shown" severity failure;
    assert pt_req = '0' report "passthrough requested with a forced screen" severity failure;
    -- neighbour link (issue 0069): the other board sees the core (B = 1,
    -- its DNA and build) and is primary; the core is secondary
    assert nb_peer.present = '1' and nb_peer.role = NB_ROLE_PRIMARY and nb_peer.heard_us = '1' and
      nb_peer.peer_dip = x"10" and nb_peer.peer_dna = x"0123456789ABCDEF" and
      nb_peer.peer_build = x"C0DE0001" and nb_peer.peer_role = x"02" and nb_peer.mismatch = '0'
      report "neighbour: the other board's view of the core" severity failure;
    assert nb_peer.crc_errs = 0 and nb_peer.fmt_errs = 0 and nb_peer.uart_errs = 0 and
      nb_peer.rx_frames >= 3 report "neighbour: errors at the other board" severity failure;
    assert nb_core.role = NB_ROLE_SECONDARY and nb_core.primary = '0'
      report "neighbour: core role (status port)" severity failure;
    report "tb_supervisor_core PASSED (frame-level); run core_scenario.py check";
    done <= true;
    wait;
  end process;
end architecture;
