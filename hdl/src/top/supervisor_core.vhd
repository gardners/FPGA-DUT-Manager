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
use work.raster_pkg.all;
use work.mem_pkg.all;
use work.thumb_pkg.all;

entity supervisor_core is
  generic (
    CLK_HZ   : positive := 125_000_000;
    BUILD_ID : std_logic_vector(31 downto 0) := x"00000000";
    -- DHCP timing (shortened in simulation)
    DHCP_FALLBACK_MS : natural := 0;    -- 0 = DHCP required (owner, ADR 0011)
    DHCP_MS_PER_S    : positive := 1000;
    THUMB_MS_PER_S   : positive := 1000;  -- thumbnail relay timers (shortened in simulation)
    THUMB_CROP_W     : positive := 640;   -- thumbnail source crop (centre of the picture)
    THUMB_CROP_H     : positive := 400;
    -- neighbour link (issue 0069): HELLO period and presence timeout in
    -- tick_1ms units (shortened in simulation)
    NB_HELLO_MS      : positive := 100;
    NB_LOST_MS       : positive := 350
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
    utx_low   : out std_logic_vector(1 downto 0);   -- drive TXD low when not oe (0067)
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
    -- physical keyboard CPLD JTAG (J5 pins 3-7, ADR 0014): TCK/TMS/TDI and
    -- JTAGEN (driven '1') are tri-stated unless pk_jtag_oe
    pk_tck, pk_tms, pk_tdi : out std_logic;
    pk_jtag_oe : out std_logic;
    pk_jtagen_o: out std_logic := '1';   -- level for JTAGEN while pk_jtag_oe
    pk_tdo    : in  std_logic := '0';
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
    -- link speed / gigabit renegotiation (issue 0070, clk_sys): measured
    -- speed 0 none, 1 = 10, 2 = 100, 3 = 1000; PHY held in reset; attempts
    link_speed  : in  std_logic_vector(1 downto 0) := "11";
    link_hold   : in  std_logic := '0';
    link_reneg  : in  unsigned(7 downto 0) := (others => '0');
    -- HDMI IN measurement (clk_sys domain, issue 0022): heartbeat video block
    vid_present, vid_locked : in std_logic := '0';
    vid_h_total, vid_v_total, vid_h_active, vid_v_active : in unsigned(15 downto 0) := (others => '0');
    vid_pixel_hz : in unsigned(31 downto 0) := (others => '0');
    -- HDMI IN source sends HDMI (preambles/guard bands) / data islands
    -- (InfoFrames, audio), seen in the last two frames (issue 0040)
    vid_hdmi, vid_islands : in std_logic := '0';
    -- HDMI IN pixel stream (pixel clock domain) for raster capture (issue 0023)
    vin_pclk  : in  std_logic := '0';
    vin_rgb   : in  std_logic_vector(23 downto 0) := (others => '0');
    vin_de, vin_hs, vin_vs : in std_logic := '0';
    -- console screens (issue 0029): text_display's force bit in, screen and
    -- select-screen slot presence out
    text_forced : in  std_logic := '0';
    con_screen  : out unsigned(1 downto 0);
    con_slots   : out std_logic_vector(9 downto 0);
    -- HDMI OUT passthrough (issue 0032): wanted (registered) / shown (from
    -- the platform's switch sequencer, clk_sys domain)
    pt_request  : out std_logic;
    pt_active   : in  std_logic := '0';
    -- DDR3 frame store status (issue 0034, clk_sys): heartbeat memory block
    mem_status  : in  mem_status_t := MEM_STATUS_NONE;
    -- shield I2C status (issue 0049, shield_io, clk_sys): heartbeat shield
    -- block; power CTRL state set by the host (key 0x0062) for shield_io
    shd_status  : in  shd_status_t := SHD_STATUS_NONE;
    pwr_ctl     : out std_logic_vector(7 downto 0);
    pwr_set     : out std_logic;
    -- thumbnails (issues 0035/0038): frame-store ports (mem_pkg, clk_sys):
    -- 0 local capture writer, 1 relay receive writer, 2 relay sender reader
    thumb_mem_req : out mem_req_arr_t(0 to 2);
    thumb_mem_rsp : in  mem_rsp_arr_t(0 to 2) := (others => MEM_RSP_IDLE);
    -- per-machine status for the mosaic (issue 0036), bit m = machine m,
    -- clk_sys: seen in the last 3 s / complete picture in the last 2 s /
    -- buffer shown (thumb_addr buf) / its scale (0: 320x200, 1: 160x100)
    thumb_seen, thumb_fresh, thumb_cur, thumb_quarter : out std_logic_vector(31 downto 0);
    -- machine number of the video target when it is one of this board's
    -- DUTs (HDMI OUT SPD InfoFrame, issue 0037)
    vid_machine    : out unsigned(4 downto 0);
    vid_machine_ok : out std_logic;
    -- full-resolution relayed picture of the video target when it has no
    -- local video (issue 0060): show it (full_on), from DDR3 buffer
    -- full_buf (mem_pkg full_addr), full_width x full_height; full_shown =
    -- the buffer the display latched at its last vertical blank
    full_on     : out std_logic;
    full_buf    : out unsigned(1 downto 0);
    full_width  : out unsigned(10 downto 0);
    full_height : out unsigned(9 downto 0);
    full_shown  : in  unsigned(1 downto 0) := "00";
    full_frame  : in  std_logic := '0';          -- full_display latched a frame (clk_sys pulse)
    -- neighbour link to the other supervisor of the unit (issue 0069, ADR
    -- 0007 point 2): UART TX (idles high), RX (pulled up at the pin, '1' =
    -- idle when unconnected); link state, role and peer for the rest of
    -- the design (nb_status.primary: hook for issue 0044)
    nb_txd      : out std_logic;
    nb_rxd      : in  std_logic := '1';
    nb_status   : out nb_status_t
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
  signal nb_st : nb_status_t;

  -- RX slots
  signal rxm_we : std_logic;
  signal rxm_wa, rxm_ra : unsigned(11 downto 0);
  signal rxm_wd, rxm_rd : std_logic_vector(7 downto 0);
  signal rx_tog, rel_tog : std_logic_vector(1 downto 0);
  signal len0, len1 : unsigned(11 downto 0);
  signal tag0, tag1 : unsigned(12 downto 0);
  signal mac_vid    : unsigned(11 downto 0);
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
  signal txm_wa, txm_ra : unsigned(13 downto 0);      -- two 8 KiB slots (jumbo raster, thumbnails)
  signal txm_wd, txm_rd : std_logic_vector(7 downto 0);
  signal mac_start, mac_busy, mac_done : std_logic;
  signal mac_base : unsigned(13 downto 0);
  signal mac_len  : unsigned(12 downto 0);

  -- raster capture (issue 0023)
  signal cap_on : std_logic := '0';
  signal rast_valid, rast_pop, vid_ok_l : std_logic;
  signal cap_dut : integer range 0 to 1;
  signal rast_desc : rast_desc_t;
  signal rast_raddr : unsigned(15 downto 0);
  signal rast_rdata : std_logic_vector(23 downto 0);
  signal hist_latch : std_logic_vector(1 downto 0);

  -- thumbnails (issues 0035, 0038)
  signal th_cur, th_seen, th_fresh, th_q : std_logic_vector(31 downto 0);
  signal th_nseen : unsigned(5 downto 0);
  signal tc_en : std_logic := '0';
  signal tc_m : unsigned(4 downto 0) := (others => '0');
  signal tc_done, tc_buf, tc_q : std_logic;
  signal tc_dm : unsigned(4 downto 0);
  signal tc_rows : unsigned(7 downto 0);
  signal te_q : std_logic;
  signal te_div : unsigned(3 downto 0);
  signal tl_v, tl_b : std_logic;
  signal tl_m : unsigned(4 downto 0);
  signal tf_valid, tf_pop : std_logic;
  signal tf_dout : std_logic_vector(35 downto 0);
  signal trq_stb : std_logic;
  signal trq_mac : std_logic_vector(47 downto 0);
  signal trq_sc, trq_dv, trq_fl, trq_tg : std_logic_vector(7 downto 0);
  signal tq_fl, tq_tg : std_logic_vector(7 downto 0);
  -- HDMI IN owner / relayed local video / full view (issue 0060)
  signal own : std_logic_vector(1 downto 0) := "11";   -- DUT i owns the HDMI IN
  signal sel_own : std_logic := '1';                  -- the video target has local video
  signal vid_sel : std_logic := '0';                  -- ... and it is decoded
  signal full_want, full_fresh, full_ev : std_logic := '0';
  signal full_m : unsigned(4 downto 0) := (others => '0');
  signal full_age : unsigned(10 downto 0) := (others => '1');
  signal tr_ev, tr_buf, tr_q, tr_sev : std_logic;
  signal tr_m, tr_sm : unsigned(4 downto 0);
  signal tp_valid, tp_taken, tq_valid, tq_taken : std_logic;
  signal tp : thumb_pkt_t;
  signal tp_raddr : unsigned(12 downto 0);
  signal tp_rdata : std_logic_vector(7 downto 0);
  signal tq_sc, tq_dv : std_logic_vector(7 downto 0);
  signal selecting : std_logic := '0';
  -- relay counters (issue 0061, heartbeat relay block)
  signal rl_req_sent, rl_req_full, rl_swaps : unsigned(15 downto 0) := (others => '0');
  signal rl_shown_d : unsigned(1 downto 0) := "00";
  signal rl_upd : std_logic := '0';     -- live view: new lines since the last displayed frame
  constant RL_FIFO_AW : natural := 14;  -- relay receive FIFO: 2**14 entries
  signal rl_win : std_logic := '0';     -- 1 s windows for the FIFO peaks
  signal rl_wms : unsigned(9 downto 0) := (others => '0');
  signal rl_lv, rl_lns, th_streaming : std_logic;
  signal rl_lm : unsigned(4 downto 0);
  signal rl_lsc : std_logic_vector(7 downto 0);

  -- dispatcher <-> builder
  signal cfg   : dut_cfg_arr_t;
  signal bcfg  : board_cfg_t;
  signal arp, icmp, ack : reply_t;
  signal jr    : jreply_arr_t;
  signal jr_status : jslv8_arr_t;
  signal jr_seq : ju32_arr_t;
  signal arp_taken, icmp_taken, ack_taken : std_logic;
  signal jr_taken : std_logic_vector(2 downto 0);
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
  signal pt_req_r : std_logic := '0';
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
  -- JTAG targets 0/1 = DUTs, 2 = physical keyboard CPLD (net_pkg JT_KBD)
  signal jreq_valid, jdec_valid, jvec_we, jgo, jdone, jab, jbusy, jready : std_logic_vector(2 downto 0);
  signal jreq_seq, jreq_bits, jreq_half : unsigned(31 downto 0);
  signal jreq_abort : std_logic;
  signal jdec_code0, jdec_code1, jdec_code2 : unsigned(2 downto 0);
  signal jvec_addr : unsigned(10 downto 0);
  signal jvec_data : std_logic_vector(7 downto 0);
  signal j_tdo_addr : unsigned(9 downto 0);
  signal j_tdo0, j_tdo1, j_tdo2 : std_logic_vector(7 downto 0);
  signal j_next, j_last, j_bits : ju32_arr_t;
  -- keyboard CPLD JTAG lease (ms): a detected keyboard or a transaction
  -- keeps the pins driven this long (flashing stops the keyboard answering)
  constant KJ_LEASE_MS : natural := 10_000;
  signal kj_lease : integer range 0 to KJ_LEASE_MS := 0;
  signal kj_pow   : std_logic := '0';
  -- keyboard JTAG quiet (key 0x0063, issue 0054): guard before the first
  -- and after the last TCK edge, and a start timeout should the keyboard
  -- host never report paused
  constant KQ_GUARD   : natural := CLK_HZ / 250_000;     -- 4 us
  constant KQ_TIMEOUT : natural := CLK_HZ / 250;         -- 4 ms
  signal kq_post  : integer range 0 to KQ_GUARD := 0;
  signal kq_pre   : integer range 0 to KQ_GUARD := 0;
  signal kq_to    : integer range 0 to KQ_TIMEOUT := 0;
  signal kq_pause, kq_stop, kq_ok, pk_paused : std_logic := '0';
  signal tdo_vote : unsigned(1 downto 0);

  -- sense / enables
  signal vio_s, kb_s, powered, out_en : std_logic_vector(1 downto 0);
  signal pwr_eff, jpow, phold : std_logic_vector(1 downto 0);
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
  -- host VLAN change (issue 0062): DHCP starts over on the new VLAN 1..2
  -- ms after the change, once the MGMT ack has gone out with the old address
  signal hv_prev    : unsigned(11 downto 0) := (others => '0');
  signal hv_wait    : unsigned(2 downto 0) := (others => '0');
  signal dhcp_restart : std_logic := '0';
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
      -- held while the RX MMCM is unlocked (its phase restarts at the
      -- default when it relocks), while the link is not at gigabit and while
      -- the PHY is held in reset for renegotiation (issue 0070): no hunting
      -- on a clock that is absent or 25/2.5 MHz
      hu_rst <= not (lock_s(1) and lock_s(2)) or link_hold or
                (link_speed(1) nand link_speed(0));
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
              rx_tog, rel_tog, len0, len1, tag0, tag1, s_good, s_crc, s_drop);
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
      tag0 => tag0, tag1 => tag1,
      mem_addr => rxm_ra, mem_data => rxm_rd,
      cfg => cfg, bcfg => bcfg, kbd_udp => kbd_udp, kbd_strobe => kbd_strobe,
      adm_valid => adm_valid, adm_offset => adm_offset, adm_count => adm_count,
      adm_clear => adm_clear, adm_cmd_id => adm_cmd, adm_done => adm_done,
      adm_ok => adm_ok, uwr_valid => uwr_valid, uwr_data => uwr_data,
      jreq_valid => jreq_valid, jreq_seq => jreq_seq, jreq_bits => jreq_bits,
      jreq_half => jreq_half, jreq_abort => jreq_abort, jdec_valid => jdec_valid,
      jdec_code0 => jdec_code0, jdec_code1 => jdec_code1, jdec_code2 => jdec_code2, jvec_we => jvec_we,
      jvec_addr => jvec_addr, jvec_data => jvec_data, jgo => jgo,
      jdone => jdone, jaborted => jab,
      arp => arp, arp_tpa_o => arp_tpa, arp_taken => arp_taken,
      icmp => icmp, icmp_len => icmp_len, icmp_raddr => icmp_raddr,
      icmp_rdata => icmp_rdata, icmp_taken => icmp_taken,
      ack => ack, ack_cmd => ack_cmd, ack_key => ack_key, ack_status => ack_status,
      ack_taken => ack_taken, jr => jr, jr_status => jr_status, jr_seq => jr_seq,
      jr_taken => jr_taken, dhcp_strobe => dhcp_strobe, dhcp_rx => dhcp_rx,
      rx_rejects => rx_rejects, vlan_drops => bstat.host_vdrops,
      vlan_ip => bstat.vlan_ip, vlan_hits => bstat.vlan_hits);

  ---------------------------------------------------------------- text tap
  ttap : entity work.text_rx_tap
    port map (clk => clk_rx, rx_dv => rx_dv, rxd => rxd,
              mac0 => cfg(0).mac, mac1 => cfg(1).mac, vlan => bcfg.host_vlan,
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
      id_restart   <= '0';
      dhcp_restart <= '0';
      if ids_prev /= (id1 & id0) then
        ids_prev   <= id1 & id0;
        id_restart <= '1';
      end if;
      -- host VLAN changed: drop the leases (DHCP starts over, tagged as
      -- the new key says) 1..2 ms later; static addresses are kept
      if hv_prev /= bcfg.host_vlan then
        hv_prev <= bcfg.host_vlan;
        hv_wait <= to_unsigned(2, 3);
      elsif hv_wait /= 0 and tick_1ms = '1' then
        hv_wait <= hv_wait - 1;
        if hv_wait = 1 then dhcp_restart <= '1'; end if;
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
      j_tdo_addr => j_tdo_addr, j_tdo_data0 => j_tdo0, j_tdo_data1 => j_tdo1, j_tdo_data2 => j_tdo2,
      snap_req => snap_req, snap_ack => snap_ack, snap => snap, baud_inc => baud,
      boot_id => boot_id, hist_addr => hist_addr, hist_data0 => hist_data0,
      hist_data1 => hist_data1, hist_latch => hist_latch,
      rast_valid => rast_valid, rast_desc => rast_desc, rast_pop => rast_pop,
      rast_en => cap_on, rast_dut => cap_dut, rast_raddr => rast_raddr,
      rast_rdata => rast_rdata,
      th_valid => tp_valid, th_pkt => tp, th_taken => tp_taken, th_raddr => tp_raddr,
      th_rdata => tp_rdata, treq_valid => tq_valid, treq_scale => tq_sc, treq_div => tq_dv,
      treq_flags => tq_fl, treq_target => tq_tg, treq_taken => tq_taken,
      mac_start => mac_start, mac_base => mac_base, mac_len => mac_len, mac_vid => mac_vid,
      mac_busy => mac_busy, mem_we => txm_we, mem_addr => txm_wa,
      mem_data => txm_wd, frames_sent => frames_sent);

  txmem : entity work.dpram generic map (14, 8)
    port map (clk_sys, txm_we, txm_wa, txm_wd, clk_sys, txm_ra, txm_rd);
  mtx : entity work.eth_mac_tx
    generic map (ADDR_W => 14, LEN_W => 13)
    port map (clk_sys, mac_start, mac_base, mac_len, mac_vid, mac_busy, mac_done,
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
    -- output policy (key 0x0060: 0 auto, 1 force UART/KIO10 on, 2 force
    -- everything off, JTAG included) and the shield power-off hold: CTRL
    -- bit i = DUT i's power (power board CTRLn = DUTn), issue 0056
    pwr_eff(i) <= bcfg.pwr_ctl(i) when bcfg.pwr_set = '1' else shd_status.pwr(i);
    og : entity work.dut_out_gate
      port map (clk => clk_sys, policy => cfg(i).out_policy, powered => powered(i),
                shd_present => shd_status.flags(2), pwr_eff => pwr_eff(i),
                out_en => out_en(i), jtag_pow => jpow(i), hold => phold(i),
                tx_low => utx_low(i));
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
          enable => cfg(i).dhcp_en and ep_enable(i), restart => id_restart or dhcp_restart,
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
        snap_req => snap_req(i), snap_ack => snap_ack(i), hist_latch => hist_latch(i),
        hist_addr => hist_addr,
        hist_data => hd,
        snap_rx_seq => snap(i).rx_seq, snap_tx_accepted => snap(i).tx_accepted,
        snap_tx_emitted => snap(i).tx_emitted, snap_tx_free => snap(i).tx_free,
        snap_framing_errs => snap(i).framing_errs, snap_rx_overflows => snap(i).rx_overflows,
        snap_tx_rejects => snap(i).tx_rejects, snap_clear_gen => snap(i).clear_gen,
        snap_rx_seq_clear => snap(i).rx_seq_clear, snap_seq => snap(i).seq,
        rx_seq_o => u_rx_seq(i), tx_accepted_o => u_tx_acc(i));

    je : entity work.jtag_engine
      port map (
        clk => clk_sys, powered => jpow(i),
        req_valid => jreq_valid(i), req_seq => jreq_seq, req_bits => jreq_bits,
        req_half => jreq_half, req_abort => jreq_abort,
        dec_valid => jdec_valid(i), dec_code => jcode,
        vec_we => jvec_we(i), vec_addr => jvec_addr, vec_data => jvec_data,
        go => jgo(i), tdo_addr => j_tdo_addr, tdo_data => tdo_d,
        busy => jbusy(i), result_ready => jready(i), done_strobe => jdone(i),
        aborted => jab(i), next_seq => j_next(i), last_seq => j_last(i),
        last_bits => j_bits(i),
        tck => jtck(i), tms => jtms(i), tdi => jtdi(i), jtag_oe => jtag_oe(i),
        tdo => jtdo(i), vote => tdo_vote, start_ok => '1');

    kd : entity work.kbd_mk1_device
      generic map (SYNC_CYCLES => (CLK_HZ / 1000) * 61 / 10000)
      port map (
        clk => clk_sys, keys_pressed => kbd_eff(i),
        kio8_in => kio8(i), kio9_in => kio9(i), kio10_out => kio10(i),
        leds => dut_leds(i), leds_strobe => kbd_leds_stb(i),
        frame_count => kbd_frames(i));
    kio10_oe(i) <= out_en(i);

    -- status for heartbeat (phase 1: UDP always owns the keyboard)
    dstat(i).target_flags  <= "000" & phold(i) & '1' & out_en(i) & vio_s(i) & kb_s(i);
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
    dstat(i).jtag_status   <= "0000" & not jpow(i) & jab(i) & jready(i) & jbusy(i);
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
  -- keyboard host, b4 hdmi capture (0023)
  -- b7 thumbnails (issues 0035/0038)
  -- b8 physical keyboard CPLD JTAG (ADR 0014)
  bstat.caps        <= x"0000019F";
  bstat.selected    <= std_logic_vector(sel_vid) & std_logic_vector(sel_kbd);
  bstat.kbd_phys    <= pk_keys;
  bstat.phys_change <= pk_change;
  bstat.phys_type   <= "000000" & pk_type;     -- 0 none, 1 MK-I, 2 MK-II, 3 type 3
  bstat.rx_phase    <= std_logic_vector(hu_pos);
  bstat.rx_eye      <= std_logic_vector(hu_eye);
  bstat.rx_hunts    <= hu_hunts;
  bstat.rx_bad      <= hu_badcnt;
  -- b0 hunting, b1 RX MMCM locked, b3:2 link speed, b4 PHY held (issue 0070)
  bstat.rx_flags    <= "000" & link_hold & link_speed & lock_s(2) & hu_hunting;
  bstat.rx_reneg    <= link_reneg;
  bstat.mem         <= mem_status;
  bstat.nb          <= nb_st;
  bstat.shd         <= shd_status;
  pwr_ctl           <= bcfg.pwr_ctl;
  pwr_set           <= bcfg.pwr_set;
  -- b0 TMDS clock present = dvi2rgb's MMCM locked to it (its output free-runs
  -- otherwise, so a measured frequency alone means nothing); b1 decoding =
  -- also active video measured. Values read 0 while unlocked. b2 per DUT.
  vid_ok  <= vid_locked = '1' and vid_present = '1';
  vid_b0  <= '1' when vid_ok else '0';
  vid_b1  <= '1' when vid_ok and vid_h_active /= 0 and vid_v_active /= 0 else '0';
  -- b3 HDMI mode, b4 data islands (issue 0040; only while locked)
  bstat.vid_flags   <= "000" & (vid_b1 and vid_islands) & (vid_b1 and vid_hdmi) & '0' & vid_b1 & vid_b0;
  bstat.vid_h_total  <= vid_h_total  when vid_ok else (others => '0');
  bstat.vid_v_total  <= vid_v_total  when vid_ok else (others => '0');
  bstat.vid_h_active <= vid_h_active when vid_ok else (others => '0');
  bstat.vid_v_active <= vid_v_active when vid_ok else (others => '0');
  bstat.vid_pixel_hz <= vid_pixel_hz when vid_ok else (others => '0');

  ---------------------------------------------------------------- neighbour link
  -- Issue 0069: HELLOs to and from the other supervisor of the unit; role
  -- standalone / primary / secondary. Phase 1 only reports it (heartbeat
  -- neighbour block); nb_status.primary is the hook for issue 0044 (which
  -- board drives the unit's shared keyboard/video selection).
  nbl : entity work.neighbour_link
    generic map (HELLO_MS => NB_HELLO_MS, LOST_MS => NB_LOST_MS)
    port map (clk => clk_sys, tick_1ms => tick_1ms, dip => dip, dna => dna, build_id => BUILD_ID,
              boot_id => boot_id, txd => nb_txd, rxd => nb_rxd, status => nb_st);
  nb_status <= nb_st;

  ---------------------------------------------------------------- keyboard CPLD JTAG
  -- Third JTAG engine on the physical keyboard's J5 JTAG pins (issue 0046,
  -- ADR 0014), reached with JTAG_REQ flags b1 on either endpoint. The
  -- keyboard is powered from the Mimas, so "powered" means wanted: auto
  -- (key 0x0061 = 0) drives the pins while a keyboard is detected and for
  -- KJ_LEASE_MS after the last detection or keyboard JTAG transaction (a
  -- CPLD being flashed stops answering on KIO10); 1 forces on (e.g. a blank
  -- CPLD), 2 off, 3 on with JTAGEN driven low (diagnostic: does J5 pin 3
  -- gate the CPLD's JTAG port? ADR 0014).
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      if pk_present = '1' or (kj_pow = '1' and (jbusy(JT_KBD) = '1' or jdone(JT_KBD) = '1')) then
        kj_lease <= KJ_LEASE_MS;
      elsif tick_1ms = '1' and kj_lease /= 0 then
        kj_lease <= kj_lease - 1;
      end if;
      pk_jtagen_o <= '1';
      if bcfg.pk_jtag = x"01" then
        kj_pow <= '1';
      elsif bcfg.pk_jtag = x"03" then
        kj_pow      <= '1';
        pk_jtagen_o <= '0';
      elsif bcfg.pk_jtag = x"02" then
        kj_pow <= '0';
      elsif kj_lease /= 0 then
        kj_pow <= '1';
      else
        kj_pow <= '0';
      end if;
    end if;
  end process;
  kje : entity work.jtag_engine
    port map (
      clk => clk_sys, powered => kj_pow,
      req_valid => jreq_valid(JT_KBD), req_seq => jreq_seq, req_bits => jreq_bits,
      req_half => jreq_half, req_abort => jreq_abort,
      dec_valid => jdec_valid(JT_KBD), dec_code => jdec_code2,
      vec_we => jvec_we(JT_KBD), vec_addr => jvec_addr, vec_data => jvec_data,
      go => jgo(JT_KBD), tdo_addr => j_tdo_addr, tdo_data => j_tdo2,
      busy => jbusy(JT_KBD), result_ready => jready(JT_KBD), done_strobe => jdone(JT_KBD),
      aborted => jab(JT_KBD), next_seq => j_next(JT_KBD), last_seq => j_last(JT_KBD),
      last_bits => j_bits(JT_KBD),
      tck => pk_tck, tms => pk_tms, tdi => pk_tdi, jtag_oe => pk_jtag_oe,
      tdo => pk_tdo, vote => tdo_vote, start_ok => kq_ok);
  tdo_vote <= unsigned(bcfg.tdo_vote);   -- key 0x0064, all three engines

  -- key 0x0063 (issue 0054): 1 pauses the physical keyboard host while the
  -- keyboard engine is busy (admission .. done + KQ_GUARD); the first TCK
  -- edge waits until the host has been paused for KQ_GUARD (or KQ_TIMEOUT
  -- passed). 2 stops the host (no keyboard reported).
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      if bcfg.kj_quiet = "10" then kq_stop <= '1'; else kq_stop <= '0'; end if;
      if bcfg.kj_quiet = "01" and jbusy(JT_KBD) = '1' then
        kq_post  <= KQ_GUARD;
        kq_pause <= '1';
      elsif kq_post /= 0 then
        kq_post  <= kq_post - 1;
        kq_pause <= '1';
      else
        kq_pause <= '0';
      end if;
      if pk_paused = '0' then
        kq_pre <= 0;
      elsif kq_pre /= KQ_GUARD then
        kq_pre <= kq_pre + 1;
      end if;
      if jbusy(JT_KBD) = '0' or bcfg.kj_quiet = "00" then
        kq_to <= 0;
      elsif kq_to /= KQ_TIMEOUT then
        kq_to <= kq_to + 1;
      end if;
      if bcfg.kj_quiet = "00" or kq_to = KQ_TIMEOUT or (pk_paused = '1' and kq_pre = KQ_GUARD) then
        kq_ok <= '1';
      else
        kq_ok <= '0';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- raster capture
  -- Lines are captured for the video target when it is one of this board's
  -- DUTs, capture is enabled for it (key 0x0040) and it has an address; they
  -- go out as that DUT's raster packets (ADR 0005 s8, issue 0023).
  cap_dut <= to_integer(sel_vid(0 downto 0));
  process (clk_sys)   -- registered (timing: feeds net_tx's frame selection)
  begin
    if rising_edge(clk_sys) then
      -- never to a broadcast/multicast telemetry destination: ~570 Mb/s of
      -- raster would flood the whole segment (issue 0023 hardware note)
      if sel_vid < 2 and sel_own = '1' and bcfg.capture_en(cap_dut) = '1' and ep_enable(cap_dut) = '1' and
         ip_eff(cap_dut) /= x"00000000" and cfg(cap_dut).dest_ip /= x"FFFFFFFF" and
         cfg(cap_dut).dest_mac(40) = '0' then
        cap_on <= '1';
      else
        cap_on <= '0';
      end if;
    end if;
  end process;
  vid_ok_l <= '1' when vid_ok else '0';
  rcap : entity work.raster_capture
    generic map (RING_AW => 13, DESC_AW => 4, MAX_LINE_PX => 1024)
    port map (pclk => vin_pclk, de => vin_de, hs => vin_hs, vs => vin_vs, rgb => vin_rgb,
              locked => vid_ok_l, clk => clk_sys, enable => cap_on,
              desc_valid => rast_valid, desc => rast_desc, desc_pop => rast_pop,
              ring_addr => rast_raddr(12 downto 0), ring_data => rast_rdata);

  ---------------------------------------------------------------- thumbnails
  -- Local capture (issue 0035): the HDMI IN picture belongs to the video
  -- target when it is one of this board's DUTs and its video is decoded;
  -- stored at the scale/rate thumb_tx has in effect. Relay (issue 0038):
  -- received pictures of other machines go into their buffers; this
  -- board's pictures are streamed on request or to the forced MAC.
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      -- HDMI IN owner (key 0x0044, issue 0060): 0 the video target's DUT
      -- (both share the input), 1 DUT0, 2 DUT1, 3 none
      case bcfg.hdmi_own is
        when "00"   => own <= "11";
        when "01"   => own <= "01";
        when "10"   => own <= "10";
        when others => own <= "00";
      end case;
      if bcfg.hdmi_own = "00" or (sel_vid < 2 and own(to_integer(sel_vid(0 downto 0))) = '1') then
        sel_own <= '1';
      else
        sel_own <= '0';
      end if;
      vid_sel <= vid_b1 and sel_own;
      case bcfg.hdmi_own is
        when "00" =>
          if sel_vid < 2 and vid_b1 = '1' then tc_en <= '1'; else tc_en <= '0'; end if;
          if sel_vid(0) = '1' then tc_m <= m1; else tc_m <= m0; end if;
        when "01" => tc_en <= vid_b1; tc_m <= m0;
        when "10" => tc_en <= vid_b1; tc_m <= m1;
        when others => tc_en <= '0';
      end case;
      if scr = "10" then selecting <= '1'; else selecting <= '0'; end if;
      -- full view: the video target is a local machine without local video,
      -- the console is on auto and no selection is pending
      if sel_vid < 2 and sel_own = '0' and hk_sel = '0' and bcfg.con_screen = x"00" and
         text_forced = '0' then
        full_want <= '1';
      else
        full_want <= '0';
      end if;
      if sel_vid(0) = '1' then full_m <= m1; else full_m <= m0; end if;
      -- a complete full picture in the last second
      if full_ev = '1' then
        full_age <= (others => '0');
      elsif tick_1ms = '1' and full_age /= 2047 then
        full_age <= full_age + 1;
      end if;
      if full_want = '1' and full_age < THUMB_MS_PER_S then full_fresh <= '1'; else full_fresh <= '0'; end if;
    end if;
  end process;
  tcap : entity work.thumb_capture
    generic map (CROP_W => THUMB_CROP_W, CROP_H => THUMB_CROP_H, FIFO_AW => 7)
    port map (pclk => vin_pclk, de => vin_de, vs => vin_vs, rgb => vin_rgb, clk => clk_sys,
              enable => tc_en, quarter => te_q, div => te_div, machine => tc_m, cur => th_cur,
              lock_valid => tl_v, lock_machine => tl_m, lock_buf => tl_b,
              mem_req => thumb_mem_req(0), mem_rsp => thumb_mem_rsp(0),
              done => tc_done, done_machine => tc_dm, done_buf => tc_buf, done_quarter => tc_q,
              done_rows => tc_rows, frames => open, skipped => open);
  tstat : entity work.thumb_status
    port map (clk => clk_sys, tick_1ms => tick_1ms, local0 => m0, local1 => m1,
              ev_a => tc_done, ev_a_machine => tc_dm, ev_a_buf => tc_buf, ev_a_quarter => tc_q,
              ev_b => tr_ev, ev_b_machine => tr_m, ev_b_buf => tr_buf, ev_b_quarter => tr_q,
              seen_ev => tr_sev, seen_machine => tr_sm,
              seen => th_seen, fresh => th_fresh, cur => th_cur, quarter => th_q, n_seen => th_nseen);
  thumb_seen <= th_seen; thumb_fresh <= th_fresh; thumb_cur <= th_cur; thumb_quarter <= th_q;
  -- 16384 entries = 16 BRAM36, ~7.5 whole 1/1 RAW888 frames (~400 us of
  -- line rate with the writer stopped; issue 0060 relay-rx-speed)
  thtap : entity work.thumb_rx_tap
    generic map (FIFO_AW => RL_FIFO_AW)
    port map (clk => clk_rx, rx_dv => rx_dv, rxd => rxd, mac0 => cfg(0).mac, mac1 => cfg(1).mac,
              vlan => bcfg.vlan,
              sclk => clk_sys, f_valid => tf_valid, f_dout => tf_dout, f_pop => tf_pop,
              req_stb => trq_stb, req_mac => trq_mac, req_scale => trq_sc, req_div => trq_dv,
              req_flags => trq_fl, req_target => trq_tg,
              frames => open,
              c_req => bstat.relay.rx_req, c_lines => bstat.relay.rx_lines,
              c_bad => bstat.relay.rx_bad, c_ovf => bstat.relay.rx_ovf,
              c_nosrc => bstat.relay.rx_nosrc, c_vlan => bstat.relay.rx_vlan,
              c_long => bstat.relay.rx_long,
              last_valid => rl_lv, last_nosrc => rl_lns, last_m => rl_lm, last_scale => rl_lsc,
              win => rl_win, hwm => bstat.relay.fifo_hwm);
  trw : entity work.thumb_rx_writer
    port map (clk => clk_sys, f_valid => tf_valid, f_dout => tf_dout, f_pop => tf_pop,
              local0 => m0, local1 => m1, relay0 => not own(0), relay1 => not own(1), cur => th_cur,
              mem_req => thumb_mem_req(1), mem_rsp => thumb_mem_rsp(1),
              ev => tr_ev, ev_machine => tr_m, ev_buf => tr_buf, ev_quarter => tr_q,
              seen_ev => tr_sev, seen_machine => tr_sm, pictures => open,
              full_en => full_want, full_m => full_m, full_shown => full_shown,
              full_live => bcfg.relay_live,
              full_ev => full_ev, full_buf => full_buf, full_width => full_width,
              full_height => full_height, full_pics => bstat.relay.full_pics,
              foreign => bstat.relay.rx_foreign,
              win => rl_win, stall => bstat.relay.wr_stall, mwait => bstat.relay.mem_wait,
              wf_hwm => bstat.relay.wf_hwm);
  bstat.relay.fifo_aw <= to_unsigned(RL_FIFO_AW, 8);
  full_on <= full_fresh;
  ttx : entity work.thumb_tx
    generic map (MS_PER_S => THUMB_MS_PER_S)
    port map (clk => clk_sys, tick_1ms => tick_1ms, local0 => m0, local1 => m1,
              selecting => selecting, n_seen => th_nseen,
              force_mac => bcfg.thumb_mac, force_scale => bcfg.thumb_scale, force_div => bcfg.thumb_div,
              req_stb => trq_stb, req_mac => trq_mac, req_scale => trq_sc, req_div => trq_dv,
              req_flags => trq_fl, req_target => trq_tg,
              full_want => full_want, full_machine => full_m, rx_ev => tr_ev, rx_machine => tr_m,
              cap_done => tc_done, cap_machine => tc_dm, cap_buf => tc_buf, cap_quarter => tc_q,
              cap_rows => tc_rows, eff_quarter => te_q, eff_div => te_div,
              lock_valid => tl_v, lock_machine => tl_m, lock_buf => tl_b,
              mem_req => thumb_mem_req(2), mem_rsp => thumb_mem_rsp(2),
              pkt_valid => tp_valid, pkt => tp, pkt_taken => tp_taken,
              pb_raddr => tp_raddr, pb_rdata => tp_rdata,
              treq_valid => tq_valid, treq_scale => tq_sc, treq_div => tq_dv,
              treq_flags => tq_fl, treq_target => tq_tg, treq_taken => tq_taken,
              streaming => th_streaming, pictures => open);

  -- relay counters (issue 0061, ADR 0005 s3d): requests handed to net_tx,
  -- full_display buffer changes, full view state
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      rl_win <= '0';
      if tick_1ms = '1' then
        if rl_wms = THUMB_MS_PER_S - 1 then rl_wms <= (others => '0'); rl_win <= '1';
        else rl_wms <= rl_wms + 1; end if;
      end if;
      if tq_taken = '1' then
        rl_req_sent <= rl_req_sent + 1;
        if tq_fl(0) = '1' and tq_sc = x"03" then rl_req_full <= rl_req_full + 1; end if;
      end if;
      -- shown: complete pictures (key 0x0045 = 0) = buffer changes; live
      -- view = displayed frames with new lines since the frame before
      rl_shown_d <= full_shown;
      if bcfg.relay_live = '0' then
        if full_shown /= rl_shown_d then rl_swaps <= rl_swaps + 1; end if;
        rl_upd <= '0';
      else
        if full_frame = '1' then
          if rl_upd = '1' or full_ev = '1' then rl_swaps <= rl_swaps + 1; end if;
          rl_upd <= '0';
        elsif full_ev = '1' then
          rl_upd <= '1';
        end if;
      end if;
    end if;
  end process;
  bstat.relay.req_sent   <= rl_req_sent;
  bstat.relay.req_full   <= rl_req_full;
  bstat.relay.full_swaps <= rl_swaps;
  bstat.relay.flags      <= '0' & bcfg.relay_live & th_streaming & rl_lns & rl_lv & (full_want and not full_fresh) &
                            full_fresh & full_want;
  bstat.relay.last_m     <= "000" & std_logic_vector(rl_lm) when rl_lv = '1' else x"FF";
  bstat.relay.last_scale <= rl_lsc when rl_lv = '1' else x"00";
  bstat.relay.full_age   <= std_logic_vector(full_age(10 downto 3));

  ---------------------------------------------------------------- physical keyboard
  -- power LED colour = machine number k = 2 * DUT-ID nibble + half (P12 0,
  -- P13 1); gentle red pulse when the selected DUT is not powered (owner)
  pk_machine <= unsigned((id0(3 downto 0) & '0') + 0) when sel_kbd(0) = '0' else
                unsigned((id1(3 downto 0) & '1') + 0);
  pkl : entity work.kbd_led_status
    port map (clk => clk_sys, dut_leds => dut_leds(to_integer(sel_kbd(0 downto 0))),
              connected => powered(to_integer(sel_kbd(0 downto 0))),
              machine => pk_machine, selecting => hk_sel, leds => pk_leds);
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
              kbd_commit => pk_commit,
              pause => kq_pause, stop => kq_stop, paused => pk_paused);
  pk_present <= '1' when pk_type /= "00" else '0';

  -- KVM hotkey (issue 0029): both SHIFTs >= 1 s, tap MEGA, then 1..9,0
  hk : entity work.kvm_hotkey
    port map (clk => clk_sys, tick_1ms => tick_1ms, keys => pk_keys,
              selecting => hk_sel, choose => hk_cho, k => hk_k, cancel => hk_can);
  m0 <= unsigned(id0(3 downto 0) & '0');
  m1 <= unsigned(id1(3 downto 0) & '1');
  vid_machine    <= m1 when sel_vid(0) = '1' else m0;
  vid_machine_ok <= '1' when sel_vid < 2 else '0';
  g_slots : for k in 0 to 9 generate
    slots(k) <= '1' when m0 = k or m1 = k else '0';
  end generate;
  con_slots <= slots;
  -- console screen: forced by management, else select while choosing,
  -- editable when the host forced text or video is present, else no video.
  -- With video present on auto the HDMI OUT normally shows passthrough
  -- instead (pt_request below); this screen is then the fallback.
  scr <= "00" when bcfg.con_screen = x"01" else
         "01" when bcfg.con_screen = x"02" else
         "10" when bcfg.con_screen = x"03" else
         "10" when hk_sel = '1' else
         "00" when text_forced = '1' or vid_sel = '1' or full_fresh = '1' else
         "01";
  con_screen <= scr;
  -- passthrough (issue 0032): the auto screen choice with the video target
  -- one of this board's DUTs (phase 1: both share the one HDMI IN) and its
  -- video present; a forced screen, forced text or the select screen keep
  -- the console. Registered (text_forced comes from another clock domain;
  -- video_pt_ctrl debounces the request).
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      if bcfg.con_screen /= x"01" and bcfg.con_screen /= x"02" and bcfg.con_screen /= x"03" and
         hk_sel = '0' and text_forced = '0' and vid_b1 = '1' and sel_vid < 2 and sel_own = '1' then
        pt_req_r <= '1';
      else
        pt_req_r <= '0';
      end if;
    end if;
  end process;
  pt_request <= pt_req_r;
  bstat.con_shown <= CON_SHOWN_PASSTHROUGH when pt_active = '1' else
                     CON_SHOWN_RELAYED when full_fresh = '1' else
                     "000000" & std_logic_vector(scr);

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
