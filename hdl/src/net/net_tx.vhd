-- net_tx: frame builder and TX arbiter (clk_sys).
--
-- Picks the next pending item (fixed priority: raster line, ARP, JTAG
-- response, MGMT ack, ICMP, DHCP, UART snapshot, heartbeat), writes the
-- complete frame (no preamble or FCS) into one of two 4 KiB TX slots, then
-- hands the slot to eth_mac_tx.
-- While the MAC sends one slot the next frame is built in the other.
--
-- Frame = 42-byte Eth/IPv4/UDP header (34 for ICMP) + fixed part (pf array,
-- includes the 8-byte custom header) + tail streamed from a memory port
-- (UART history, JTAG TDO, ICMP data). IPv4 header checksum is computed;
-- UDP checksum is 0 (ADR 0005).
--
-- Writing (issue 0019, timing): hdr & pf form one shift register that emits
-- sr(0) each cycle -- no byte-index muxes. A frame is up to three segments:
--   A: a_len bytes shifted out of hdr & pf,
--   B: b_len tail bytes (memory port with 1-cycle latency; zeros for DHCP),
--   C: c_len further bytes shifted out of pf (DHCP cookie and options).
-- DHCP payload (300 bytes) = pf(0..43) BOOTP head, 192 zero bytes,
-- pf(44..107) = BOOTP bytes 236..299.
--
-- Raster (issue 0023, ADR 0005 s8 v1): a committed line from raster_capture
-- has priority at frame boundaries (it wins whenever a new frame is chosen,
-- except that a raster frame never follows a raster frame while other
-- traffic is waiting: control traffic keeps flowing even when the source
-- needs more than the link). One datagram per line: segment A = headers + the
-- 52-byte raster header (incl. the latest 16 UART RX bytes, copied from the
-- history port into a shift register in S_HIST), segment B = the pixels
-- streamed from the ring (24-bit words, shifted out R, G, B). Lines arriving
-- while capture is off for the video target (or it has no address) are
-- discarded. Up to 42 + 52 + 3072 = 3166 bytes per frame (jumbo).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.proto_pkg.all;
use work.net_pkg.all;
use work.raster_pkg.all;
use work.thumb_pkg.all;

entity net_tx is
  port (
    clk        : in  std_logic;
    tick_1ms   : in  std_logic;
    cfg        : in  dut_cfg_arr_t;
    bcfg       : in  board_cfg_t;
    bstat      : in  board_status_t;
    dstat      : in  dut_status_arr_t;
    hb_expedite: in  std_logic;            -- master physical keyboard change
    ip_eff     : in  ip_arr_t;
    ep_enable  : in  std_logic_vector(1 downto 0);
    dhcp       : in  dhcp_tx_arr_t;
    dhcp_taken : out std_logic_vector(1 downto 0);
    -- replies from net_rx
    arp        : in  reply_t;
    arp_taken  : out std_logic;
    icmp       : in  reply_t;
    icmp_len   : in  unsigned(6 downto 0);
    icmp_raddr : out unsigned(6 downto 0);
    icmp_rdata : in  std_logic_vector(7 downto 0);
    icmp_taken : out std_logic;
    ack        : in  reply_t;
    ack_cmd    : in  std_logic_vector(15 downto 0);
    ack_key    : in  std_logic_vector(15 downto 0);
    ack_status : in  std_logic_vector(7 downto 0);
    ack_taken  : out std_logic;
    -- JTAG responses per target (net_pkg JT_*: 0/1 DUTs, 2 keyboard CPLD);
    -- jr(t).dut is the endpoint that sends it
    jr         : in  jreply_arr_t;
    jr_status  : in  jslv8_arr_t;
    jr_seq     : in  ju32_arr_t;
    jr_taken   : out std_logic_vector(2 downto 0);
    -- JTAG results
    j_next_seq : in  ju32_arr_t;
    j_bits     : in  ju32_arr_t;
    j_tdo_addr : out unsigned(9 downto 0);
    j_tdo_data0, j_tdo_data1, j_tdo_data2 : in std_logic_vector(7 downto 0);
    -- UART snapshots
    snap_req   : in  std_logic_vector(1 downto 0);
    snap_ack   : out std_logic_vector(1 downto 0);
    snap       : in  snap_arr_t;
    baud_inc   : in  u32_arr_t;
    boot_id    : in  std_logic_vector(31 downto 0);
    hist_addr  : out unsigned(9 downto 0);
    hist_data0, hist_data1 : in std_logic_vector(7 downto 0);
    hist_latch : out std_logic_vector(1 downto 0);   -- latch the RX history now (raster)
    -- raster capture (issue 0023)
    rast_valid : in  std_logic := '0';
    rast_desc  : in  rast_desc_t := RAST_DESC_NONE;
    rast_pop   : out std_logic;
    rast_en    : in  std_logic := '0';     -- capture on for rast_dut and it is addressed
    rast_dut   : in  integer range 0 to 1 := 0;
    rast_raddr : out unsigned(15 downto 0);
    rast_rdata : in  std_logic_vector(23 downto 0) := (others => '0');
    -- thumbnail relay (issue 0038, ADR 0005 s10): raw Ethernet frames from
    -- thumb_tx's packet buffer, and broadcast requests
    th_valid   : in  std_logic := '0';
    th_pkt     : in  thumb_pkt_t := THUMB_PKT_NONE;
    th_taken   : out std_logic;
    th_raddr   : out unsigned(12 downto 0);
    th_rdata   : in  std_logic_vector(7 downto 0) := (others => '0');
    treq_valid : in  std_logic := '0';
    treq_scale : in  std_logic_vector(7 downto 0) := x"01";
    treq_div   : in  std_logic_vector(7 downto 0) := x"02";
    treq_flags : in  std_logic_vector(7 downto 0) := x"00";   -- issue 0060: b0 targeted, b1 priority
    treq_target: in  std_logic_vector(7 downto 0) := x"00";
    treq_taken : out std_logic;
    -- MAC
    mac_start  : out std_logic;
    mac_base   : out unsigned(13 downto 0);
    mac_len    : out unsigned(12 downto 0);
    mac_busy   : in  std_logic;
    mem_we     : out std_logic;
    mem_addr   : out unsigned(13 downto 0);
    mem_data   : out std_logic_vector(7 downto 0);
    -- statistics
    frames_sent: out unsigned(31 downto 0)
  );
