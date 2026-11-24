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
  end record;
  type dut_cfg_arr_t is array (0 to 1) of dut_cfg_t;

  type board_cfg_t is record
    kbd_target : std_logic_vector(7 downto 0);
    vid_target : std_logic_vector(7 downto 0);
    coupled    : std_logic;
    capture_en : std_logic_vector(1 downto 0);
    cfg_gen    : unsigned(31 downto 0);
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
  end record;

  -- UART snapshot counters (latched by uart_bridge on snap_ack)
  type snap_t is record
    rx_seq, tx_accepted, tx_emitted, rx_seq_clear, seq : unsigned(31 downto 0);
    tx_free, framing_errs, rx_overflows, tx_rejects, clear_gen : unsigned(15 downto 0);
  end record;
  type snap_arr_t is array (0 to 1) of snap_t;

  function default_cfg(dut : natural; node : unsigned(3 downto 0); dna_hash : std_logic_vector(7 downto 0))
    return dut_cfg_t;
end package;

package body net_pkg is
  function default_cfg(dut : natural; node : unsigned(3 downto 0); dna_hash : std_logic_vector(7 downto 0))
    return dut_cfg_t is
    variable c : dut_cfg_t;
  begin
    c.mac          := x"024D3635" & dna_hash & std_logic_vector(to_unsigned(dut, 8));
    c.ip           := std_logic_vector(unsigned(DEFAULT_IP_BASE) + resize(node & '0', 32) + dut);
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
    return c;
  end function;
end package body;
