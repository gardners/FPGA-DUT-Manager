-- net_rx: receive dispatcher (clk_sys).
--
-- Consumes frames from the two RX slots (alternately), reads the first
-- HDR_BYTES bytes into registers, validates Ethernet/ARP/IPv4/ICMP/UDP and
-- the custom header (ADR 0005), then:
--   ARP request for an endpoint IP  -> ARP reply request to net_tx
--   ICMP echo (<= 64 data bytes)    -> echo reply request (data copied)
--   UDP 6500 MGMT_SET               -> apply config, MGMT_ACK request
--   UDP 6502 KBD_SET                -> kbd_udp(dut)
--   UDP 6503 UART_TX                -> uart_bridge admission + byte copy
--   UDP 6507 JTAG_REQ               -> jtag_engine admission + vector copy
-- Owns all host-writable configuration registers.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.proto_pkg.all;
use work.net_pkg.all;

entity net_rx is
  port (
    clk        : in  std_logic;
    dut_id0    : in  unsigned(4 downto 0);   -- '0' & DIP[3:0] (ADR 0011, issue 0026)
    dut_id1    : in  unsigned(4 downto 0);   -- '1' & DIP[7:4]
    ep_enable  : in  std_logic_vector(1 downto 0);
    ip_eff     : in  ip_arr_t;               -- effective address (DHCP/fallback/static)
    dna        : in  std_logic_vector(63 downto 0);
    -- RX slots
    rx_toggle  : in  std_logic_vector(1 downto 0);   -- async from clk_rx
    rel_toggle : out std_logic_vector(1 downto 0);
    len0, len1 : in  unsigned(11 downto 0);
    mem_addr   : out unsigned(11 downto 0);
    mem_data   : in  std_logic_vector(7 downto 0);
    -- configuration
    cfg        : out dut_cfg_arr_t;
    bcfg       : out board_cfg_t;
    -- keyboard
    kbd_udp    : out kbd_arr_t;
    kbd_strobe : out std_logic_vector(1 downto 0);
    -- UART bridges
    adm_valid  : out std_logic_vector(1 downto 0);
    adm_offset : out unsigned(31 downto 0);
    adm_count  : out unsigned(15 downto 0);
    adm_clear  : out std_logic;
    adm_cmd_id : out unsigned(15 downto 0);
    adm_done   : in  std_logic_vector(1 downto 0);
    adm_ok     : in  std_logic_vector(1 downto 0);
    uwr_valid  : out std_logic_vector(1 downto 0);
    uwr_data   : out std_logic_vector(7 downto 0);
    -- JTAG engines
    jreq_valid : out std_logic_vector(1 downto 0);
    jreq_seq   : out unsigned(31 downto 0);
    jreq_bits  : out unsigned(31 downto 0);
    jreq_half  : out unsigned(31 downto 0);
    jreq_abort : out std_logic;
    jdec_valid : in  std_logic_vector(1 downto 0);
    jdec_code0 : in  unsigned(2 downto 0);
    jdec_code1 : in  unsigned(2 downto 0);
    jvec_we    : out std_logic_vector(1 downto 0);
    jvec_addr  : out unsigned(10 downto 0);
    jvec_data  : out std_logic_vector(7 downto 0);
    jgo        : out std_logic_vector(1 downto 0);
    jdone      : in  std_logic_vector(1 downto 0);
    jaborted   : in  std_logic_vector(1 downto 0);
    -- reply requests to net_tx
    arp        : out reply_t;
    arp_tpa_o  : out ip_t;                 -- unused by tx (requester ip in arp.ip)
    arp_taken  : in  std_logic;
    icmp       : out reply_t;
    icmp_len   : out unsigned(6 downto 0); -- ICMP bytes (hdr + data), 8..72
    icmp_raddr : in  unsigned(6 downto 0);
    icmp_rdata : out std_logic_vector(7 downto 0);
    icmp_taken : in  std_logic;
    ack        : out reply_t;
    ack_cmd    : out std_logic_vector(15 downto 0);
    ack_key    : out std_logic_vector(15 downto 0);
    ack_status : out std_logic_vector(7 downto 0);
    ack_taken  : in  std_logic;
    jr         : out reply_arr_t;
    jr_status  : out slv8_arr_t;
    jr_seq     : out u32_arr_t;
    jr_taken   : in  std_logic_vector(1 downto 0);
    -- DHCP replies for dhcp_client
    dhcp_strobe: out std_logic_vector(1 downto 0);
    dhcp_rx    : out dhcp_rx_t;
    -- statistics
    rx_rejects : out u16_arr_t
  );
