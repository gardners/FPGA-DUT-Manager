-- supervisor_core: vendor-independent phase-1 supervisor.
-- GMII-style byte interfaces (rx on clk_rx, tx on clk_sys); all DUT pins as
-- plain in/out/oe so the platform top owns the IO buffers.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.proto_pkg.all;
use work.net_pkg.all;

entity supervisor_core is
  generic (
    CLK_HZ   : positive := 125_000_000;
    BUILD_ID : std_logic_vector(31 downto 0) := x"00000000";
    -- DHCP timing (shortened in simulation)
    DHCP_FALLBACK_MS : natural := 0;    -- 0 = DHCP required (owner, ADR 0011)
    DHCP_MS_PER_S    : positive := 1000
  );
  port (
    clk_sys   : in  std_logic;
    clk_rx    : in  std_logic;
    -- GMII
    rx_dv, rx_er : in std_logic;
    rxd       : in  std_logic_vector(7 downto 0);
    tx_en     : out std_logic;
    txd       : out std_logic_vector(7 downto 0);
    -- identity / board
    dna       : in  std_logic_vector(63 downto 0);
    dip       : in  std_logic_vector(7 downto 0);
    link_flags: in  std_logic_vector(7 downto 0);
    -- DUT sense (already synchronised or not; synchronised here)
    vio_sense : in  std_logic_vector(1 downto 0);
    kb3v3_sense : in std_logic_vector(1 downto 0);
    -- DUT JTAG
    jtck, jtms, jtdi : out std_logic_vector(1 downto 0);
    jtdo      : in  std_logic_vector(1 downto 0);
    jtag_oe   : out std_logic_vector(1 downto 0);
    -- DUT UART
    utx       : out std_logic_vector(1 downto 0);
    utx_oe    : out std_logic_vector(1 downto 0);
    urx       : in  std_logic_vector(1 downto 0);
    -- DUT keyboard (MK-I device side)
    kio8      : in  std_logic_vector(1 downto 0);
    kio9      : in  std_logic_vector(1 downto 0);
    kio10     : out std_logic_vector(1 downto 0);
    kio10_oe  : out std_logic_vector(1 downto 0);
    -- physical keyboard (master's own, P12 X block): MK-I or MK-II, auto-
    -- detected (kbd_phys_host, issue 0009). KIO8/KIO9 are push-pull for MK-I
    -- and open drain (SDA/SCL) for MK-II: tri-state them at the top level.
    pk_kio8, pk_kio9       : out std_logic;
    pk_kio8_oe, pk_kio9_oe : out std_logic;
    pk_kio8_in             : in  std_logic;
    pk_kio10  : in  std_logic;
    -- front panel
    buttons   : in  std_logic_vector(3 downto 0);   -- 0 prev, 1 next target
    leds      : out std_logic_vector(7 downto 0);
    -- text display write port (clk_rx domain, ADR 0012)
    text_we   : out std_logic;
    text_addr : out unsigned(14 downto 0);
    text_data : out std_logic_vector(7 downto 0);
    -- address state per endpoint: 0 none, 1 DHCP, 2 fallback, 3 static
    addr_src0, addr_src1 : out std_logic_vector(7 downto 0);
    ep_enable_o : out std_logic_vector(1 downto 0);
    -- debug
    stat_rx_good, stat_rx_bad : out unsigned(15 downto 0);
    -- RGMII RX phase hunter (issue 0028): MMCM dynamic phase shift on clk_sys
    rx_ps_en    : out std_logic;
    rx_ps_done  : in  std_logic := '0';
    rx_locked   : in  std_logic := '1';
    -- HDMI IN measurement (clk_sys domain, issue 0022): heartbeat video block
    vid_present, vid_locked : in std_logic := '0';
    vid_h_total, vid_v_total, vid_h_active, vid_v_active : in unsigned(15 downto 0) := (others => '0');
    vid_pixel_hz : in unsigned(31 downto 0) := (others => '0');
    -- console screens (issue 0029): text_display's force bit in, screen and
    -- select-screen slot presence out
    text_forced : in  std_logic := '0';
    con_screen  : out unsigned(1 downto 0);
    con_slots   : out std_logic_vector(9 downto 0)
  );
end entity;

architecture rtl of supervisor_core is
  -- timers
  constant US_DIV : positive := CLK_HZ / 1_000_000;
  signal us_cnt : integer range 0 to US_DIV - 1 := 0;
  signal ms_cnt : integer range 0 to 999 := 0;
  signal tick_1us, tick_1ms : std_logic := '0';
  signal boot_cnt : unsigned(31 downto 0) := (others => '0');
  signal boot_id  : std_logic_vector(31 downto 0) := (others => '0');
  signal boot_latched : std_logic := '0';

  -- RX slots
  signal rxm_we : std_logic;
  signal rxm_wa, rxm_ra : unsigned(11 downto 0);
  signal rxm_wd, rxm_rd : std_logic_vector(7 downto 0);
  signal rx_tog, rel_tog : std_logic_vector(1 downto 0);
  signal len0, len1 : unsigned(11 downto 0);
  signal s_good, s_crc, s_drop : std_logic;
  signal good_t, bad_t : std_logic := '0';
  signal ob_good_t, ob_bad_t : std_logic;
  signal ob_g_s, ob_b_s : std_logic_vector(2 downto 0) := "000";
  signal hu_good, hu_bad, hu_rst, hu_hunting : std_logic := '0';
  signal lock_s : std_logic_vector(2 downto 0) := "000";
  signal hu_pos, hu_eye : unsigned(7 downto 0);
  signal hu_hunts : unsigned(15 downto 0);
  signal hu_badcnt : unsigned(15 downto 0) := (others => '0');
  signal good_s, bad_s : std_logic_vector(2 downto 0) := "000";
  signal cnt_good, cnt_bad : unsigned(15 downto 0) := (others => '0');

  -- TX slots
  signal txm_we : std_logic;
  signal txm_wa, txm_ra : unsigned(11 downto 0);
  signal txm_wd, txm_rd : std_logic_vector(7 downto 0);
  signal mac_start, mac_busy, mac_done : std_logic;
  signal mac_base, mac_len : unsigned(11 downto 0);

  -- dispatcher <-> builder
  signal cfg   : dut_cfg_arr_t;
  signal bcfg  : board_cfg_t;
  signal arp, icmp, ack : reply_t;
  signal jr    : reply_arr_t;
  signal jr_status : slv8_arr_t;
  signal jr_seq : u32_arr_t;
  signal arp_taken, icmp_taken, ack_taken : std_logic;
  signal jr_taken : std_logic_vector(1 downto 0);
  signal icmp_len : unsigned(6 downto 0);
  signal icmp_raddr : unsigned(6 downto 0);
  signal icmp_rdata : std_logic_vector(7 downto 0);
  signal ack_cmd, ack_key : std_logic_vector(15 downto 0);
  signal ack_status : std_logic_vector(7 downto 0);
  signal rx_rejects : u16_arr_t;
  signal arp_tpa : ip_t;

  -- keyboard
  signal kbd_udp : kbd_arr_t;
  signal kbd_strobe : std_logic_vector(1 downto 0);
  -- physical keyboard and arbitration (brief section 10)
  signal pk_keys, pk_prev : std_logic_vector(79 downto 0) := (others => '0');
  signal pk_stb, pk_present : std_logic;
  signal pk_type : std_logic_vector(1 downto 0);
  signal pk_commit : std_logic_vector(31 downto 0);
  signal pk_leds, pk_leds_o : std_logic_vector(95 downto 0);
  signal vid_ok : boolean;
  signal vid_b0, vid_b1 : std_logic;
  signal hk_sel, hk_cho, hk_can : std_logic;
  signal hk_k : unsigned(3 downto 0);
  signal m0, m1 : unsigned(4 downto 0);        -- machine numbers of DUT0/DUT1
  signal slots : std_logic_vector(9 downto 0);
  signal scr : unsigned(1 downto 0);
  signal pk_machine : unsigned(4 downto 0);
  signal pk_change : unsigned(15 downto 0) := (others => '0');
  signal hb_exp : std_logic := '0';
  signal kbd_eff : kbd_arr_t;
  signal kbd_owner, route : std_logic_vector(1 downto 0);
  signal sel_kbd, sel_vid : unsigned(3 downto 0) := (others => '0');
  signal bcfg_kt, bcfg_vt : std_logic_vector(7 downto 0) := x"FF";
  signal btn_s1, btn_s2, btn_prev : std_logic_vector(3 downto 0) := (others => '0');
  signal deb : unsigned(19 downto 0) := (others => '0');
  signal blink : unsigned(24 downto 0) := (others => '0');
  type leds_arr_t is array (0 to 1) of std_logic_vector(95 downto 0);
  signal dut_leds : leds_arr_t;
  signal kbd_leds_stb : std_logic_vector(1 downto 0);
  type u16a is array (0 to 1) of unsigned(15 downto 0);
  signal kbd_frames : u16a;

  -- UART
  signal adm_valid, adm_done, adm_ok, uwr_valid : std_logic_vector(1 downto 0);
  signal adm_offset : unsigned(31 downto 0);
  signal adm_count, adm_cmd : unsigned(15 downto 0);
  signal adm_clear : std_logic;
  signal uwr_data : std_logic_vector(7 downto 0);
  signal snap_req, snap_ack : std_logic_vector(1 downto 0);
  signal snap : snap_arr_t;
  signal hist_addr : unsigned(9 downto 0);
  signal hist_data0, hist_data1 : std_logic_vector(7 downto 0);
  signal u_rx_seq, u_tx_acc : u32_arr_t;
  signal baud : u32_arr_t;

  -- JTAG
  signal jreq_valid, jdec_valid, jvec_we, jgo, jdone, jab, jbusy, jready : std_logic_vector(1 downto 0);
  signal jreq_seq, jreq_bits, jreq_half : unsigned(31 downto 0);
  signal jreq_abort : std_logic;
  signal jdec_code0, jdec_code1 : unsigned(2 downto 0);
  signal jvec_addr : unsigned(10 downto 0);
  signal jvec_data : std_logic_vector(7 downto 0);
  signal j_tdo_addr : unsigned(9 downto 0);
  signal j_tdo0, j_tdo1 : std_logic_vector(7 downto 0);
  signal j_next, j_last, j_bits : u32_arr_t;

  -- sense / enables
  signal vio_s, kb_s, powered, out_en : std_logic_vector(1 downto 0);
  signal dstat : dut_status_arr_t;
  signal bstat : board_status_t;
  signal frames_sent : unsigned(31 downto 0);

  -- identity / DHCP (ADR 0011)
  signal id0, id1 : unsigned(4 downto 0);
  signal ep_enable : std_logic_vector(1 downto 0);
  signal ip_eff : ip_arr_t;
  signal dhcp_strobe, dhcp_taken : std_logic_vector(1 downto 0);
  signal dhcp_rx : dhcp_rx_t;
  signal dhcp_tx : dhcp_tx_arr_t;
  signal ids_prev : unsigned(9 downto 0) := (others => '1');
  signal id_restart : std_logic := '0';
begin
  ---------------------------------------------------------------- timers
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      tick_1us <= '0';
      tick_1ms <= '0';
      boot_cnt <= boot_cnt + 1;
      if us_cnt = US_DIV - 1 then
        us_cnt   <= 0;
        tick_1us <= '1';
        if ms_cnt = 999 then
          ms_cnt   <= 0;
          tick_1ms <= '1';
        else
          ms_cnt <= ms_cnt + 1;
        end if;
      else
        us_cnt <= us_cnt + 1;
      end if;
      -- boot id: DNA-derived plus the cycle count when the first frame
      -- arrives (varies with PHY link-up timing)
      if boot_latched = '0' then
        boot_id <= dna(31 downto 0) xor std_logic_vector(boot_cnt);
        if cnt_good /= 0 then
          boot_latched <= '1';
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- RX phase hunter
  obs : entity work.rx_frame_observer
    port map (clk => clk_rx, rx_dv => rx_dv, stat_good => s_good, stat_drop => s_drop,
              tog_good => ob_good_t, tog_bad => ob_bad_t);
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      ob_g_s <= ob_g_s(1 downto 0) & ob_good_t;
      ob_b_s <= ob_b_s(1 downto 0) & ob_bad_t;
      hu_good <= ob_g_s(2) xor ob_g_s(1);
      hu_bad  <= ob_b_s(2) xor ob_b_s(1);
      if hu_bad = '1' then hu_badcnt <= hu_badcnt + 1; end if;
      lock_s <= lock_s(1 downto 0) & rx_locked;
      hu_rst <= lock_s(1) and not lock_s(2);   -- MMCM (re)locked: phase = default
    end if;
  end process;
  hunter : entity work.rx_phase_hunter
    -- 2 frames per position, up to 10 s each: before DHCP the board only
    -- hears LAN background broadcasts (a few per second). Short timeouts
    -- scored quiet positions inside the eye as fails and split it (hardware,
    -- issue 0028); a position now fails on timeout only if truly silent.
    generic map (FRAMES_PER_POS => 2, TIMEOUT_CYC => 10 * CLK_HZ)
    port map (clk => clk_sys, rst => hu_rst, ev_good => hu_good, ev_bad => hu_bad,
              ps_en => rx_ps_en, ps_inc => open, ps_done => rx_ps_done,
              position => hu_pos, eye_width => hu_eye, hunting => hu_hunting, hunts => hu_hunts);

  ---------------------------------------------------------------- MAC RX
  mrx : entity work.eth_mac_rx
    port map (clk_rx, rx_dv, rx_er, rxd, rxm_we, rxm_wa, rxm_wd,
              rx_tog, rel_tog, len0, len1, s_good, s_crc, s_drop);
  rxmem : entity work.dpram generic map (12, 8)
    port map (clk_rx, rxm_we, rxm_wa, rxm_wd, clk_sys, rxm_ra, rxm_rd);

  -- statistics across the clock domain via toggles
  process (clk_rx)
  begin
    if rising_edge(clk_rx) then
      if s_good = '1' then good_t <= not good_t; end if;
      if s_crc = '1' or s_drop = '1' then bad_t <= not bad_t; end if;
    end if;
  end process;
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      good_s <= good_s(1 downto 0) & good_t;
      bad_s  <= bad_s(1 downto 0) & bad_t;
      if good_s(2) /= good_s(1) then cnt_good <= cnt_good + 1; end if;
      if bad_s(2) /= bad_s(1) then cnt_bad <= cnt_bad + 1; end if;
    end if;
  end process;
  stat_rx_good <= cnt_good;
  stat_rx_bad  <= cnt_bad;

  ---------------------------------------------------------------- dispatch
  nrx : entity work.net_rx
    port map (
      clk => clk_sys, dut_id0 => id0, dut_id1 => id1, ep_enable => ep_enable,
      ip_eff => ip_eff, dna => dna,
      rx_toggle => rx_tog, rel_toggle => rel_tog, len0 => len0, len1 => len1,
      mem_addr => rxm_ra, mem_data => rxm_rd,
      cfg => cfg, bcfg => bcfg, kbd_udp => kbd_udp, kbd_strobe => kbd_strobe,
      adm_valid => adm_valid, adm_offset => adm_offset, adm_count => adm_count,
      adm_clear => adm_clear, adm_cmd_id => adm_cmd, adm_done => adm_done,
      adm_ok => adm_ok, uwr_valid => uwr_valid, uwr_data => uwr_data,
      jreq_valid => jreq_valid, jreq_seq => jreq_seq, jreq_bits => jreq_bits,
      jreq_half => jreq_half, jreq_abort => jreq_abort, jdec_valid => jdec_valid,
      jdec_code0 => jdec_code0, jdec_code1 => jdec_code1, jvec_we => jvec_we,
      jvec_addr => jvec_addr, jvec_data => jvec_data, jgo => jgo,
      jdone => jdone, jaborted => jab,
      arp => arp, arp_tpa_o => arp_tpa, arp_taken => arp_taken,
      icmp => icmp, icmp_len => icmp_len, icmp_raddr => icmp_raddr,
      icmp_rdata => icmp_rdata, icmp_taken => icmp_taken,
      ack => ack, ack_cmd => ack_cmd, ack_key => ack_key, ack_status => ack_status,
      ack_taken => ack_taken, jr => jr, jr_status => jr_status, jr_seq => jr_seq,
      jr_taken => jr_taken, dhcp_strobe => dhcp_strobe, dhcp_rx => dhcp_rx,
      rx_rejects => rx_rejects);

  ---------------------------------------------------------------- text tap
  ttap : entity work.text_rx_tap
    port map (clk => clk_rx, rx_dv => rx_dv, rxd => rxd,
              mac0 => cfg(0).mac, mac1 => cfg(1).mac,
              wr_en => text_we, wr_addr => text_addr, wr_data => text_data,
              frames => open);
  addr_src0   <= dstat(0).addr_src;
  addr_src1   <= dstat(1).addr_src;
  ep_enable_o <= ep_enable;

  ---------------------------------------------------------------- identity
  -- DUT IDs 0x0n (P12 half) and 0x1m (P13 half): the halves cannot collide
  -- (issue 0026, amends ADR 0011)
  id0 <= unsigned('0' & dip(3 downto 0));
  id1 <= unsigned('1' & dip(7 downto 4));
  ep_enable <= "11";
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      id_restart <= '0';
      if ids_prev /= (id1 & id0) then
        ids_prev   <= id1 & id0;
        id_restart <= '1';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- builder
  ntx : entity work.net_tx
    port map (
      clk => clk_sys, tick_1ms => tick_1ms, cfg => cfg, bcfg => bcfg,
      bstat => bstat, dstat => dstat, hb_expedite => hb_exp,
      ip_eff => ip_eff, ep_enable => ep_enable, dhcp => dhcp_tx, dhcp_taken => dhcp_taken,
      arp => arp, arp_taken => arp_taken,
      icmp => icmp, icmp_len => icmp_len, icmp_raddr => icmp_raddr,
      icmp_rdata => icmp_rdata, icmp_taken => icmp_taken,
      ack => ack, ack_cmd => ack_cmd, ack_key => ack_key, ack_status => ack_status,
      ack_taken => ack_taken, jr => jr, jr_status => jr_status, jr_seq => jr_seq,
      jr_taken => jr_taken, j_next_seq => j_next, j_bits => j_bits,
      j_tdo_addr => j_tdo_addr, j_tdo_data0 => j_tdo0, j_tdo_data1 => j_tdo1,
      snap_req => snap_req, snap_ack => snap_ack, snap => snap, baud_inc => baud,
      boot_id => boot_id, hist_addr => hist_addr, hist_data0 => hist_data0,
      hist_data1 => hist_data1,
      mac_start => mac_start, mac_base => mac_base, mac_len => mac_len,
      mac_busy => mac_busy, mem_we => txm_we, mem_addr => txm_wa,
      mem_data => txm_wd, frames_sent => frames_sent);

  txmem : entity work.dpram generic map (12, 8)
    port map (clk_sys, txm_we, txm_wa, txm_wd, clk_sys, txm_ra, txm_rd);
  mtx : entity work.eth_mac_tx
    port map (clk_sys, mac_start, mac_base, mac_len, mac_busy, mac_done,
              txm_ra, txm_rd, tx_en, txd);

  ---------------------------------------------------------------- per DUT
  g_dut : for i in 0 to 1 generate
    signal jcode : unsigned(2 downto 0);
    signal tdo_d : std_logic_vector(7 downto 0);
    signal hd    : std_logic_vector(7 downto 0);
  begin
    sv : entity work.sync_bit port map (clk_sys, vio_sense(i), vio_s(i));
    sk : entity work.sync_bit port map (clk_sys, kb3v3_sense(i), kb_s(i));
    -- DUT powered: JB1 VIO or the keyboard cable's 3.3 V (both the MEGA65's
    -- 3.3 V rail). The bench JTAG strip skips JB1's VIO row (ADR 0008
    -- amendment 2), so the keyboard cable alone must enable the outputs.
    powered(i) <= vio_s(i) or kb_s(i);
    -- output policy: 0 auto (sense), 1 force on, 2 force off
    out_en(i) <= '1' when cfg(i).out_policy = x"01" else
                 '0' when cfg(i).out_policy = x"02" else
                 powered(i);
    baud(i) <= cfg(i).baud_inc;

    dc : block
      signal bound, fb : std_logic;
      signal lease : ip_t;
      signal st3 : unsigned(2 downto 0);
      signal id : unsigned(4 downto 0);
    begin
      id <= id0 when i = 0 else id1;
      cl : entity work.dhcp_client
        generic map (FALLBACK_MS => DHCP_FALLBACK_MS, MS_PER_S => DHCP_MS_PER_S)
        port map (
          clk => clk_sys, tick_1ms => tick_1ms,
          enable => cfg(i).dhcp_en and ep_enable(i), restart => id_restart,
          xid_base => x"4D3635" & "000" & std_logic_vector(id),
          rx_strobe => dhcp_strobe(i), rx_type => dhcp_rx.typ, rx_xid => dhcp_rx.xid,
          rx_yiaddr => dhcp_rx.yiaddr, rx_server => dhcp_rx.server,
          rx_lease => dhcp_rx.lease, rx_t1 => dhcp_rx.t1,
          tx_req => dhcp_tx(i).req, tx_taken => dhcp_taken(i), tx_type => dhcp_tx(i).typ,
          tx_xid => dhcp_tx(i).xid, tx_ciaddr => dhcp_tx(i).ciaddr,
          tx_reqip => dhcp_tx(i).reqip, tx_server => dhcp_tx(i).server,
          bound => bound, lease_ip => lease, fallback => fb, state_o => st3);
      -- effective address: static, DHCP lease, fallback after timeout, else none
      ip_eff(i) <= cfg(i).ip  when cfg(i).dhcp_en = '0' else
                   lease      when bound = '1' else
                   cfg(i).ip  when fb = '1' else
                   x"00000000";
      dstat(i).addr_src <= x"03" when cfg(i).dhcp_en = '0' else
                           x"01" when bound = '1' else
                           x"02" when fb = '1' else x"00";
      dstat(i).dut_id <= "000" & std_logic_vector(id);
    end block;

    ub : entity work.uart_bridge
      port map (
        clk => clk_sys, tick_1us => tick_1us, baud_inc => cfg(i).baud_inc,
        out_enable => out_en(i), snap_enable => cfg(i).uart_snap_en,
        fast_mode => cfg(i).uart_fast, snap_period_us => cfg(i).uart_period,
        txd => utx(i), txd_oe => utx_oe(i), rxd => urx(i),
        adm_valid => adm_valid(i), adm_offset => adm_offset, adm_count => adm_count,
        adm_clear => adm_clear, adm_cmd_id => adm_cmd, adm_done => adm_done(i),
        adm_ok => adm_ok(i), wr_valid => uwr_valid(i), wr_data => uwr_data,
        snap_req => snap_req(i), snap_ack => snap_ack(i), hist_addr => hist_addr,
        hist_data => hd,
        snap_rx_seq => snap(i).rx_seq, snap_tx_accepted => snap(i).tx_accepted,
        snap_tx_emitted => snap(i).tx_emitted, snap_tx_free => snap(i).tx_free,
        snap_framing_errs => snap(i).framing_errs, snap_rx_overflows => snap(i).rx_overflows,
        snap_tx_rejects => snap(i).tx_rejects, snap_clear_gen => snap(i).clear_gen,
        snap_rx_seq_clear => snap(i).rx_seq_clear, snap_seq => snap(i).seq,
        rx_seq_o => u_rx_seq(i), tx_accepted_o => u_tx_acc(i));

    je : entity work.jtag_engine
      port map (
        clk => clk_sys, powered => powered(i),
        req_valid => jreq_valid(i), req_seq => jreq_seq, req_bits => jreq_bits,
        req_half => jreq_half, req_abort => jreq_abort,
        dec_valid => jdec_valid(i), dec_code => jcode,
        vec_we => jvec_we(i), vec_addr => jvec_addr, vec_data => jvec_data,
        go => jgo(i), tdo_addr => j_tdo_addr, tdo_data => tdo_d,
        busy => jbusy(i), result_ready => jready(i), done_strobe => jdone(i),
        aborted => jab(i), next_seq => j_next(i), last_seq => j_last(i),
        last_bits => j_bits(i),
        tck => jtck(i), tms => jtms(i), tdi => jtdi(i), jtag_oe => jtag_oe(i),
        tdo => jtdo(i));

    kd : entity work.kbd_mk1_device
      generic map (SYNC_CYCLES => (CLK_HZ / 1000) * 61 / 10000)
      port map (
        clk => clk_sys, keys_pressed => kbd_eff(i),
        kio8_in => kio8(i), kio9_in => kio9(i), kio10_out => kio10(i),
        leds => dut_leds(i), leds_strobe => kbd_leds_stb(i),
        frame_count => kbd_frames(i));
    kio10_oe(i) <= out_en(i);

    -- status for heartbeat (phase 1: UDP always owns the keyboard)
    dstat(i).target_flags  <= "0000" & '1' & out_en(i) & vio_s(i) & kb_s(i);
    route(i) <= pk_present when sel_kbd = i else '0';
    arb : entity work.kbd_arbiter
      port map (clk => clk_sys, udp_strobe => kbd_strobe(i), udp_keys => kbd_udp(i),
                phys_route => route(i),
                phys_keys => pk_keys, policy => cfg(i).kbd_policy,
                override => cfg(i).kbd_override, effective => kbd_eff(i),
                udp_stored => open, owner_phys => kbd_owner(i));
    dstat(i).kbd_owner     <= "0000000" & kbd_owner(i);
    dstat(i).kbd_eff       <= kbd_eff(i);
    dstat(i).kbd_udp       <= kbd_udp(i);
    dstat(i).dut_leds      <= dut_leds(i);
    dstat(i).jtag_status   <= "0000" & not powered(i) & jab(i) & jready(i) & jbusy(i);
    dstat(i).jtag_next_seq <= j_next(i);
    dstat(i).uart_rx_seq   <= u_rx_seq(i);
    dstat(i).uart_tx_acc   <= u_tx_acc(i);
    dstat(i).rx_rejects    <= rx_rejects(i);

    g0 : if i = 0 generate
      jdec_code0 <= jcode; j_tdo0 <= tdo_d; hist_data0 <= hd;
    end generate;
    g1 : if i = 1 generate
      jdec_code1 <= jcode; j_tdo1 <= tdo_d; hist_data1 <= hd;
    end generate;
  end generate;

  bstat.boot_id     <= boot_id;
  bstat.build_id    <= BUILD_ID;
  bstat.dna         <= dna;
  bstat.topo_index  <= x"FF";
  bstat.topo_count  <= x"00";
  bstat.dip         <= dip;
  bstat.link_flags  <= link_flags(7) & (not ep_enable(1)) & link_flags(5 downto 0);
  -- capabilities (ADR 0005 s3): b0 uart, b1 jtag, b2 kbd device, b3 physical
  -- keyboard host, b4 hdmi capture (set once raster capture exists, 0023)
  bstat.caps        <= x"0000000F";
  bstat.selected    <= std_logic_vector(sel_vid) & std_logic_vector(sel_kbd);
  bstat.kbd_phys    <= pk_keys;
  bstat.phys_change <= pk_change;
  bstat.phys_type   <= "000000" & pk_type;     -- 0 none, 1 MK-I, 2 MK-II
  bstat.rx_phase    <= std_logic_vector(hu_pos);
  bstat.rx_eye      <= std_logic_vector(hu_eye);
  bstat.rx_hunts    <= hu_hunts;
  bstat.rx_bad      <= hu_badcnt;
  bstat.rx_flags    <= "000000" & lock_s(2) & hu_hunting;
  -- b0 TMDS clock present = dvi2rgb's MMCM locked to it (its output free-runs
  -- otherwise, so a measured frequency alone means nothing); b1 decoding =
  -- also active video measured. Values read 0 while unlocked. b2 per DUT.
  vid_ok  <= vid_locked = '1' and vid_present = '1';
  vid_b0  <= '1' when vid_ok else '0';
  vid_b1  <= '1' when vid_ok and vid_h_active /= 0 and vid_v_active /= 0 else '0';
  bstat.vid_flags   <= "000000" & vid_b1 & vid_b0;
  bstat.vid_h_total  <= vid_h_total  when vid_ok else (others => '0');
  bstat.vid_v_total  <= vid_v_total  when vid_ok else (others => '0');
  bstat.vid_h_active <= vid_h_active when vid_ok else (others => '0');
  bstat.vid_v_active <= vid_v_active when vid_ok else (others => '0');
  bstat.vid_pixel_hz <= vid_pixel_hz when vid_ok else (others => '0');

  ---------------------------------------------------------------- physical keyboard
  -- power LED colour = machine number k = 2 * DUT-ID nibble + half (P12 0,
  -- P13 1); gentle red pulse when the selected DUT is not powered (owner)
  pk_machine <= unsigned((id0(3 downto 0) & '0') + 0) when sel_kbd(0) = '0' else
                unsigned((id1(3 downto 0) & '1') + 0);
  pkl : entity work.kbd_led_status
    port map (clk => clk_sys, dut_leds => dut_leds(to_integer(sel_kbd(0 downto 0))),
              connected => powered(to_integer(sel_kbd(0 downto 0))),
              machine => pk_machine, leds => pk_leds);
  pk_leds_o <= dut_leds(to_integer(sel_kbd(0 downto 0))) when bcfg.pk_led_mode = x"01" else
               bcfg.pk_led_host when bcfg.pk_led_mode = x"02" else
               pk_leds;
  pkh : entity work.kbd_phys_host
    generic map (MK1_HALF_CYCLES => CLK_HZ / 625_000,          -- 1.6 us
                 MK2_QUARTER_CYCLES => CLK_HZ / 1_000_000,     -- 250 kHz SCL
                 MK2_DETECT_CYCLES => CLK_HZ / 8_100)          -- 123 us
    port map (clk => clk_sys, kio8_o => pk_kio8, kio8_oe => pk_kio8_oe,
              kio8_i => pk_kio8_in, kio9_o => pk_kio9, kio9_oe => pk_kio9_oe,
              kio10 => pk_kio10,
              -- K_PK_LED_MODE: 0 status (machine colour), 1 DUT's own, 2 host
              leds => pk_leds_o,
              pressed => pk_keys, strobe => pk_stb, kbd_type => pk_type,
              kbd_commit => pk_commit);
  pk_present <= '1' when pk_type /= "00" else '0';

  -- KVM hotkey (issue 0029): both SHIFTs >= 1 s, tap MEGA, then 1..9,0
  hk : entity work.kvm_hotkey
    port map (clk => clk_sys, tick_1ms => tick_1ms, keys => pk_keys,
              selecting => hk_sel, choose => hk_cho, k => hk_k, cancel => hk_can);
  m0 <= unsigned(id0(3 downto 0) & '0');
  m1 <= unsigned(id1(3 downto 0) & '1');
  g_slots : for k in 0 to 9 generate
    slots(k) <= '1' when m0 = k or m1 = k else '0';
  end generate;
  con_slots <= slots;
  -- console screen: forced by management, else select while choosing,
  -- editable when the host forced text or video is present, else no video
  scr <= "00" when bcfg.con_screen = x"01" else
         "01" when bcfg.con_screen = x"02" else
         "10" when bcfg.con_screen = x"03" else
         "10" when hk_sel = '1' else
         "00" when text_forced = '1' or vid_b1 = '1' else
         "01";
  con_screen <= scr;
  bstat.con_shown <= "000000" & std_logic_vector(scr);

  -- selection: management writes or front-panel buttons (last writer wins);
  -- phase 1 has no chain, so targets are this board's two DUTs (0, 1).
  -- Expedited heartbeat on every physical bitmap change (brief section 13).
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      hb_exp <= '0';
      blink  <= blink + 1;
      if pk_stb = '1' then
        pk_prev <= pk_keys;
        if pk_keys /= pk_prev then
          pk_change <= pk_change + 1;
          hb_exp    <= '1';
        end if;
      end if;
      bcfg_kt <= bcfg.kbd_target;
      bcfg_vt <= bcfg.vid_target;
      if bcfg.kbd_target /= bcfg_kt then
        sel_kbd <= unsigned(bcfg.kbd_target(3 downto 0));
        if bcfg.coupled = '1' then sel_vid <= unsigned(bcfg.kbd_target(3 downto 0)); end if;
      end if;
      if bcfg.vid_target /= bcfg_vt then
        sel_vid <= unsigned(bcfg.vid_target(3 downto 0));
      end if;
      -- hotkey choice: keyboard + video to the chosen machine if it is here
      if hk_cho = '1' then
        if hk_k = m0 then
          sel_kbd <= (others => '0'); sel_vid <= (others => '0');
        elsif hk_k = m1 then
          sel_kbd <= to_unsigned(1, 4); sel_vid <= to_unsigned(1, 4);
        end if;
      end if;
      -- buttons: sample every ~8 ms (debounce), act on press
      deb <= deb + 1;
      if deb = 0 then
        btn_s1 <= buttons;
        btn_s2 <= btn_s1;
        btn_prev <= btn_s2;
        if btn_s2(1) = '1' and btn_prev(1) = '0' then
          -- next (wraps within this board's two targets until the chain exists)
          if sel_kbd < 1 then
            sel_kbd <= sel_kbd + 1; sel_vid <= sel_kbd + 1;
          else
            sel_kbd <= (others => '0'); sel_vid <= (others => '0');
          end if;
        elsif btn_s2(0) = '1' and btn_prev(0) = '0' then
          if sel_kbd > 0 then
            sel_kbd <= sel_kbd - 1; sel_vid <= sel_kbd - 1;
          else
            sel_kbd <= to_unsigned(1, 4); sel_vid <= to_unsigned(1, 4);
          end if;
        end if;
      end if;
    end if;
  end process;

  -- front panel: LED0 heartbeat-ish activity, LED1/2 DUT powered, LED7 rx
  -- green LEDs: selected target one-hot; steady when keyboard and video
  -- selections agree, blinking (keyboard target) when they differ (brief)
  process (sel_kbd, sel_vid, blink)
  begin
    leds <= (others => '0');
    leds(to_integer(sel_vid(2 downto 0))) <= '1';
    if sel_kbd /= sel_vid then
      leds(to_integer(sel_kbd(2 downto 0))) <= blink(blink'high);
    end if;
  end process;
end architecture;