end entity;

architecture rtl of net_tx is
  type kind_t is (K_NONE, K_RAST, K_ARP, K_JRESP, K_ACK, K_ICMP, K_DHCP, K_THUMB, K_TREQ, K_SNAP, K_HB);
  signal kind : kind_t := K_NONE;
  signal d    : integer range 0 to 1 := 0;
  attribute max_fanout : integer;
  attribute max_fanout of d : signal is 24;   -- replicated (timing, issue 0038)

  type state_t is (S_IDLE, S_DISCARD, S_LATCH, S_HIST, S_PREP, S_CSUM, S_START, S_WRITE, S_WAIT_MAC);
  signal state : state_t := S_IDLE;

  constant PF_MAX : natural := 196;   -- heartbeat: 8 + 188
  type pf_t is array (0 to PF_MAX - 1) of byte_t;
  type hdr_t is array (0 to 41) of byte_t;
  signal hdr   : hdr_t := (others => (others => '0'));
  signal pf    : pf_t := (others => (others => '0'));
  signal a_len    : unsigned(12 downto 0) := (others => '0');  -- segment lengths
  signal b_len    : unsigned(12 downto 0) := (others => '0');
  signal c_len    : unsigned(12 downto 0) := (others => '0');
  signal total    : unsigned(12 downto 0) := (others => '0');
  type seg_t is (SEG_A, SEG_B, SEG_C);
  signal seg      : seg_t := SEG_A;
  signal cnt      : unsigned(12 downto 0) := (others => '0');  -- bytes left in seg - 1

  signal csum  : unsigned(15 downto 0) := (others => '0');
  signal cidx  : integer range 0 to 11 := 0;
  signal cw    : unsigned(15 downto 0) := (others => '0');  -- checksum word (pipelined)

  signal widx  : unsigned(12 downto 0) := (others => '0');   -- byte being written
  signal bslot : std_logic := '0';
  signal pend_slot : std_logic := '0';
  signal pend_len  : unsigned(12 downto 0) := (others => '0');
  signal pend_valid: std_logic := '0';
  signal tail_addr : unsigned(12 downto 0) := (others => '0');

  signal hb_cnt  : u16_arr_t := (others => (others => '0'));
  signal hb_due  : std_logic_vector(1 downto 0) := "00";
  signal hb_seq  : u32_arr_t := (others => (others => '0'));
  signal sent    : unsigned(31 downto 0) := (others => '0');
  signal rr      : std_logic := '0';      -- round robin between DUTs
  signal jtg     : integer range 0 to 2 := 0;   -- JTAG target of a K_JRESP
  signal jr_nb   : unsigned(31 downto 0) := (others => '0');  -- JRESP TDO bytes (S_LATCH)

  -- raster
  type hist_t is array (0 to 15) of byte_t;
  signal hist_sr : hist_t := (others => (others => '0'));
  signal hcnt    : integer range 0 to 16 := 0;
  signal rast_nb : unsigned(11 downto 0) := (others => '0');   -- pixel bytes = 3 * count
  signal rast_rxseq : unsigned(31 downto 0) := (others => '0');
  signal raddr   : unsigned(15 downto 0) := (others => '0');
  signal pix_sr  : std_logic_vector(23 downto 0) := (others => '0');
  signal ph, pr  : integer range 0 to 2 := 0;
  signal rast_frames : unsigned(31 downto 0) := (others => '0');
  signal rast_drops  : unsigned(15 downto 0) := (others => '0');
  signal last_rast   : std_logic := '0';    -- previous frame built was raster
  signal ep_ok       : std_logic_vector(1 downto 0) := "00";  -- enabled and addressed (registered, timing)
  -- DHCP inputs of endpoint d, registered every cycle (timing): d is fixed
  -- from S_LATCH on, so in S_PREP these hold dhcp(d), cfg(d).mac and the
  -- DUT ID as sampled one cycle earlier (no per-DUT mux or 32-bit compare
  -- in front of the payload fill)
  signal dq       : dhcp_tx_t := (req => '0', typ => x"00", others => (others => '0'));
  signal dq_mac   : mac_t := (others => '0');
  signal dq_id    : byte_t := (others => '0');
  signal dq_has50, dq_has54 : boolean := false;

  function b(v : std_logic_vector; i : natural) return byte_t is
    -- byte i counting from the most significant byte (big-endian)
    variable n : natural := v'length / 8;
    variable x : std_logic_vector(v'length - 1 downto 0) := v;
  begin
    return x((n - i) * 8 - 1 downto (n - i - 1) * 8);
  end function;
  function bu(v : unsigned; i : natural) return byte_t is
  begin
    return b(std_logic_vector(v), i);
  end function;

  function hexc(v : natural) return byte_t is
  begin
    if v < 10 then return std_logic_vector(to_unsigned(48 + v, 8));
    else return std_logic_vector(to_unsigned(87 + v, 8)); end if;   -- 'a'..'f'
  end function;

  -- DHCP DISCOVER/REQUEST UDP payload (300 bytes, RFC 2131/2132)
  -- has50/has54: t.reqip / t.server non-zero (precomputed, timing)
  function dhcp_byte(i : natural; mac : mac_t; t : dhcp_tx_t; id : std_logic_vector(7 downto 0);
                     has50, has54 : boolean)
    return byte_t is
    variable tens, ones : natural;
    -- options: 53 type, 61 client id, 12 host name, [50 req ip], [54 server], 55 params, 255
    variable o : integer;
  begin
    -- host name digits: DUT ID in lower-case hex (issue 0026), = MAC byte 5
    tens := to_integer(unsigned(id(7 downto 4)));
    ones := to_integer(unsigned(id(3 downto 0)));
    case i is
      when 0 => return x"01";                 -- BOOTREQUEST
      when 1 => return x"01";                 -- Ethernet
      when 2 => return x"06";
      when 4 to 7 => return b(t.xid, i - 4);
      when 10 => return x"80";                -- broadcast flag
      when 12 to 15 => return b(t.ciaddr, i - 12);
      when 28 to 33 => return b(mac, i - 28);
      when 236 => return x"63";
      when 237 => return x"82";
      when 238 => return x"53";
      when 239 => return x"63";
      when others => null;
    end case;
    if i < 240 then
      return x"00";
    end if;
    o := i - 240;
    -- 53,1,type
    if o = 0 then return x"35"; elsif o = 1 then return x"01"; elsif o = 2 then return t.typ; end if;
    -- 61,7,1,mac
    if o = 3 then return x"3D"; elsif o = 4 then return x"07"; elsif o = 5 then return x"01"; end if;
    if o >= 6 and o <= 11 then return b(mac, o - 6); end if;
    -- 12,8,"m65dutNN"
    case o is
      when 12 => return x"0C";
      when 13 => return x"08";
      when 14 => return x"6D";                -- m
      when 15 => return x"36";                -- 6
      when 16 => return x"35";                -- 5
      when 17 => return x"64";                -- d
      when 18 => return x"75";                -- u
      when 19 => return x"74";                -- t
      when 20 => return hexc(tens);
      when 21 => return hexc(ones);
      when others => null;
    end case;
    o := o - 22;
    if has50 then
      if o = 0 then return x"32"; elsif o = 1 then return x"04"; end if;
      if o >= 2 and o <= 5 then return b(t.reqip, o - 2); end if;
      o := o - 6;
    end if;
    if has54 then
      if o = 0 then return x"36"; elsif o = 1 then return x"04"; end if;
      if o >= 2 and o <= 5 then return b(t.server, o - 2); end if;
      o := o - 6;
    end if;
    -- 55,4: subnet, router, lease, T1
    case o is
      when 0 => return x"37";
      when 1 => return x"04";
      when 2 => return x"01";
      when 3 => return x"03";
      when 4 => return x"33";
      when 5 => return x"3A";
      when 6 => return x"FF";
      when others => return x"00";
    end case;
  end function;
begin
  frames_sent <= sent;
  hist_addr   <= tail_addr(9 downto 0);
  j_tdo_addr  <= tail_addr(9 downto 0);
  icmp_raddr  <= tail_addr(6 downto 0);
  rast_raddr  <= raddr;
  th_raddr    <= tail_addr;

  process (clk)
    variable k       : kind_t;
    variable dd      : integer range 0 to 1;
    variable jj      : integer range 0 to 2;
    variable dmac    : mac_t;
    variable dip     : ip_t;
    variable dport   : std_logic_vector(15 downto 0);
    variable sport   : natural;
    variable typ     : byte_t;
    variable plen    : natural;     -- custom payload length (excl. 8-byte hdr)
    variable tl      : natural;     -- tail bytes
    variable iplen   : unsigned(15 downto 0);
    variable proto   : byte_t;
    variable nbytes  : unsigned(31 downto 0);
    variable wb      : byte_t;
    variable st      : dut_status_t;
    variable tgo     : natural range 0 to 4;   -- 802.1Q tag bytes (relay frames)
  begin
    if rising_edge(clk) then
      arp_taken  <= '0';
      icmp_taken <= '0';
      ack_taken  <= '0';
      jr_taken   <= "000";
      snap_ack   <= "00";
      dhcp_taken <= "00";
      mac_start  <= '0';
      mem_we     <= '0';
      rast_pop   <= '0';
      hist_latch <= "00";
      th_taken   <= '0';
      treq_taken <= '0';
      for i in 0 to 1 loop
        if ep_enable(i) = '1' and ip_eff(i) /= x"00000000" then ep_ok(i) <= '1'; else ep_ok(i) <= '0'; end if;
      end loop;
      dq       <= dhcp(d);
      dq_mac   <= cfg(d).mac;
      dq_id    <= dstat(d).dut_id;
      dq_has50 <= dhcp(d).reqip /= x"00000000";
      dq_has54 <= dhcp(d).server /= x"00000000";

      -- heartbeat timers
      for i in 0 to 1 loop
        if tick_1ms = '1' then
          if hb_cnt(i) + 1 >= cfg(i).hb_period_ms then
            hb_cnt(i) <= (others => '0');
            hb_due(i) <= '1';
          else
            hb_cnt(i) <= hb_cnt(i) + 1;
          end if;
        end if;
      end loop;
      if hb_expedite = '1' then
        hb_due <= "11";
      end if;

      -- hand a finished slot to the MAC
      if pend_valid = '1' and mac_busy = '0' then
        mac_start  <= '1';
        mac_base   <= pend_slot & "0000000000000";
        mac_len    <= pend_len;
        pend_valid <= '0';
        sent       <= sent + 1;
      end if;

      case state is
        when S_IDLE =>
          k := K_NONE; dd := 0; jj := 0;
          if arp.pend = '1' then k := K_ARP; dd := arp.dut;
          elsif jr(0).pend = '1' and (rr = '0' or jr(1).pend = '0') then k := K_JRESP; dd := 0;
          elsif jr(1).pend = '1' then k := K_JRESP; dd := 1; jj := 1;
          elsif jr(JT_KBD).pend = '1' then k := K_JRESP; dd := jr(JT_KBD).dut; jj := JT_KBD;
          elsif ack.pend = '1' then k := K_ACK; dd := ack.dut;
          elsif icmp.pend = '1' then k := K_ICMP; dd := icmp.dut;
          elsif dhcp(0).req = '1' and ep_enable(0) = '1' then k := K_DHCP; dd := 0;
          elsif dhcp(1).req = '1' and ep_enable(1) = '1' then k := K_DHCP; dd := 1;
          -- thumbnail relay: below control traffic, above telemetry (owner)
          elsif th_valid = '1' and ep_enable(th_pkt.d) = '1' then k := K_THUMB; dd := th_pkt.d;
          elsif treq_valid = '1' and ep_enable(0) = '1' then k := K_TREQ; dd := 0;
          elsif snap_req(0) = '1' and ep_ok(0) = '1' and (rr = '0' or snap_req(1) = '0') then k := K_SNAP; dd := 0;
          elsif snap_req(1) = '1' and ep_ok(1) = '1' then k := K_SNAP; dd := 1;
          elsif hb_due(0) = '1' and ep_ok(0) = '1' and (rr = '0' or hb_due(1) = '0') then k := K_HB; dd := 0;
          elsif hb_due(1) = '1' and ep_ok(1) = '1' then k := K_HB; dd := 1;
          end if;
          -- raster first; but never two raster frames in a row while other
          -- traffic waits (a source above ~1 Gb/s would starve it otherwise)
          if rast_valid = '1' and rast_en = '1' and (last_rast = '0' or k = K_NONE) then
            k := K_RAST; dd := rast_dut;
          end if;
          -- a disabled (DUT ID conflict) or not yet addressed endpoint drops
          -- its periodic traffic (DHCP required, ADR 0011)
          for i in 0 to 1 loop
            if ep_ok(i) = '0' then
              hb_due(i) <= '0';
            end if;
          end loop;
          if rast_valid = '1' and rast_en = '0' then
            -- capture off / target not addressed: discard the line
            rast_pop <= '1';
            state    <= S_DISCARD;
          elsif k /= K_NONE and pend_valid = '0' then
            rr    <= not rr;
            if k = K_RAST then last_rast <= '1'; else last_rast <= '0'; end if;
            kind  <= k;
            d     <= dd;
            jtg   <= jj;
            state <= S_LATCH;
            case k is
              when K_ARP  => arp_taken <= '1';
              when K_ICMP => null;            -- taken after data copied
              when K_ACK  => ack_taken <= '1';
              when K_JRESP=> jr_taken(jj) <= '1';
              when K_SNAP => snap_ack(dd) <= '1';
              when K_HB   => hb_due(dd) <= '0';
              when K_DHCP => dhcp_taken(dd) <= '1';
              when K_RAST => hist_latch(dd) <= '1';
              when K_TREQ => treq_taken <= '1';
              when others => null;
            end case;
          end if;

        when S_DISCARD =>
          state <= S_IDLE;              -- let rast_valid fall after the pop

        when S_LATCH =>
          -- uart_bridge latches its snapshot counters on the cycle after
          -- snap_ack; wait for them before using snap(d). Also precompute
          -- the JTAG response byte count (timing, issue 0019).
          jr_nb <= (others => '0');
          if jr_status(jtg) = JS_DONE then
            jr_nb <= shift_right(j_bits(jtg) + 7, 3);
          end if;
          state <= S_PREP;
          if kind = K_RAST then
            -- uart_bridge latched its RX history on this edge (hist_latch)
            rast_nb    <= resize(rast_desc.count & '0', 12) + rast_desc.count;
            rast_rxseq <= dstat(d).uart_rx_seq;
            tail_addr  <= to_unsigned(496, 13);   -- latest 16 of the 512 RX bytes
            hcnt       <= 0;
            state      <= S_HIST;
          end if;

        when S_HIST =>
          -- 16 RX history bytes, oldest first, one-cycle read latency
          tail_addr <= tail_addr + 1;
          if hcnt /= 0 then
            for i in 0 to 14 loop hist_sr(i) <= hist_sr(i + 1); end loop;
            if d = 0 then hist_sr(15) <= hist_data0; else hist_sr(15) <= hist_data1; end if;
          end if;
          if hcnt = 16 then
            state <= S_PREP;
          else
            hcnt <= hcnt + 1;
          end if;

        when S_PREP =>
          -- destination and payload layout per kind
          dmac := cfg(d).dest_mac; dip := cfg(d).dest_ip;
          dport := (others => '0'); sport := 0; typ := x"00"; plen := 0; tl := 0;
          proto := x"11";
          pf <= (others => (others => '0'));
          case kind is
            when K_ARP =>
              dmac := arp.mac; dip := arp.ip;
            when K_THUMB =>
              dmac := th_pkt.dst;
            when K_TREQ =>
              dmac := (others => '1');
            when K_ICMP =>
              dmac := icmp.mac; dip := icmp.ip; proto := x"01";
              tl := to_integer(icmp_len);
            when K_DHCP =>
              dmac := (others => '1'); dip := (others => '1');
              sport := PORT_DHCP_C; dport := std_logic_vector(to_unsigned(PORT_DHCP_S, 16));
              tl := 300;
              for i in 0 to 43 loop
                pf(i) <= dhcp_byte(i, dq_mac, dq, dq_id, dq_has50, dq_has54);
              end loop;
              for i in 0 to 63 loop
                pf(44 + i) <= dhcp_byte(236 + i, dq_mac, dq, dq_id, dq_has50, dq_has54);
              end loop;
            when K_ACK =>
              dmac := ack.mac; dip := ack.ip; dport := ack.port_n; sport := PORT_MGMT;
              typ := T_MGMT_ACK; plen := ACK_PAYLOAD_LEN;
              pf(8) <= ack_cmd(15 downto 8); pf(9) <= ack_cmd(7 downto 0);
              pf(10) <= ack_key(15 downto 8); pf(11) <= ack_key(7 downto 0);
              pf(12) <= ack_status; pf(13) <= x"00";
              for i in 0 to 3 loop pf(14 + i) <= bu(bcfg.cfg_gen, i); end loop;
            when K_JRESP =>
              dmac := jr(jtg).mac; dip := jr(jtg).ip; dport := jr(jtg).port_n; sport := PORT_JTAG;
              typ := T_JTAG_RESP;
              nbytes := jr_nb;
              plen := JRESP_FIXED_LEN + to_integer(nbytes(11 downto 0));
              tl   := to_integer(nbytes(11 downto 0));
              for i in 0 to 3 loop
                pf(8 + i)  <= bu(jr_seq(jtg), i);
                pf(12 + i) <= bu(j_next_seq(jtg), i);
                pf(20 + i) <= bu(j_bits(jtg), i);
              end loop;
              -- byte 17: target, 0 = DUT, 1 = physical keyboard CPLD (ADR 0014)
              pf(16) <= jr_status(jtg);
              if jtg = JT_KBD then pf(17) <= x"01"; else pf(17) <= x"00"; end if;
              pf(18) <= bu(nbytes(15 downto 0), 0); pf(19) <= bu(nbytes(15 downto 0), 1);
              if jr_status(jtg) /= JS_DONE then
                for i in 0 to 3 loop pf(20 + i) <= x"00"; end loop;
              end if;
            when K_SNAP =>
              sport := PORT_UART; dport := std_logic_vector(to_unsigned(PORT_UART, 16));
              typ := T_UART_SNAP; plen := SNAP_PAYLOAD_LEN; tl := 640;
              for i in 0 to 3 loop
                pf(8 + i)  <= b(boot_id, i);
                pf(12 + i) <= bu(snap(d).seq, i);
                pf(16 + i) <= bu(snap(d).rx_seq, i);
                pf(20 + i) <= bu(snap(d).tx_accepted, i);
                pf(24 + i) <= bu(snap(d).tx_emitted, i);
                pf(38 + i) <= bu(snap(d).rx_seq_clear, i);
                pf(42 + i) <= bu(baud_inc(d), i);
              end loop;
              for i in 0 to 1 loop
                pf(28 + i) <= bu(snap(d).tx_free, i);
                pf(30 + i) <= bu(snap(d).framing_errs, i);
                pf(32 + i) <= bu(snap(d).rx_overflows, i);
                pf(34 + i) <= bu(snap(d).tx_rejects, i);
                pf(36 + i) <= bu(snap(d).clear_gen, i);
              end loop;
            when K_RAST =>
              sport := PORT_RAST; dport := std_logic_vector(to_unsigned(PORT_RAST, 16));
              typ := T_RASTER;
              plen := RASTER_FIXED_LEN + to_integer(rast_nb);
              tl   := to_integer(rast_nb);
              pf(8) <= RASTER_VERSION; pf(9) <= x"00";       -- raw RGB888
              pf(10) <= rast_desc.flags; pf(11) <= x"00";
              for i in 0 to 3 loop
                pf(12 + i) <= bu(rast_desc.frame, i);
                pf(32 + i) <= bu(rast_rxseq, i);
              end loop;
              for i in 0 to 1 loop
                pf(16 + i) <= bu(rast_desc.line, i);
                pf(18 + i) <= bu(bstat.vid_h_total, i);
                pf(20 + i) <= bu(bstat.vid_v_total, i);
                pf(22 + i) <= bu(resize(rast_desc.count, 16), i);
                pf(24 + i) <= bu(bstat.vid_v_active, i);
                pf(26 + i) <= bu(rast_desc.hs_start, i);
                pf(28 + i) <= bu(rast_desc.hs_end, i);
                pf(30 + i) <= bu(resize(rast_nb, 16), i);
              end loop;
              for i in 0 to 15 loop pf(36 + i) <= hist_sr(i); end loop;
            when K_HB =>
              sport := PORT_HB; dport := std_logic_vector(to_unsigned(PORT_HB, 16));
              typ := T_HEARTBEAT; plen := HB_PAYLOAD_LEN;
              st := dstat(d);
              hb_seq(d) <= hb_seq(d) + 1;
              for i in 0 to 3 loop
                pf(8 + i)  <= bu(hb_seq(d), i);
                pf(12 + i) <= b(bstat.boot_id, i);
                pf(16 + i) <= b(bstat.build_id, i);
                pf(32 + i) <= b(bstat.caps, i);
                pf(36 + i) <= bu(bcfg.cfg_gen, i);
                pf(78 + i) <= bu(st.jtag_next_seq, i);
                pf(82 + i) <= bu(st.uart_rx_seq, i);
                pf(86 + i) <= bu(st.uart_tx_acc, i);
              end loop;
              for i in 0 to 7 loop pf(20 + i) <= b(bstat.dna, i); end loop;
              pf(28) <= bstat.topo_index; pf(29) <= bstat.topo_count;
              pf(30) <= bstat.dip;        pf(31) <= bstat.link_flags;
              pf(40) <= st.target_flags;  pf(41) <= st.kbd_owner;
              pf(42) <= cfg(d).kbd_policy; pf(43) <= bstat.selected;
              for i in 0 to 9 loop
                pf(44 + i) <= st.kbd_eff(8 * i + 7 downto 8 * i);
                pf(54 + i) <= st.kbd_udp(8 * i + 7 downto 8 * i);
                pf(64 + i) <= bstat.kbd_phys(8 * i + 7 downto 8 * i);
              end loop;
              pf(74) <= bu(bstat.phys_change, 0); pf(75) <= bu(bstat.phys_change, 1);
              pf(76) <= bstat.phys_type; pf(77) <= st.jtag_status;
              pf(90) <= bu(st.rx_rejects, 0); pf(91) <= bu(st.rx_rejects, 1);
              pf(92) <= x"00"; pf(93) <= x"00";
              pf(106) <= st.addr_src; pf(107) <= st.dut_id;
              for i in 0 to 11 loop pf(94 + i) <= b(st.dut_leds, i); end loop;
              -- 108..131 video block (ADR 0005 s8): HDMI IN measurement,
              -- frames captured (line 0 sent) and raster lines dropped
              -- (board-wide); decode errors 0 (not counted yet)
              pf(108) <= bstat.vid_flags(7 downto 3) & bcfg.capture_en(d) & bstat.vid_flags(1 downto 0);
              pf(109) <= bstat.con_shown;     -- console screen shown (issue 0029)
              pf(110) <= bu(bstat.vid_h_total, 0);  pf(111) <= bu(bstat.vid_h_total, 1);
              pf(112) <= bu(bstat.vid_v_total, 0);  pf(113) <= bu(bstat.vid_v_total, 1);
              pf(114) <= bu(bstat.vid_h_active, 0); pf(115) <= bu(bstat.vid_h_active, 1);
              pf(116) <= bu(bstat.vid_v_active, 0); pf(117) <= bu(bstat.vid_v_active, 1);
              for i in 0 to 3 loop
                pf(118 + i) <= bu(bstat.vid_pixel_hz, i);
                pf(122 + i) <= bu(rast_frames, i);
              end loop;
              pf(126) <= bu(rast_drops, 0); pf(127) <= bu(rast_drops, 1);
              -- 132..139 link block (ADR 0005 s3a)
              pf(132) <= bstat.rx_phase; pf(133) <= bstat.rx_eye;
              pf(134) <= bu(bstat.rx_hunts, 0); pf(135) <= bu(bstat.rx_hunts, 1);
              pf(136) <= bu(bstat.rx_bad, 0);   pf(137) <= bu(bstat.rx_bad, 1);
              pf(138) <= bstat.rx_flags;        pf(139) <= x"00";
              -- 140..151 memory block (ADR 0005 s3b, issue 0034)
              pf(140) <= "0000" & bstat.mem.st_pass & bstat.mem.st_done &
                         bstat.mem.st_running & bstat.mem.calibrated;
              pf(141) <= x"00";
              pf(142) <= bu(bstat.mem.errors, 0);   pf(143) <= bu(bstat.mem.errors, 1);
              pf(144) <= bstat.mem.dq_fail(15 downto 8); pf(145) <= bstat.mem.dq_fail(7 downto 0);
              pf(146) <= bu(bstat.mem.test_kib, 0); pf(147) <= bu(bstat.mem.test_kib, 1);
              for i in 0 to 3 loop pf(148 + i) <= b(bstat.mem.first_err, i); end loop;
              -- 152..159 shield block (ADR 0005 s3c, issue 0049)
              pf(152) <= bstat.shd.flags;    pf(153) <= bstat.shd.revision;
              pf(154) <= bstat.shd.features; pf(155) <= bstat.shd.sense;
              pf(156) <= bstat.shd.hdmi;     pf(157) <= bstat.shd.pwr;
              pf(158) <= bu(bstat.shd.errors, 0); pf(159) <= bu(bstat.shd.errors, 1);
              -- 160..187 relay block (ADR 0005 s3d, issue 0061)
              for i in 0 to 1 loop
                pf(160 + i) <= bu(bstat.relay.req_sent, i);
                pf(162 + i) <= bu(bstat.relay.req_full, i);
                pf(164 + i) <= bu(bstat.relay.rx_req, i);
                pf(166 + i) <= bu(bstat.relay.rx_lines, i);
                pf(168 + i) <= bu(bstat.relay.rx_bad, i);
                pf(170 + i) <= bu(bstat.relay.rx_ovf, i);
                pf(172 + i) <= bu(bstat.relay.rx_nosrc, i);
                pf(174 + i) <= bu(bstat.relay.rx_vlan, i);
                pf(176 + i) <= bu(bstat.relay.rx_long, i);
                pf(178 + i) <= bu(bstat.relay.rx_foreign, i);
                pf(180 + i) <= bu(bstat.relay.full_pics, i);
                pf(182 + i) <= bu(bstat.relay.full_swaps, i);
              end loop;
              pf(184) <= bstat.relay.flags;      pf(185) <= bstat.relay.last_m;
              pf(186) <= bstat.relay.last_scale; pf(187) <= bstat.relay.full_age;
              -- 188..195 relay receive load (relay-rx-speed)
              for i in 0 to 1 loop
                pf(188 + i) <= bu(bstat.relay.fifo_hwm, i);
                pf(190 + i) <= bu(bstat.relay.wr_stall, i);
                pf(192 + i) <= bu(bstat.relay.mem_wait, i);
              end loop;
              pf(194) <= std_logic_vector(bstat.relay.wf_hwm);
              pf(195) <= std_logic_vector(bstat.relay.fifo_aw);
            when others => null;
          end case;

          -- common custom header
          if kind /= K_ARP and kind /= K_ICMP and kind /= K_DHCP and kind /= K_THUMB and kind /= K_TREQ then
            pf(0) <= PROTO_MAGIC(15 downto 8); pf(1) <= PROTO_MAGIC(7 downto 0);
            pf(2) <= PROTO_VERSION; pf(3) <= typ;
            pf(4) <= bu(to_unsigned(plen, 16), 0); pf(5) <= bu(to_unsigned(plen, 16), 1);
            pf(6) <= std_logic_vector(to_unsigned(d, 8)); pf(7) <= x"00";
          end if;

          -- Ethernet header
          for i in 0 to 5 loop
            hdr(i)     <= b(dmac, i);
            hdr(6 + i) <= b(cfg(d).mac, i);
          end loop;
          if kind = K_ARP then
            hdr(12) <= x"08"; hdr(13) <= x"06";
            hdr(14) <= x"00"; hdr(15) <= x"01"; hdr(16) <= x"08"; hdr(17) <= x"00";
            hdr(18) <= x"06"; hdr(19) <= x"04"; hdr(20) <= x"00"; hdr(21) <= x"02";
            for i in 0 to 5 loop
              hdr(22 + i) <= b(cfg(d).mac, i);
              hdr(32 + i) <= b(arp.mac, i);
            end loop;
            for i in 0 to 3 loop
              hdr(28 + i) <= b(ip_eff(d), i);
              hdr(38 + i) <= b(arp.ip, i);
            end loop;
            a_len    <= to_unsigned(42, 13);
            b_len    <= (others => '0');
            c_len    <= (others => '0');
            total    <= to_unsigned(42, 13);
            state    <= S_START;
          elsif kind = K_THUMB or kind = K_TREQ then
            -- raw Ethernet: [802.1Q tag,] EtherType 0x88B5, version, subtype,
            -- magic, ... Inter-board frames (requests, frames to a requester)
            -- carry the VLAN tag when key 0x0043 is set (issue 0060); frames
            -- to the forced host MAC (key 0x0041) never do.
            if bcfg.vlan /= 0 and (kind = K_TREQ or th_pkt.tag = '1') then tgo := 4; else tgo := 0; end if;
            for i in 12 to 41 loop hdr(i) <= x"00"; end loop;
            if tgo = 4 then
              hdr(12) <= TH_TPID(15 downto 8); hdr(13) <= TH_TPID(7 downto 0);
              hdr(14) <= "0000" & std_logic_vector(bcfg.vlan(11 downto 8));     -- PCP 0, DEI 0
              hdr(15) <= std_logic_vector(bcfg.vlan(7 downto 0));
            end if;
            hdr(12 + tgo) <= TH_ETYPE(15 downto 8); hdr(13 + tgo) <= TH_ETYPE(7 downto 0);
            hdr(14 + tgo) <= TH_VERSION;
            hdr(16 + tgo) <= TH_MAGIC(15 downto 8); hdr(17 + tgo) <= TH_MAGIC(7 downto 0);
            c_len <= (others => '0');
            if kind = K_TREQ then
              hdr(15 + tgo) <= TH_SUB_REQ;
              hdr(18 + tgo) <= treq_scale; hdr(19 + tgo) <= treq_div;
              hdr(20 + tgo) <= treq_flags; hdr(21 + tgo) <= treq_target;
              a_len <= to_unsigned(14 + tgo + TH_REQ_LEN, 13);
              b_len <= (others => '0');
              total <= to_unsigned(14 + tgo + TH_REQ_LEN, 13);
            else
              hdr(15 + tgo) <= th_pkt.sub;
              hdr(18 + tgo) <= "000" & std_logic_vector(th_pkt.machine);
              hdr(19 + tgo) <= th_pkt.flags; hdr(20 + tgo) <= th_pkt.scale; hdr(21 + tgo) <= th_pkt.enc;
              for i in 0 to 3 loop hdr(22 + tgo + i) <= bu(th_pkt.frame, i); end loop;
              hdr(26 + tgo) <= x"00"; hdr(27 + tgo) <= std_logic_vector(th_pkt.row);
              hdr(28 + tgo) <= x"00"; hdr(29 + tgo) <= std_logic_vector(th_pkt.nlines);
              hdr(30 + tgo) <= bu(th_pkt.width, 0); hdr(31 + tgo) <= bu(th_pkt.width, 1);
              hdr(32 + tgo) <= x"00"; hdr(33 + tgo) <= std_logic_vector(th_pkt.height);
              hdr(34 + tgo) <= bu(resize(th_pkt.nbytes, 16), 0); hdr(35 + tgo) <= bu(resize(th_pkt.nbytes, 16), 1);
              a_len <= to_unsigned(14 + tgo + TH_HDR_LEN, 13);
              b_len <= th_pkt.nbytes;
              total <= to_unsigned(14 + tgo + TH_HDR_LEN, 13) + th_pkt.nbytes;
            end if;
            state <= S_START;
          else
            c_len <= (others => '0');
            if kind = K_ICMP then
              iplen := to_unsigned(20 + tl, 16);
              a_len <= to_unsigned(34, 13);
              b_len <= to_unsigned(tl, 13);
              total <= to_unsigned(34 + tl, 13);
            elsif kind = K_DHCP then
              iplen := to_unsigned(20 + 8 + tl, 16);
              a_len <= to_unsigned(42 + 44, 13);
              b_len <= to_unsigned(tl - 44 - 64, 13);
              c_len <= to_unsigned(64, 13);
              total <= to_unsigned(42 + tl, 13);
            else
              iplen := to_unsigned(20 + 8 + 8 + plen, 16);
              a_len <= to_unsigned(42 + 8 + plen - tl, 13);
              b_len <= to_unsigned(tl, 13);
              total <= to_unsigned(42 + 8 + plen, 13);
            end if;
            hdr(12) <= x"08"; hdr(13) <= x"00";
            hdr(14) <= x"45"; hdr(15) <= x"00";
            hdr(16) <= bu(iplen, 0); hdr(17) <= bu(iplen, 1);
            hdr(18) <= x"00"; hdr(19) <= x"00"; hdr(20) <= x"40"; hdr(21) <= x"00";
            hdr(22) <= x"40"; hdr(23) <= proto; hdr(24) <= x"00"; hdr(25) <= x"00";
            for i in 0 to 3 loop
              if kind = K_DHCP then
                hdr(26 + i) <= b(dq.ciaddr, i);        -- 0.0.0.0 unless renewing
              else
                hdr(26 + i) <= b(ip_eff(d), i);
              end if;
              hdr(30 + i) <= b(dip, i);
            end loop;
            hdr(34) <= bu(to_unsigned(sport, 16), 0); hdr(35) <= bu(to_unsigned(sport, 16), 1);
            hdr(36) <= dport(15 downto 8); hdr(37) <= dport(7 downto 0);
            hdr(38) <= bu(iplen - 20, 0); hdr(39) <= bu(iplen - 20, 1);
            hdr(40) <= x"00"; hdr(41) <= x"00";
            csum  <= (others => '0');
            cidx  <= 0;
            state <= S_CSUM;
          end if;

        when S_CSUM =>
          -- word select and add in separate cycles (timing, issue 0019)
          if cidx < 10 then
            cw <= unsigned(hdr(14 + 2 * cidx)) & unsigned(hdr(15 + 2 * cidx));
          end if;
          if cidx >= 1 and cidx <= 10 then
            csum <= ones_add(csum, cw);
          end if;
          if cidx = 11 then
            hdr(24) <= std_logic_vector(not csum(15 downto 8));
            hdr(25) <= std_logic_vector(not csum(7 downto 0));
            state     <= S_START;
          else
            cidx <= cidx + 1;
          end if;

        when S_START =>
          widx      <= (others => '0');
          tail_addr <= (others => '0');
          seg       <= SEG_A;
          cnt       <= a_len - 1;
          raddr     <= rast_desc.start;   -- raster pixel stream (K_RAST only)
          pr        <= 0;
          ph        <= 0;
          state     <= S_WRITE;

        when S_WRITE =>
          -- one byte per cycle (a build only starts when no frame is pending,
          -- so the MAC is reading the other slot or is idle). The tail
          -- memories have one cycle latency: tail_addr holds the index of the
          -- byte after the one being written.
          if seg = SEG_B then
            case kind is
              when K_SNAP =>
                if d = 0 then wb := hist_data0; else wb := hist_data1; end if;
              when K_JRESP =>
                case jtg is
                  when 0 => wb := j_tdo_data0;
                  when 1 => wb := j_tdo_data1;
                  when others => wb := j_tdo_data2;
                end case;
              when K_ICMP =>
                wb := icmp_rdata;       -- type/checksum already patched by net_rx
              when K_RAST =>
                wb := pix_sr(23 downto 16);
              when K_THUMB =>
                wb := th_rdata;           -- packet buffer, 1-cycle latency
              when others => wb := x"00";
            end case;
          else
            wb := hdr(0);
            for i in 0 to 40 loop hdr(i) <= hdr(i + 1); end loop;
            hdr(41) <= pf(0);
            for i in 0 to PF_MAX - 2 loop pf(i) <= pf(i + 1); end loop;
          end if;
          mem_we   <= '1';
          mem_addr <= bslot & widx(12 downto 0);
          -- raster pixel stream: ring word (1-cycle latency) primed during
          -- segment A, then shifted out R, G, B; the next word is already
          -- on rast_rdata when the third byte goes out
          if kind = K_RAST then
            if seg = SEG_B then
              if ph = 2 then
                pix_sr <= rast_rdata;
                raddr  <= raddr + 1;
                ph     <= 0;
              else
                pix_sr <= pix_sr(15 downto 0) & x"00";
                ph     <= ph + 1;
              end if;
            elsif pr = 0 then
              raddr <= raddr + 1;
              pr    <= 1;
            elsif pr = 1 then
              pix_sr <= rast_rdata;
              pr     <= 2;
            end if;
          end if;
          mem_data <= wb;
          widx     <= widx + 1;
          if seg = SEG_B or (seg = SEG_A and cnt = 0) then
            tail_addr <= tail_addr + 1;
          end if;
          if cnt /= 0 then
            cnt <= cnt - 1;
          elsif seg = SEG_A and b_len /= 0 then
            seg <= SEG_B; cnt <= b_len - 1;
          elsif seg /= SEG_C and c_len /= 0 then
            seg <= SEG_C; cnt <= c_len - 1;
          else
            if kind = K_ICMP then
              icmp_taken <= '1';
            end if;
            if kind = K_THUMB then
              th_taken <= '1';          -- copied: thumb_tx may refill its buffer
            end if;
            if kind = K_RAST then
              rast_pop <= '1';          -- frees the line; S_WAIT_MAC lets valid fall
              if rast_desc.flags(RF_FIRST) = '1' then
                rast_frames <= rast_frames + 1;
              end if;
              rast_drops <= rast_drops + rast_desc.drops;
            end if;
            state <= S_WAIT_MAC;
          end if;

        when S_WAIT_MAC =>
          if pend_valid = '0' then
            pend_valid <= '1';
            pend_slot  <= bslot;
            pend_len   <= total;
            bslot      <= not bslot;
            state      <= S_IDLE;
          end if;
      end case;
    end if;
  end process;
end architecture;