end entity;

architecture rtl of net_rx is
  constant HDR_BYTES : natural := 112;
  type hdr_t is array (0 to HDR_BYTES - 1) of byte_t;
  signal h : hdr_t := (others => (others => '0'));

  type state_t is (S_WAIT, S_HDR, S_CSUM, S_PRE, S_PARSE, S_ARP, S_ICMP, S_MGMT,
                   S_KBD, S_UART_ADM, S_UART_WAIT, S_UART_COPY,
                   S_JTAG_ADM, S_JTAG_WAIT, S_JTAG_COPY, S_JTAG_GO, S_JTAG_REPLY,
                   S_DHCP_RD, S_DHCP_WAIT, S_DHCP_BYTE, S_DHCP_DONE,
                   S_RELEASE);
  signal state : state_t := S_WAIT;

  signal rxs1, rxs2, rel : std_logic_vector(1 downto 0) := "00";
  signal cur     : std_logic := '0';
  signal flen    : unsigned(11 downto 0) := (others => '0');
  signal ra, ca  : unsigned(11 downto 0) := (others => '0');
  signal rd_on   : std_logic := '0';
  signal csum    : unsigned(15 downto 0) := (others => '0');
  signal cidx    : integer range 0 to 11 := 0;
  signal cw      : unsigned(15 downto 0) := (others => '0');  -- checksum word (pipelined)
  signal d       : integer range 0 to 1 := 0;

  signal cfg_r   : dut_cfg_arr_t := (default_cfg(x"0"), default_cfg(x"1"));
  signal ids_seen: unsigned(9 downto 0) := (others => '1');
  signal cfg_init: std_logic := '0';
  signal bcfg_r  : board_cfg_t := (x"FF", x"FF", '1', "00", (others => '0'), x"00", (others => '0'), x"00");
  signal last_cmd: u16_arr_t := (others => (others => '0'));
  signal last_cmd_v : std_logic_vector(1 downto 0) := "00";

  signal arp_r, icmp_r, ack_r : reply_t := REPLY_NONE;
  signal jr_r    : reply_arr_t := (REPLY_NONE, REPLY_NONE);
  signal jrst_r  : slv8_arr_t := (others => x"00");
  signal jrseq_r : u32_arr_t := (others => (others => '0'));
  type icmp_buf_t is array (0 to 71) of byte_t;
  signal icmp_buf : icmp_buf_t := (others => (others => '0'));
  signal icmp_len_r : unsigned(6 downto 0) := (others => '0');
  signal ack_cmd_r, ack_key_r : std_logic_vector(15 downto 0) := (others => '0');
  signal ack_st_r : std_logic_vector(7 downto 0) := (others => '0');
  signal rej     : u16_arr_t := (others => (others => '0'));
  signal kbd_r   : kbd_arr_t := (others => (others => '0'));

  -- S_PRE -> S_PARSE: header classification registered in one cycle so the
  -- decision in S_PARSE only combines flags (issue 0019, timing)
  signal f_arp, f_ipv4, f_trunc, f_dhcp, f_bcast, f_icmp_echo : boolean := false;
  signal f_arp_ip, f_ip_dst, f_dhcp_mac, f_dut_ok : std_logic_vector(1 downto 0) := "00";
  signal f_udp, f_udp_bad, f_identity, f_mgmt, f_kbd, f_uart, f_jtag, f_text : boolean := false;
  signal f_dut_ff : std_logic := '0';
  signal f_jbad   : boolean := false;                    -- JTAG request malformed
  signal j_nb_r   : unsigned(31 downto 0) := (others => '0');
  signal j_bits_r : unsigned(31 downto 0) := (others => '0');

  -- DHCP option scan
  type opt_st_t is (O_CODE, O_LEN, O_VAL);
  signal opt_st  : opt_st_t := O_CODE;
  signal opt_code: byte_t := (others => '0');
  signal opt_left: unsigned(7 downto 0) := (others => '0');
  signal dhcp_r  : dhcp_rx_t := (x"00", (others => '0'), (others => '0'), (others => '0'),
                                  (others => '0'), (others => '0'));

  -- copy engine
  signal cp_src, cp_end : unsigned(11 downto 0) := (others => '0');
  signal cp_dst  : unsigned(10 downto 0) := (others => '0');
  signal cp_n    : unsigned(11 downto 0) := (others => '0');
  signal cp_phase: std_logic := '0';  -- JTAG: 0 = TMS, 1 = TDI
  signal j_nbytes: unsigned(11 downto 0) := (others => '0');
  signal j_seq   : unsigned(31 downto 0) := (others => '0');

  function be16(hh : hdr_t; o : natural) return unsigned is
  begin
    return unsigned(hh(o)) & unsigned(hh(o + 1));
  end function;
  function be32(hh : hdr_t; o : natural) return unsigned is
  begin
    return be16(hh, o) & be16(hh, o + 2);
  end function;
  function slv48(hh : hdr_t; o : natural) return std_logic_vector is
  begin
    return hh(o) & hh(o + 1) & hh(o + 2) & hh(o + 3) & hh(o + 4) & hh(o + 5);
  end function;
  function slv32(hh : hdr_t; o : natural) return std_logic_vector is
  begin
    return hh(o) & hh(o + 1) & hh(o + 2) & hh(o + 3);
  end function;
