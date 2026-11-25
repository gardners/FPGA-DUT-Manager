-- Record types shared by the network dispatcher (net_rx) and builder (net_tx).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.proto_pkg.all;

package net_pkg is
  subtype mac_t is std_logic_vector(47 downto 0);
  subtype ip_t  is std_logic_vector(31 downto 0);

  type dut_cfg_t is record
    mac          : mac_t;
    ip           : ip_t;
    dest_mac     : mac_t;
    dest_ip      : ip_t;
    baud_inc     : unsigned(31 downto 0);
    uart_fast    : std_logic;
    uart_snap_en : std_logic;
    uart_period  : unsigned(15 downto 0);
    kbd_policy   : std_logic_vector(7 downto 0);
    kbd_override : std_logic_vector(7 downto 0);
    out_policy   : std_logic_vector(7 downto 0);
    hb_period_ms : unsigned(15 downto 0);
    dhcp_en      : std_logic;
  end record;
  type dut_cfg_arr_t is array (0 to 1) of dut_cfg_t;

  type board_cfg_t is record
    kbd_target : std_logic_vector(7 downto 0);
    vid_target : std_logic_vector(7 downto 0);
    coupled    : std_logic;
    capture_en : std_logic_vector(1 downto 0);
    cfg_gen    : unsigned(31 downto 0);
    pk_led_mode: std_logic_vector(7 downto 0);   -- 0 status colour, 1 DUT's LEDs, 2 host
    pk_led_host: std_logic_vector(95 downto 0);  -- LED vector for mode 2 (MK-I order)
  end record;

  -- a pending reply addressed to a requester
  type reply_t is record
    pend   : std_logic;
    dut    : integer range 0 to 1;
    mac    : mac_t;
    ip     : ip_t;
    port_n : std_logic_vector(15 downto 0);
  end record;
  constant REPLY_NONE : reply_t := ('0', 0, (others => '0'), (others => '0'), (others => '0'));
  type reply_arr_t is array (0 to 1) of reply_t;

  type u32_arr_t is array (0 to 1) of unsigned(31 downto 0);
  type u16_arr_t is array (0 to 1) of unsigned(15 downto 0);
  type slv8_arr_t is array (0 to 1) of std_logic_vector(7 downto 0);
  type kbd_arr_t is array (0 to 1) of std_logic_vector(79 downto 0);

  -- per-DUT live status for heartbeats
  type dut_status_t is record
    target_flags  : std_logic_vector(7 downto 0);
    kbd_owner     : std_logic_vector(7 downto 0);
    kbd_eff       : std_logic_vector(79 downto 0);
    kbd_udp       : std_logic_vector(79 downto 0);
    dut_leds      : std_logic_vector(95 downto 0);
    jtag_status   : std_logic_vector(7 downto 0);
    jtag_next_seq : unsigned(31 downto 0);
    uart_rx_seq   : unsigned(31 downto 0);
    uart_tx_acc   : unsigned(31 downto 0);
    rx_rejects    : unsigned(15 downto 0);
    addr_src      : std_logic_vector(7 downto 0);  -- 0 none, 1 DHCP, 2 fallback, 3 static
    dut_id        : std_logic_vector(7 downto 0);
  end record;
  type dut_status_arr_t is array (0 to 1) of dut_status_t;

  type board_status_t is record
    boot_id     : std_logic_vector(31 downto 0);
    build_id    : std_logic_vector(31 downto 0);
    dna         : std_logic_vector(63 downto 0);
    topo_index  : std_logic_vector(7 downto 0);
    topo_count  : std_logic_vector(7 downto 0);
    dip         : std_logic_vector(7 downto 0);
    link_flags  : std_logic_vector(7 downto 0);
    caps        : std_logic_vector(31 downto 0);
    selected    : std_logic_vector(7 downto 0);
    kbd_phys    : std_logic_vector(79 downto 0);
    phys_change : unsigned(15 downto 0);
    phys_type   : std_logic_vector(7 downto 0);
    -- RGMII RX phase hunter (issue 0028), heartbeat link block
    rx_phase    : std_logic_vector(7 downto 0);
    rx_eye      : std_logic_vector(7 downto 0);
    rx_hunts    : unsigned(15 downto 0);
    rx_bad      : unsigned(15 downto 0);
    rx_flags    : std_logic_vector(7 downto 0);   -- b0 hunting, b1 RX MMCM locked
    -- HDMI IN (issue 0022), heartbeat video block
    vid_flags   : std_logic_vector(7 downto 0);   -- b0 clock present, b1 locked
    vid_h_total, vid_v_total, vid_h_active, vid_v_active : unsigned(15 downto 0);
    vid_pixel_hz : unsigned(31 downto 0);
  end record;

  -- UART snapshot counters (latched by uart_bridge on snap_ack)
  type snap_t is record
    rx_seq, tx_accepted, tx_emitted, rx_seq_clear, seq : unsigned(31 downto 0);
    tx_free, framing_errs, rx_overflows, tx_rejects, clear_gen : unsigned(15 downto 0);
  end record;
  type snap_arr_t is array (0 to 1) of snap_t;

  type ip_arr_t is array (0 to 1) of ip_t;

  -- DHCP reply fields parsed by net_rx (one set, strobe per DUT)
  type dhcp_rx_t is record
    typ    : std_logic_vector(7 downto 0);
    xid    : std_logic_vector(31 downto 0);
    yiaddr : ip_t;
    server : ip_t;
    lease  : unsigned(31 downto 0);
    t1     : unsigned(31 downto 0);
  end record;

  -- DHCP transmit request from dhcp_client to net_tx
  type dhcp_tx_t is record
    req    : std_logic;
    typ    : std_logic_vector(7 downto 0);
    xid    : std_logic_vector(31 downto 0);
    ciaddr : ip_t;
    reqip  : ip_t;
    server : ip_t;
  end record;
  type dhcp_tx_arr_t is array (0 to 1) of dhcp_tx_t;

  -- ADR 0011: MAC 02:4D:36:35:00:<DUT ID>, fallback IP 192.168.65.(16+ID)
  -- id = DUT ID (issue 0026: 0x00..0x0F P12 half, 0x10..0x1F P13 half)
  function dut_mac(id : unsigned) return mac_t;
  function fallback_ip(id : unsigned) return ip_t;
  function default_cfg(id : unsigned) return dut_cfg_t;
end package;

package body net_pkg is
  function dut_mac(id : unsigned) return mac_t is
  begin
    return x"024D36350000" or std_logic_vector(resize(id, 48));
  end function;

  function fallback_ip(id : unsigned) return ip_t is
  begin
    return std_logic_vector(unsigned(DEFAULT_IP_BASE) + resize(id, 32));
  end function;

  function default_cfg(id : unsigned) return dut_cfg_t is
    variable c : dut_cfg_t;
  begin
    c.mac          := dut_mac(id);
    c.ip           := fallback_ip(id);
    c.dest_mac     := (others => '1');
    c.dest_ip      := (others => '1');
    c.baud_inc     := DEFAULT_BAUD_INC;
    c.uart_fast    := '0';
    c.uart_snap_en := '1';
    c.uart_period  := to_unsigned(1000, 16);
    c.kbd_policy   := x"00";
    c.kbd_override := x"00";
    c.out_policy   := x"00";
    c.hb_period_ms := to_unsigned(20, 16);
    c.dhcp_en      := '1';
    return c;
  end function;
end package body;