begin
  rel_toggle <= rel;
  cfg        <= cfg_r;
  bcfg       <= bcfg_r;
  kbd_udp    <= kbd_r;
  arp        <= arp_r;
  arp_tpa_o  <= (others => '0');
  icmp       <= icmp_r;
  dhcp_rx    <= dhcp_r;
  icmp_len   <= icmp_len_r;
  ack        <= ack_r;
  ack_cmd    <= ack_cmd_r;
  ack_key    <= ack_key_r;
  ack_status <= ack_st_r;
  jr         <= jr_r;
  jr_status  <= jrst_r;
  jr_seq     <= jrseq_r;
  rx_rejects <= rej;
  mem_addr   <= ra;

  -- registered read port (1-cycle latency like the other tail memories)
  process (clk)
  begin
    if rising_edge(clk) then
      if icmp_raddr < 72 then
        icmp_rdata <= icmp_buf(to_integer(icmp_raddr));
      else
        icmp_rdata <= x"00";
      end if;
    end if;
  end process;

  process (clk)
    variable typ      : std_logic_vector(7 downto 0);
    variable dport    : natural;
    variable ip_total : unsigned(15 downto 0);
    variable udp_len  : unsigned(15 downto 0);
    variable plen     : unsigned(15 downto 0);   -- custom payload length
    variable dd       : integer range 0 to 1;
    variable matched  : boolean;
    variable bcast    : boolean;
    variable key      : natural;
    variable vlen     : unsigned(15 downto 0);
    variable st       : std_logic_vector(7 downto 0);
    variable code     : unsigned(2 downto 0);
    variable bits     : unsigned(31 downto 0);
    variable nb       : unsigned(31 downto 0);
    variable dhcp_hit : boolean;
    variable ob       : byte_t;

  begin
    if rising_edge(clk) then
      rxs1 <= rx_toggle;
      rxs2 <= rxs1;
      kbd_strobe <= "00";
      adm_valid  <= "00";
      uwr_valid  <= "00";
      jreq_valid <= "00";
      jvec_we    <= "00";
      jgo        <= "00";

      dhcp_strobe <= "00";
      -- (re)initialise per-endpoint defaults whenever the DIP DUT IDs change
      if cfg_init = '0' or ids_seen /= (dut_id1 & dut_id0) then
        cfg_init   <= '1';
        ids_seen   <= dut_id1 & dut_id0;
        cfg_r(0)   <= default_cfg(dut_id0);
        cfg_r(1)   <= default_cfg(dut_id1);
        last_cmd_v <= "00";
      end if;

      -- consumers taking replies
      if arp_taken = '1' then arp_r.pend <= '0'; end if;
      if icmp_taken = '1' then icmp_r.pend <= '0'; end if;
      if ack_taken = '1' then ack_r.pend <= '0'; end if;
      for i in 0 to 1 loop
        if jr_taken(i) = '1' then jr_r(i).pend <= '0'; end if;
        -- engine completion -> response
        if jdone(i) = '1' then
          jr_r(i).pend <= '1';
          if jaborted(i) = '1' then
            jrst_r(i) <= JS_UNPOWERED;
          else
            jrst_r(i) <= JS_DONE;
          end if;
        end if;
      end loop;

      -- header read pipeline: data for address presented at cycle n is
      -- valid at n+1
      rd_on <= '0';
      if rd_on = '1' and ca < HDR_BYTES then
        h(to_integer(ca)) <= mem_data;
        ca <= ca + 1;
      end if;

      case state is
        when S_WAIT =>
          if (cur = '0' and rxs2(0) /= rel(0)) or (cur = '1' and rxs2(1) /= rel(1)) then
            if cur = '0' then flen <= len0; else flen <= len1; end if;
            ra    <= cur & "00000000000";
            ca    <= (others => '0');
            h     <= (others => (others => '0'));
            state <= S_HDR;
          end if;

        when S_HDR =>
          if ra(10 downto 0) < HDR_BYTES and ra(10 downto 0) < flen then
            rd_on <= '1';
            ra    <= ra + 1;
          elsif rd_on = '0' then
            csum  <= (others => '0');
            cidx  <= 0;
            state <= S_CSUM;
          end if;

        when S_CSUM =>
          -- IPv4 header checksum over bytes 14..33; word select and add in
          -- separate cycles (timing, issue 0019)
          if cidx < 10 then
            cw <= be16(h, 14 + 2 * cidx);
          end if;
          if cidx >= 1 then
            csum <= ones_add(csum, cw);
          end if;
          if cidx = 10 then
            state <= S_PRE;
          else
            cidx <= cidx + 1;
          end if;

        when S_PRE =>
          state <= S_PARSE;
          ip_total := be16(h, 16);
          udp_len  := be16(h, 38);
          typ      := h(45);
          dport    := to_integer(be16(h, 36));
          plen     := be16(h, 46);
          f_arp <= h(12) = x"08" and h(13) = x"06" and be16(h, 14) = 1 and
                   be16(h, 16) = 16#0800# and h(18) = x"06" and h(19) = x"04" and
                   be16(h, 20) = 1;
          f_ipv4 <= h(12) = x"08" and h(13) = x"00" and h(14) = x"45" and csum = x"FFFF"
                    and (h(20) and x"3F") = x"00" and h(21) = x"00";
          for i in 0 to 1 loop
            f_arp_ip(i) <= '0'; f_ip_dst(i) <= '0'; f_dhcp_mac(i) <= '0'; f_dut_ok(i) <= '0';
            if slv32(h, 38) = ip_eff(i) and ep_enable(i) = '1' and ip_eff(i) /= x"00000000" then
              f_arp_ip(i) <= '1';
            end if;
            if slv32(h, 30) = ip_eff(i) and slv48(h, 0) = cfg_r(i).mac and
               ep_enable(i) = '1' and ip_eff(i) /= x"00000000" then
              f_ip_dst(i) <= '1';
            end if;
            if slv48(h, 70) = cfg_r(i).mac and ep_enable(i) = '1' and cfg_r(i).dhcp_en = '1' and
               (slv48(h, 0) = cfg_r(i).mac or slv48(h, 0) = x"FFFFFFFFFFFF") then
              f_dhcp_mac(i) <= '1';
            end if;
            if unsigned(h(48)) = i or h(48) = x"FF" then
              f_dut_ok(i) <= '1';
            end if;
          end loop;
          f_dut_ff <= h(48)(0);
          f_dhcp  <= h(23) = x"11" and be16(h, 34) = PORT_DHCP_S and be16(h, 36) = PORT_DHCP_C and
                     h(42) = x"02";
          f_bcast <= slv32(h, 30) = x"FFFFFFFF" and slv48(h, 0) = x"FFFFFFFFFFFF";
          f_trunc <= ip_total + 14 > flen or ip_total < 28;
          f_icmp_echo <= h(34) = x"08" and h(35) = x"00" and ip_total <= 20 + 72;
          f_udp <= h(23) = x"11";
          f_udp_bad <= udp_len /= ip_total - 20 or udp_len < 16 or
                       be16(h, 42) /= unsigned(PROTO_MAGIC) or h(44) /= PROTO_VERSION or
                       plen /= udp_len - 16;
          f_identity <= dport = PORT_MGMT and typ = T_MGMT_SET and be16(h, 52) = K_IDENTITY
                        and be16(h, 54) = 18 and slv48(h, 56) & h(62) & h(63) = dna;
          f_mgmt <= dport = PORT_MGMT and typ = T_MGMT_SET and plen >= 6 and
                    be16(h, 54) = plen - 6 and plen <= 6 + 18;
          f_kbd  <= dport = PORT_KBD and typ = T_KBD_SET and plen = KBD_PAYLOAD_LEN;
          f_uart <= dport = PORT_UART and typ = T_UART_TX and plen >= UART_TX_FIXED and
                    be16(h, 58) = plen - UART_TX_FIXED and be16(h, 58) <= UART_TX_MAX;
          f_jtag <= dport = PORT_JTAG and typ = T_JTAG_REQ and plen >= JTAG_REQ_FIXED;
          f_text <= dport = PORT_TEXT;
          -- JTAG request geometry (used by S_JTAG_ADM)
          bits := be32(h, 62);
          nb   := shift_right(bits + 7, 3);
          j_bits_r <= bits;
          j_nb_r   <= nb;
          f_jbad   <= bits = 0 or bits > JTAG_MAX_BITS or
                      resize(be16(h, 46), 32) /= JTAG_REQ_FIXED + 2 * nb;

        when S_PARSE =>
          state <= S_RELEASE;
          matched := false;
          bcast   := false;
          dd      := 0;
          if f_arp then
            -- ARP request (Ethernet/IPv4) for one of our addresses?
            for i in 0 to 1 loop
              if f_arp_ip(i) = '1' then
                matched := true; dd := i;
              end if;
            end loop;
            if matched then
              d <= dd;
              state <= S_ARP;
            end if;
          elsif f_ipv4 then
            for i in 0 to 1 loop
              if f_ip_dst(i) = '1' then
                matched := true; dd := i;
              end if;
            end loop;
            -- DHCP replies (UDP 67 -> 68): match on chaddr, any dst IP
            dhcp_hit := false;
            if f_dhcp then
              for i in 0 to 1 loop
                if f_dhcp_mac(i) = '1' then
                  dhcp_hit := true; dd := i;
                end if;
              end loop;
            end if;
            if f_bcast and not dhcp_hit then
              bcast := true;
              if f_dut_ff = '1' then dd := 1; else dd := 0; end if;
            end if;
            d <= dd;
            if f_trunc then
              null;                     -- truncated
            elsif dhcp_hit then
              dhcp_r.xid    <= slv32(h, 46);
              dhcp_r.yiaddr <= slv32(h, 58);
              dhcp_r.typ    <= x"00";
              dhcp_r.server <= (others => '0');
              dhcp_r.lease  <= (others => '0');
              dhcp_r.t1     <= (others => '0');
              -- magic cookie at UDP payload 236 = frame 278; options at 282
              ra     <= cur & to_unsigned(282, 11);
              opt_st <= O_CODE;
              state  <= S_DHCP_RD;
            elsif matched and h(23) = x"01" then
              -- ICMP echo request
              if f_icmp_echo then
                state <= S_ICMP;
              end if;
            elsif (matched or bcast) and f_udp then
              if f_udp_bad or f_dut_ok(dd) = '0' then
                rej(dd) <= rej(dd) + 1;
              elsif bcast then
                -- only SET_IDENTITY is accepted on broadcast
                if f_identity then
                  state <= S_MGMT;
                end if;
              elsif f_mgmt then
                state <= S_MGMT;
              elsif f_kbd then
                state <= S_KBD;
              elsif f_uart then
                state <= S_UART_ADM;
              elsif f_jtag then
                state <= S_JTAG_ADM;
              elsif f_text then
                null;                   -- written at line rate by text_rx_tap
              else
                rej(dd) <= rej(dd) + 1;
              end if;
            end if;
          end if;

        when S_ARP =>
          if arp_r.pend = '0' then
            arp_r <= ('1', d, slv48(h, 22), slv32(h, 28), (others => '0'));
            state <= S_RELEASE;
          end if;

        when S_ICMP =>
          if icmp_r.pend = '0' then
            icmp_r <= ('1', d, slv48(h, 6), slv32(h, 26), (others => '0'));
            icmp_len_r <= resize(be16(h, 16) - 20, 7);
            for i in 0 to 71 loop
              icmp_buf(i) <= h(34 + i);
            end loop;
            -- echo reply: type 8 -> 0, checksum += 0x0800 (RFC 1624)
            icmp_buf(0) <= x"00";
            icmp_buf(2) <= std_logic_vector(ones_add(be16(h, 36), x"0800")(15 downto 8));
            icmp_buf(3) <= std_logic_vector(ones_add(be16(h, 36), x"0800")(7 downto 0));
            state <= S_RELEASE;
          end if;

        when S_MGMT =>
          if ack_r.pend = '0' then
            key  := to_integer(be16(h, 52));
            vlen := be16(h, 54);
            st   := ST_OK;
            if last_cmd_v(d) = '1' and last_cmd(d) = be16(h, 50) and key /= K_IDENTITY then
              st := ST_DUPLICATE;
            else
              case key is
                when K_MAC =>
                  if vlen = 6 then cfg_r(d).mac <= slv48(h, 56); else st := ST_BAD_LEN; end if;
                when K_IP =>
                  -- a static address also stops DHCP for this endpoint
                  if vlen = 4 then cfg_r(d).ip <= slv32(h, 56); cfg_r(d).dhcp_en <= '0';
                  else st := ST_BAD_LEN; end if;
                when K_DHCP_EN =>
                  if vlen = 1 then cfg_r(d).dhcp_en <= h(56)(0); else st := ST_BAD_LEN; end if;
                when K_DEST_IP =>
                  if vlen = 4 then cfg_r(d).dest_ip <= slv32(h, 56); else st := ST_BAD_LEN; end if;
                when K_DEST_MAC =>
                  if vlen = 6 then cfg_r(d).dest_mac <= slv48(h, 56); else st := ST_BAD_LEN; end if;
                when K_IDENTITY =>
                  if vlen = 18 then
                    cfg_r(d).mac <= slv48(h, 64);
                    cfg_r(d).ip  <= slv32(h, 70);
                    cfg_r(d).dhcp_en <= '0';
                  else
                    st := ST_BAD_LEN;
                  end if;
                when K_UART_BAUD =>
                  if vlen = 4 then cfg_r(d).baud_inc <= be32(h, 56); else st := ST_BAD_LEN; end if;
                when K_UART_FAST =>
                  if vlen = 1 then cfg_r(d).uart_fast <= h(56)(0); else st := ST_BAD_LEN; end if;
                when K_UART_SNAP_EN =>
                  if vlen = 1 then cfg_r(d).uart_snap_en <= h(56)(0); else st := ST_BAD_LEN; end if;
                when K_UART_PERIOD =>
                  if vlen = 2 and be16(h, 56) >= 100 then cfg_r(d).uart_period <= be16(h, 56);
                  elsif vlen = 2 then st := ST_BAD_VALUE; else st := ST_BAD_LEN; end if;
                when K_KBD_POLICY =>
                  if vlen = 1 and unsigned(h(56)) <= 1 then cfg_r(d).kbd_policy <= h(56);
                  else st := ST_BAD_VALUE; end if;
                when K_KBD_OVERRIDE =>
                  if vlen = 1 and unsigned(h(56)) <= 3 then cfg_r(d).kbd_override <= h(56);
                  else st := ST_BAD_VALUE; end if;
                when K_KBD_TARGET =>
                  if vlen = 1 then bcfg_r.kbd_target <= h(56); else st := ST_BAD_LEN; end if;
                when K_VID_TARGET =>
                  if vlen = 1 then bcfg_r.vid_target <= h(56); else st := ST_BAD_LEN; end if;
                when K_COUPLED =>
                  if vlen = 1 then bcfg_r.coupled <= h(56)(0); else st := ST_BAD_LEN; end if;
                when K_PK_LED_MODE =>
                  if vlen = 1 and unsigned(h(56)) <= 2 then bcfg_r.pk_led_mode <= h(56);
                  elsif vlen = 1 then st := ST_BAD_VALUE; else st := ST_BAD_LEN; end if;
                when K_CON_SCREEN =>
                  if vlen = 1 and unsigned(h(56)) <= 3 then bcfg_r.con_screen <= h(56);
                  elsif vlen = 1 then st := ST_BAD_VALUE; else st := ST_BAD_LEN; end if;
                when K_PK_LED_HOST =>
                  if vlen = 12 then
                    for i in 0 to 11 loop
                      bcfg_r.pk_led_host(8 * i + 7 downto 8 * i) <= h(56 + i);
                    end loop;
                  else st := ST_BAD_LEN; end if;
                when K_CAPTURE_EN =>
                  if vlen = 1 then bcfg_r.capture_en(d) <= h(56)(0); else st := ST_BAD_LEN; end if;
                when K_HB_PERIOD =>
                  if vlen = 2 and be16(h, 56) >= 1 then cfg_r(d).hb_period_ms <= be16(h, 56);
                  else st := ST_BAD_VALUE; end if;
                when K_OUT_POLICY =>
                  if vlen = 1 and unsigned(h(56)) <= 2 then cfg_r(d).out_policy <= h(56);
                  else st := ST_BAD_VALUE; end if;
                when others =>
                  st := ST_BAD_KEY;
              end case;
              last_cmd(d)   <= be16(h, 50);
              last_cmd_v(d) <= '1';
              if st = ST_OK then
                bcfg_r.cfg_gen <= bcfg_r.cfg_gen + 1;
              end if;
            end if;
            ack_r     <= ('1', d, slv48(h, 6), slv32(h, 26), h(34) & h(35));
            ack_cmd_r <= h(50) & h(51);
            ack_key_r <= h(52) & h(53);
            ack_st_r  <= st;
            state     <= S_RELEASE;
          end if;

        when S_KBD =>
          for i in 0 to 9 loop
            kbd_r(d)(8 * i + 7 downto 8 * i) <= h(50 + i);
          end loop;
          kbd_strobe(d) <= '1';
          state <= S_RELEASE;

        -- UART: offset 50, cmd_id 54, flags 56, count 58, data 60.. ------
        when S_UART_ADM =>
          adm_valid(d) <= '1';
          adm_offset   <= be32(h, 50);
          adm_cmd_id   <= be16(h, 54);
          adm_clear    <= h(56)(0);
          adm_count    <= be16(h, 58);
          state        <= S_UART_WAIT;

        when S_UART_WAIT =>
          if adm_done(d) = '1' then
            if adm_ok(d) = '1' and be16(h, 58) /= 0 then
              cp_src <= to_unsigned(60, 12);
              cp_end <= to_unsigned(60, 12) + resize(be16(h, 58), 12);
              ra     <= cur & to_unsigned(60, 11);
              cp_n   <= (others => '0');
              rd_on  <= '0';
              state  <= S_UART_COPY;
            else
              state <= S_RELEASE;
            end if;
          end if;

        when S_UART_COPY =>
          -- address issue: ra runs ahead by one
          if ra(10 downto 0) < cp_end(10 downto 0) then
            ra <= ra + 1;
          end if;
          if cp_n /= 0 then
            uwr_valid(d) <= '1';
            uwr_data     <= mem_data;
          end if;
          if cp_n = cp_end - cp_src then
            state <= S_RELEASE;
          else
            cp_n <= cp_n + 1;
          end if;

        -- JTAG: seq 50, half 54, report 58, flags 60, bits 62, vectors 66.. --
        when S_JTAG_ADM =>
          bits := j_bits_r;
          nb   := j_nb_r;
          j_seq <= be32(h, 50);
          if jr_r(d).pend = '1' then
            null;                       -- wait for previous response to go
          elsif f_jbad then
            -- malformed: answer without involving the engine
            jr_r(d)    <= ('1', d, slv48(h, 6), slv32(h, 26), h(34) & h(35));
            jrst_r(d)  <= JS_BAD_FMT;
            jrseq_r(d) <= be32(h, 50);
            rej(d)     <= rej(d) + 1;
            state      <= S_RELEASE;
          else
            j_nbytes      <= resize(nb, 12);
            jreq_valid(d) <= '1';
            jreq_seq      <= be32(h, 50);
            jreq_half     <= be32(h, 54);
            jreq_abort    <= h(61)(0);
            jreq_bits     <= bits;
            state         <= S_JTAG_WAIT;
          end if;

        when S_JTAG_WAIT =>
          if jdec_valid(d) = '1' then
            if d = 0 then code := jdec_code0; else code := jdec_code1; end if;
            jr_r(d).dut    <= d;
            jr_r(d).mac    <= slv48(h, 6);
            jr_r(d).ip     <= slv32(h, 26);
            jr_r(d).port_n <= h(34) & h(35);
            jrseq_r(d)     <= j_seq;
            case code is
              when "000" =>              -- accepted: copy vectors
                ra       <= cur & to_unsigned(66, 11);
                cp_src   <= to_unsigned(66, 12);
                cp_end   <= to_unsigned(66, 12) + (j_nbytes(10 downto 0) & '0');
                cp_n     <= (others => '0');
                cp_dst   <= (others => '0');
                state    <= S_JTAG_COPY;
              when "001" => jrst_r(d) <= JS_DONE;      jr_r(d).pend <= '1'; state <= S_RELEASE;
              when "010" => jrst_r(d) <= JS_BUSY;      jr_r(d).pend <= '1'; state <= S_RELEASE;
              when "011" => jrst_r(d) <= JS_BAD_SEQ;   jr_r(d).pend <= '1'; state <= S_RELEASE;
              when "100" => jrst_r(d) <= JS_BAD_FMT;   jr_r(d).pend <= '1'; state <= S_RELEASE;
              when others => jrst_r(d) <= JS_UNPOWERED; jr_r(d).pend <= '1'; state <= S_RELEASE;
            end case;
          end if;

        when S_JTAG_COPY =>
          if ra(10 downto 0) < cp_end(10 downto 0) then
            ra <= ra + 1;
          end if;
          if cp_n /= 0 then
            jvec_we(d) <= '1';
            jvec_data  <= mem_data;
            if cp_n - 1 < j_nbytes then
              jvec_addr <= resize(cp_n - 1, 11);                    -- TMS
            else
              jvec_addr <= to_unsigned(1024, 11) + resize(cp_n - 1 - j_nbytes, 11); -- TDI
            end if;
          end if;
          if cp_n = cp_end - cp_src then
            state <= S_JTAG_GO;
          else
            cp_n <= cp_n + 1;
          end if;

        when S_JTAG_GO =>
          jgo(d) <= '1';
          state  <= S_RELEASE;

        when S_JTAG_REPLY =>
          state <= S_RELEASE;

        -- DHCP option scan: one byte per two cycles (address, then data) --
        when S_DHCP_RD =>
          if ra(10 downto 0) >= flen then
            state <= S_DHCP_DONE;
          else
            state <= S_DHCP_WAIT;
          end if;
        when S_DHCP_WAIT =>
          state <= S_DHCP_BYTE;          -- RAM latency
        when S_DHCP_BYTE =>
          ob := mem_data;
          ra <= ra + 1;
          state <= S_DHCP_RD;
          case opt_st is
            when O_CODE =>
              if ob = x"FF" then
                state <= S_DHCP_DONE;
              elsif ob /= x"00" then
                opt_code <= ob;
                opt_st   <= O_LEN;
              end if;
            when O_LEN =>
              opt_left <= unsigned(ob);
              if ob = x"00" then opt_st <= O_CODE; else opt_st <= O_VAL; end if;
            when O_VAL =>
              case opt_code is
                when x"35" => dhcp_r.typ <= ob;                                  -- 53
                when x"36" => dhcp_r.server <= dhcp_r.server(23 downto 0) & ob; -- 54
                when x"33" => dhcp_r.lease  <= dhcp_r.lease(23 downto 0) & unsigned(ob);  -- 51
                when x"3A" => dhcp_r.t1     <= dhcp_r.t1(23 downto 0) & unsigned(ob);     -- 58
                when others => null;
              end case;
              if opt_left = 1 then opt_st <= O_CODE; end if;
              opt_left <= opt_left - 1;
          end case;
        when S_DHCP_DONE =>
          dhcp_strobe(d) <= '1';
          state <= S_RELEASE;

        when S_RELEASE =>
          rel(to_integer(unsigned'('0' & cur))) <= not rel(to_integer(unsigned'('0' & cur)));
          cur   <= not cur;
          state <= S_WAIT;
      end case;
    end if;
  end process;
end architecture;
