"""Generate input frames for tb_supervisor_core and check its captured output.

  python3 -I tests/scenarios/tb_supervisor_core.py gen   <out.txt>
  python3 -I tests/scenarios/tb_supervisor_core.py check <captured.txt>

Input file format, one frame per line: "<delay_us> <len> <hex byte> ..."
(frames include FCS; the testbench adds preamble/SFD).
"""
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import netproto as P  # noqa: E402

HOST_MAC = P.mac("02:00:00:00:00:01")
HOST_IP = P.ip("192.168.65.1")
BCAST = b"\xff" * 6
# DIP = 0x10: DUT0 (P12 half) has DUT ID 0x00, DUT1 (P13 half) DUT ID 0x11
# (0x1m, issue 0026).
# DUT0 gets a DHCP lease; DUT1 gets no reply and falls back (ADR 0011).
DNA = 0x0123456789ABCDEF
DUT_MAC = [bytes([0x02, 0x4D, 0x36, 0x35, 0x00, d]) for d in (0x00, 0x11)]
LEASE_IP = P.ip("10.65.0.50")
SERVER_IP = P.ip("10.65.0.1")
SERVER_MAC = P.mac("02:00:00:00:00:fe")
DUT_IP = [LEASE_IP, P.ip("192.168.65.33")]   # 16 + 0x11
XID = [0x4D363501, 0x4D363512]   # xid_base (4D3635 & id) + 1
IDCODE = 0x0362C093
KBD_IDCODE = 0x012BA043   # the keyboard CPLD's TAP model (LCMXO2-1200HC)
BAUD_12M5 = 429496730
# JTAG: TLR x5, RTI, SELDR, CAPDR, SHDR (9 nav bits) then 32 bits, last exits
JTAG_TMS = "11111" + "0100" + "0" * 31 + "1"
JTAG_TDI = "0" * len(JTAG_TMS)
# HDMI IN test source in the testbench (video_timing): 720 x 8 of 858 x 12,
# HSYNC at pixels 736..797, negative syncs
V_HA, V_VA, V_HT, V_VT, V_HS0, V_HS1 = 720, 8, 858, 12, 736, 798
K_CAPTURE_EN = 0x0040
K_THUMB_FORCE = 0x0041
PEER_MAC = P.mac("02:4D:36:35:00:22")
PEER_TILE = [bytes((x * 3 + y) & 255 for x in range(480)) for y in range(4)]
VLAN = P.VLAN_DEFAULT          # inter-board relay traffic (issue 0060)
# 1/1 picture of machine 3 (DUT1's slot) from a board without HDMI (issue 0060)
LONG_LINE = bytes((x * 7 + 3) & 255 for x in range(3 * 720))
FULL_PIC = [bytes((x * 5 + 7 * y) & 255 for x in range(3 * 64)) for y in range(8)]
# thumbnail of the testbench picture: centre 640 columns (x offset 40), all
# 8 lines (shorter than 400), 2x2 boxes -> 320 x 4
THUMB_TILE = P.thumb_box(lambda x, y: (x & 255, y & 255, (7 * x + 31 * y + 5) & 255), 40, 0, 2, 320, 4)


def pattern_line(y):
    return b"".join(bytes([x & 0xFF, y & 0xFF, (7 * x + 31 * y + 5) & 0xFF]) for x in range(V_HA))


def udp_to(dut, dport, payload, sport=40000):
    return P.with_fcs(P.eth(DUT_MAC[dut], HOST_MAC, 0x0800,
                            P.ipv4(HOST_IP, DUT_IP[dut], 17, P.udp(sport, dport, payload))))


def dhcp_to(dut, msg_type):
    payload = P.dhcp_reply(msg_type, XID[dut], LEASE_IP, DUT_MAC[dut], SERVER_IP)
    return P.with_fcs(P.eth(BCAST, SERVER_MAC, 0x0800,
                            P.ipv4(SERVER_IP, b"\xff" * 4, 17, P.udp(67, 68, payload))))


def scenario():
    f = []
    f.append((5, dhcp_to(0, 2)))     # OFFER  (DISCOVER went out at boot)
    f.append((10, dhcp_to(0, 5)))    # ACK    (after our REQUEST)
    f.append((5, P.with_fcs(P.eth(BCAST, HOST_MAC, 0x0806, P.arp_request(HOST_MAC, HOST_IP, DUT_IP[0])))))
    # DUT0's fallback address must not be answered once it holds a lease
    f.append((5, P.with_fcs(P.eth(BCAST, HOST_MAC, 0x0806, P.arp_request(HOST_MAC, HOST_IP, P.ip("192.168.65.16"))))))
    f.append((5, P.with_fcs(P.eth(DUT_MAC[0], HOST_MAC, 0x0800,
                                  P.ipv4(HOST_IP, DUT_IP[0], 1, P.icmp_echo(0x1234, 7, bytes(range(32))))))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 1, 0x0010, struct.pack(">I", BAUD_12M5)))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 2, 0x0050, struct.pack(">H", 1)))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 2, 0x0050, struct.pack(">H", 1)))))   # duplicate id
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 3, 0x7777, b"\x01"))))              # bad key
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 4, P.K_PK_LED_MODE, b"\x02"))))     # host LEDs
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 5, P.K_PK_LED_MODE, b"\x03"))))     # bad value
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 6, P.K_PK_LED_HOST, bytes(range(12))))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 7, P.K_PK_LED_HOST, bytes(11)))))  # bad length
    # raster never goes to a broadcast destination: point DUT0's telemetry
    # at the host first (dest MAC, dest IP), then enable capture
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 10, 0x0004, HOST_MAC))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 11, 0x0003, HOST_IP))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 8, K_CAPTURE_EN, b"\x01"))))      # raster on
    # thumbnails (issue 0038): stream this board's pictures to the host at
    # 1/2 scale, divisor 2; a group MAC is refused
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 13, K_THUMB_FORCE, HOST_MAC + b"\x01\x02"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 14, K_THUMB_FORCE, b"\x01\x00\x5e\x00\x00\x01\x01\x02"))))
    # a peer board's picture of machine 5 at 1/4 scale, and its request
    f.append((5, P.with_fcs(P.thumb_frame(DUT_MAC[1], PEER_MAC, 5, 1, 0, PEER_TILE, P.TH_SCALE_QUARTER, 4,
                                          vlan=VLAN))))
    f.append((5, P.with_fcs(P.thumb_request(PEER_MAC, P.TH_SCALE_QUARTER, 2, vlan=VLAN))))
    f.append((5, udp_to(0, P.PORT_KBD, P.kbd_set(0xFF, [10, 63]))))  # wildcard dut
    f.append((5, udp_to(0, P.PORT_UART, P.uart_tx(0, 0, 1, b"HELLO"))))
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 0, JTAG_TMS, JTAG_TDI, half=2))))
    f.append((60, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 0, JTAG_TMS, JTAG_TDI, half=2))))  # duplicate
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 5, "1", "0"))))                      # bad seq
    bad = bytearray(P.custom(P.T_KBD_SET, 0, bytes(10)))
    bad[0] = 0x00                                                                            # bad magic
    f.append((5, udp_to(0, P.PORT_KBD, bytes(bad))))
    # DUT1 only has an address after the (shortened, 1 ms) fallback delay
    f.append((1000, P.with_fcs(P.eth(BCAST, HOST_MAC, 0x0806, P.arp_request(HOST_MAC, HOST_IP, DUT_IP[1])))))
    f.append((5, udp_to(1, P.PORT_KBD, P.kbd_set(0, [1]))))   # dut field mismatch -> reject on DUT1
    f.append((5, udp_to(1, P.PORT_MGMT, P.mgmt_set(1, 9, 0x0050, struct.pack(">H", 1)))))
    # console screen forced to editable: passthrough (issue 0032) ends
    f.append((600, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 12, P.K_CON_SCREEN, b"\x01"))))
    # keyboard CPLD JTAG (ADR 0014): no keyboard detected -> unpowered; forced
    # on (key 0x0061) -> IDCODE of the keyboard's TAP, through DUT1's endpoint
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 0, JTAG_TMS, JTAG_TDI, half=2, flags=P.JF_KBD))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 15, P.K_PK_JTAG, b"\x04"))))   # bad value
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 16, P.K_PK_JTAG, b"\x01"))))   # force on
    f.append((5, udp_to(1, P.PORT_JTAG, P.jtag_req(1, 0, JTAG_TMS, JTAG_TDI, half=2, flags=P.JF_KBD))))
    # mode 3: engine on, JTAGEN low (the tb's TAP ignores JTAGEN): seq 1 works
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 17, P.K_PK_JTAG, b"\x03"))))
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 1, JTAG_TMS, JTAG_TDI, half=2, flags=P.JF_KBD))))
    # shield power CTRL (key 0x0062, issue 0049): set, then a bad length
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 18, P.K_PWR_CTL, b"\xa5"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 19, P.K_PWR_CTL, b"\xa5\x00"))))
    # issue 0054: keyboard JTAG quiet (key 0x0063) and TDO majority voting
    # (key 0x0064): bad values, then quiet 1 + vote 2 -> keyboard IDCODE
    # (the engine waits for the keyboard host to pause) and DUT0 IDCODE at
    # half 6; then quiet 2 (keyboard host stopped, JTAG forced on) -> seq 3
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 20, P.K_KJ_QUIET, b"\x03"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 21, P.K_TDO_VOTE, b"\x03"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 22, P.K_KJ_QUIET, b"\x01"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 23, P.K_TDO_VOTE, b"\x02"))))
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 2, JTAG_TMS, JTAG_TDI, half=6, flags=P.JF_KBD))))
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 1, JTAG_TMS, JTAG_TDI, half=6))))
    f.append((600, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 24, P.K_KJ_QUIET, b"\x02"))))
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 3, JTAG_TMS, JTAG_TDI, half=4, flags=P.JF_KBD))))
    # issue 0056: out-policy 2 also switches DUT0's JTAG off (status 4,
    # nothing clocked, seq not consumed); back to 0 -> seq 2 reads IDCODE
    f.append((100, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 25, P.K_OUT_POLICY, bytes([P.OUTPOL_OFF])))))
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 2, JTAG_TMS, JTAG_TDI, half=2))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 26, P.K_OUT_POLICY, bytes([P.OUTPOL_AUTO])))))
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 2, JTAG_TMS, JTAG_TDI, half=2))))
    # issue 0059: the largest JTAG_REQ an RX slot holds (7904 bits, frame
    # 2046 bytes incl. FCS) is clocked; 8 bits more overflow the slot and
    # are answered "bad format" (nothing clocked, seq not consumed)
    big = P.JTAG_MAX_BITS
    f.append((5, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 3, "1" * big, "0" * big, half=2))))
    f.append((300, udp_to(0, P.PORT_JTAG, P.jtag_req(0, 4, "1" * (big + 8), "0" * (big + 8), half=2))))
    # issue 0060: HDMI IN owned by DUT0 (key 0x0044 = 1); bad values for
    # 0x0044 and 0x0043; a relayed 1/4 thumbnail of DUT1's machine 3 is now
    # stored; console back to auto, video target DUT1 (no local video) ->
    # targeted priority 1/1 requests on VLAN 1650 and the full view of two
    # relayed 1/1 pictures
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 27, P.K_HDMI_OWNER, b"\x01"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 28, P.K_HDMI_OWNER, b"\x04"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 29, P.K_VLAN, struct.pack(">H", 4095)))))
    f.append((5, P.with_fcs(P.thumb_frame(DUT_MAC[0], PEER_MAC, 3, 1, 0, PEER_TILE, P.TH_SCALE_QUARTER, 4,
                                          vlan=VLAN))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 30, P.K_CON_SCREEN, b"\x00"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 31, 0x0031, b"\x01"))))
    for k in (1, 2):
        for fr in P.thumb_packets(DUT_MAC[0], PEER_MAC, 3, k, FULL_PIC, P.TH_SCALE_FULL, budget=1000, vlan=VLAN):
            f.append((5 if k == 1 else 20, P.with_fcs(fr)))
    # relay counters (issue 0061): an untagged relay frame (VLAN drop), and a
    # 1/1 RAW888 frame of 720 pixels for machine 9 (2214 bytes: longer than
    # a MAC slot; good, but not taken: no full view of machine 9)
    f.append((100, P.with_fcs(P.thumb_frame(DUT_MAC[1], PEER_MAC, 5, 2, 0, PEER_TILE, P.TH_SCALE_QUARTER, 4))))
    f.append((100, P.with_fcs(P.thumb_frame(DUT_MAC[0], PEER_MAC, 9, 1, 0, [LONG_LINE], P.TH_SCALE_FULL, 480,
                                          enc=P.TH_ENC_RAW, vlan=VLAN))))
    # relay-rx-speed: key 0x0045 relay view, bad value 2, then 1 (live, the default)
    f.append((20, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 32, P.K_RELAY_VIEW, b"\x02"))))
    f.append((5, udp_to(0, P.PORT_MGMT, P.mgmt_set(0, 33, P.K_RELAY_VIEW, b"\x01"))))
    return f


def gen(path):
    with open(path, "w") as fh:
        for delay, frame in scenario():
            fh.write("%d %d %s\n" % (delay, len(frame), " ".join("%02x" % b for b in frame)))


def check(path):
    frames = []
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if parts:
                frames.append(bytes(int(x, 16) for x in parts[1:]))
    errors = []

    def err(msg):
        errors.append(msg)

    parsed = [P.parse_frame(f) for f in frames]
    for i, d in enumerate(parsed):
        if not d["fcs_ok"]:
            err("frame %d bad FCS" % i)
        if d.get("ip_ok") is False:
            err("frame %d bad IP checksum" % i)

    dhcps = [(d, P.parse_dhcp(d["payload"])) for d in parsed
             if d.get("kind") == "udp" and d.get("sport") == 68 and d.get("dport") == 67]
    disc = [x for d, x in dhcps if x["opts"].get(53) == b"\x01"]
    reqs = [x for d, x in dhcps if x["opts"].get(53) == b"\x03"]
    if not any(x["chaddr"] == DUT_MAC[0] and x["xid"] == XID[0] for x in disc):
        err("no DISCOVER from DUT0 with xid %08x" % XID[0])
    if not any(x["chaddr"] == DUT_MAC[1] for x in disc):
        err("no DISCOVER from DUT1")
    for d, x in dhcps:
        if d["dst"] != BCAST or d["ip_dst"] != b"\xff" * 4 or x["len"] != 300 or \
           x["cookie"] != b"\x63\x82\x53\x63" or x["op"] != 1 or x["flags"] != 0x8000 or \
           x["opts"].get(61) != b"\x01" + x["chaddr"] or x["opts"].get(12, b"")[:6] != b"m65dut":
            err("malformed DHCP client message: %r" % x)
    if [x["opts"].get(12) for x in disc if x["chaddr"] == DUT_MAC[1]][:1] != [b"m65dut11"]:
        err("DUT1 host name wrong")
    if len(reqs) != 1 or reqs[0]["opts"].get(50) != LEASE_IP or reqs[0]["opts"].get(54) != SERVER_IP \
       or reqs[0]["xid"] != XID[0]:
        err("REQUEST wrong: %r" % reqs)

    for d in parsed:
        if d.get("kind") == "udp" and d.get("ptype") in (P.T_HEARTBEAT, P.T_UART_SNAP) and \
           d["ip_src"] == bytes(4):
            err("telemetry sent before the endpoint had an address")

    arps = [d for d in parsed if d.get("kind") == "arp"]
    if len(arps) != 2:
        err("expected 2 ARP replies, got %d" % len(arps))
    for d, dut in zip(arps, (0, 1)):
        if d["oper"] != 2 or d["sha"] != DUT_MAC[dut] or d["spa"] != DUT_IP[dut] or \
           d["tha"] != HOST_MAC or d["tpa"] != HOST_IP or d["dst"] != HOST_MAC:
            err("ARP reply %d wrong: %r" % (dut, d))

    icmps = [d for d in parsed if d.get("kind") == "icmp"]
    if len(icmps) != 1:
        err("expected 1 ICMP reply, got %d" % len(icmps))
    else:
        d = icmps[0]
        if d["icmp"][0] != 0 or not d["icmp_ok"] or d["icmp"][8:] != bytes(range(32)) or \
           d["ip_dst"] != HOST_IP or d["dst"] != HOST_MAC:
            err("ICMP reply wrong: %r" % d)

    acks = [P.decode_ack(d["body"]) for d in parsed
            if d.get("kind") == "udp" and d.get("ptype") == P.T_MGMT_ACK and d["dut"] == 0]
    acks1 = [P.decode_ack(d["body"]) for d in parsed
             if d.get("kind") == "udp" and d.get("ptype") == P.T_MGMT_ACK and d["dut"] == 1]
    if [(a["cmd_id"], a["status"]) for a in acks1] != [(9, 0)]:
        err("DUT1 MGMT ack %r" % acks1)
    want = [(1, 0x0010, 0), (2, 0x0050, 0), (2, 0x0050, 4), (3, 0x7777, 1),
            (4, P.K_PK_LED_MODE, 0), (5, P.K_PK_LED_MODE, 3), (6, P.K_PK_LED_HOST, 0),
            (7, P.K_PK_LED_HOST, 2), (10, 0x0004, 0), (11, 0x0003, 0), (8, K_CAPTURE_EN, 0),
            (13, K_THUMB_FORCE, 0), (14, K_THUMB_FORCE, 3), (12, P.K_CON_SCREEN, 0),
            (15, P.K_PK_JTAG, 3), (16, P.K_PK_JTAG, 0), (17, P.K_PK_JTAG, 0),
            (18, P.K_PWR_CTL, 0), (19, P.K_PWR_CTL, 2),
            (20, P.K_KJ_QUIET, 3), (21, P.K_TDO_VOTE, 3), (22, P.K_KJ_QUIET, 0),
            (23, P.K_TDO_VOTE, 0), (24, P.K_KJ_QUIET, 0),
            (25, P.K_OUT_POLICY, 0), (26, P.K_OUT_POLICY, 0),
            (27, P.K_HDMI_OWNER, 0), (28, P.K_HDMI_OWNER, 3), (29, P.K_VLAN, 3),
            (30, P.K_CON_SCREEN, 0), (31, 0x0031, 0), (32, P.K_RELAY_VIEW, 3), (33, P.K_RELAY_VIEW, 0)]
    got = [(a["cmd_id"], a["key"], a["status"]) for a in acks]
    if got != want:
        err("MGMT acks %r != %r" % (got, want))
    elif acks[-1]["cfg_gen"] != 22:  # baud, hb period, LED mode, LED vector, dest x2, capture,
        # thumb force, DUT1 hb period, console screen, kbd JTAG x2, power, quiet x2, vote,
        # out-policy x2, HDMI owner, console screen, video target, relay view
        err("cfg_gen %d != 22" % acks[-1]["cfg_gen"])

    jrall = [(d["dut"], P.decode_jtag_resp(d["body"])) for d in parsed
             if d.get("kind") == "udp" and d.get("ptype") == P.T_JTAG_RESP]
    jr = [r for (_, r) in jrall if r["target"] == P.JT_DUT]
    jk = [(dut, r) for (dut, r) in jrall if r["target"] == P.JT_KBD]
    if len(jk) != 5:
        err("expected 5 keyboard JTAG responses, got %d" % len(jk))
    else:
        (d0, r0), (d1, r1), (d2, r2), (d3, r3), (d4, r4) = jk
        for (r, seq, what) in ((r3, 2, "quiet 1, vote 2"), (r4, 3, "quiet 2 (host stopped)")):
            if r["status"] != 0 or r["seq"] != seq or r["next_seq"] != seq + 1 or \
               (int.from_bytes(r["tdo"], "little") >> 9) & 0xFFFFFFFF != KBD_IDCODE:
                err("keyboard JTAG with %s: %r" % (what, r))
        if r2["status"] != 0 or r2["seq"] != 1 or r2["next_seq"] != 2 or \
           (int.from_bytes(r2["tdo"], "little") >> 9) & 0xFFFFFFFF != KBD_IDCODE:
            err("keyboard JTAG in mode 3 (JTAGEN low): %r" % (jk[2],))
        if d0 != 0 or r0["status"] != 4 or r0["seq"] != 0 or r0["next_seq"] != 0 or r0["tdo_bytes"]:
            err("keyboard JTAG while off: %r" % (jk[0],))
        if d1 != 1 or r1["status"] != 0 or r1["bit_count"] != len(JTAG_TMS) or r1["next_seq"] != 1:
            err("keyboard JTAG forced on: %r" % (jk[1],))
        elif (int.from_bytes(r1["tdo"], "little") >> 9) & 0xFFFFFFFF != KBD_IDCODE:
            err("keyboard IDCODE %08x" % ((int.from_bytes(r1["tdo"], "little") >> 9) & 0xFFFFFFFF))
    if len(jr) != 8:
        err("expected 8 JTAG responses, got %d" % len(jr))
    else:
        r = jr[6]
        if r["status"] != 0 or r["seq"] != 3 or r["next_seq"] != 4 or r["bit_count"] != P.JTAG_MAX_BITS \
           or r["tdo_bytes"] != P.JTAG_MAX_BITS // 8:
            err("DUT0 JTAG of the maximum size (%d bits): %r" % (P.JTAG_MAX_BITS, r))
        r = jr[7]
        if r["status"] != 3 or r["seq"] != 4 or r["next_seq"] != 4 or r["tdo_bytes"]:
            err("oversize JTAG_REQ not answered bad format: %r" % r)
        r = jr[4]
        if r["status"] != 4 or r["seq"] != 2 or r["next_seq"] != 2 or r["tdo_bytes"]:
            err("DUT0 JTAG with out-policy 2 not refused as unpowered: %r" % r)
        r = jr[5]
        if r["status"] != 0 or r["seq"] != 2 or r["next_seq"] != 3 or \
           (int.from_bytes(r["tdo"], "little") >> 9) & 0xFFFFFFFF != IDCODE:
            err("DUT0 JTAG after out-policy 0: %r" % r)
        r = jr[3]
        if r["status"] != 0 or r["seq"] != 1 or r["next_seq"] != 2 or \
           (int.from_bytes(r["tdo"], "little") >> 9) & 0xFFFFFFFF != IDCODE:
            err("DUT0 JTAG with TDO vote 2 at half 6: %r" % r)
        for r in jr[:2]:
            if r["status"] != 0 or r["bit_count"] != len(JTAG_TMS) or r["next_seq"] != 1:
                err("JTAG response wrong: %r" % r)
            else:
                v = int.from_bytes(r["tdo"], "little")
                idc = (v >> 9) & 0xFFFFFFFF
                if idc != IDCODE:
                    err("IDCODE %08x != %08x" % (idc, IDCODE))
        if jr[2]["status"] != 2 or jr[2]["seq"] != 5 or jr[2]["next_seq"] != 1:
            err("bad-seq response wrong: %r" % jr[2])

    snaps = [P.decode_snapshot(d["body"]) for d in parsed
             if d.get("kind") == "udp" and d.get("ptype") == P.T_UART_SNAP and d["dut"] == 0]
    hello = [s for s in snaps if s["rx_seq"] == 5]
    if not hello:
        err("no DUT0 UART snapshot with rx_seq 5 (got %r)" % [s["rx_seq"] for s in snaps])
    else:
        s = hello[-1]
        if s["rx_history"][-5:] != b"HELLO" or s["tx_history"][-5:] != b"HELLO" or \
           any(s["rx_history"][:-5]) or s["tx_accepted"] != 5 or s["baud_nco"] != BAUD_12M5:
            err("snapshot content wrong")

    hbs = [(d["dut"], P.decode_heartbeat(d["body"])) for d in parsed
           if d.get("kind") == "udp" and d.get("ptype") == P.T_HEARTBEAT]
    hb0 = [h for (dut, h) in hbs if dut == 0]
    hb1 = [h for (dut, h) in hbs if dut == 1]
    if len(hb0) < 2:
        err("expected >=2 DUT0 heartbeats (1 ms period), got %d" % len(hb0))
    else:
        h = hb0[-1]
        if h["dna"] != DNA or h["kbd_udp"] != (1 << 10) | (1 << 63) or h["kbd_eff"] != h["kbd_udp"]:
            err("heartbeat DUT0 fields wrong: %r" % h)
        if h["uart_rx_seq"] != 5 or h["uart_tx_acc"] != 5 or h["jtag_next_seq"] != 4:
            err("heartbeat DUT0 counters wrong: %r" % h)
        if h["rx_rejects"] != 2:   # unknown type + oversize JTAG_REQ
            err("DUT0 rx_rejects %d != 2" % h["rx_rejects"])
        if h["target_flags"] & (P.TF_OUT_EN | P.TF_PWR_HOLD) != P.TF_OUT_EN:
            err("DUT0 target_flags %02x: outputs not back on after out-policy 0" % h["target_flags"])
        if not h["caps"] & P.CAP_KBD_JTAG or h["phys_type"] != 0:
            err("heartbeat caps %x / phys_type %d" % (h["caps"], h["phys_type"]))
        seqs = [x["hb_seq"] for x in hb0]
        if seqs != sorted(seqs):
            err("heartbeat seq not increasing")
    if hb1 and hb1[-1]["rx_rejects"] != 1:
        err("DUT1 rx_rejects %d != 1" % hb1[-1]["rx_rejects"])
    if hb0 and (hb0[-1]["addr_src"] != 1 or hb0[-1]["dut_id"] != 0):
        err("DUT0 heartbeat addr_src/dut_id %r" % ((hb0[-1]["addr_src"], hb0[-1]["dut_id"]),))
    for d, h in hbs:
        if "rx_hunts" not in h or "video_flags" not in h or "mem_flags" not in h or "shd_flags" not in h \
                or "rl_req_sent" not in h or "rl_fifo_hwm" not in h:
            err("heartbeat without video/link/memory/shield/relay/receive-load block (expected 188-byte payload)")
            break
        # testbench: no shield (status inputs at defaults): all-zero block
        if any(h[k] for k in P.SHD_FIELDS):
            err("shield block unexpected: %r" % ({k: h[k] for k in P.SHD_FIELDS},))
            break
        # testbench: no memory subsystem attached (status inputs at defaults)
        if (h["mem_flags"], h["mem_errors"], h["mem_dq_fail"], h["mem_first_err"]) != (0, 0, 0, 0xFFFFFFFF):
            err("memory block unexpected: %r" % ({k: h[k] for k in P.MEM_FIELDS},))
            break
        # testbench: gigabit, 5 renegotiation attempts (issue 0070), RX MMCM
        # locked, not hunting, PHY not held
        if h["rx_hunts"] != 0 or h["rx_phase_pos"] != 0 or h["link_speed"] != P.LINK_SPEED_1000 \
                or h["rx_reneg"] != 5 or h["rx_link_flags"] != P.RXF_LOCKED | (P.LINK_SPEED_1000 << 2):
            err("link block unexpected: %r" % ({k: h[k] for k in P.LINK_FIELDS},))
            break
        # testbench HDMI IN: clock present + locked; capture enabled on DUT0 only
        if h["video_flags"] & 0x0B != 0x03 or (h["video_flags"] & 4 and d != 0) or \
           (h["h_total"], h["v_total"], h["h_active"], h["v_active"]) != (V_HT, V_VT, V_HA, V_VA):
            err("video block unexpected: dut %d %r" % (d, h))
            break
        if h["raster_lines_dropped"] != 0:
            err("heartbeat reports %d raster lines dropped" % h["raster_lines_dropped"])
            break
    if not hb0 or not hb0[-1]["video_flags"] & 4:
        err("DUT0 heartbeat does not show capture enabled")
    # HDMI OUT shown (byte 109, issue 0032): passthrough (3) while the video
    # target's video is present on auto, editable (0) once key 0x0035 = 1;
    # at the end (issue 0060) the video target DUT1 has no local video: the
    # full view (4) while relayed pictures arrive, else no video (1)
    shown = [h["console_screen"] for h in hb0]
    first0 = shown.index(0) if 0 in shown else None
    if 3 not in shown or first0 is None or any(x != 3 for x in shown[:first0]):
        err("DUT0 heartbeat console_screen sequence %r (want 3 ... then 0)" % shown)
    else:
        tail = shown[first0:]
        n0 = next((i for i, x in enumerate(tail) if x != 0), len(tail))
        if any(x not in (1, 4) for x in tail[n0:]):
            err("DUT0 heartbeat console_screen sequence %r (want 3 ... 0 ... then 1/4)" % shown)
        else:
            print("console shown (byte 109): %r" % shown)
    if not hb1 or hb1[-1]["addr_src"] != 2 or hb1[-1]["dut_id"] != 0x11:
        err("DUT1 heartbeat missing or addr_src/dut_id wrong")

    # raster (issue 0023): one datagram per active line, frames rebuilt and
    # compared byte for byte with the testbench pattern
    rasters = [d for d in parsed if d.get("kind") == "udp" and d.get("ptype") == P.T_RASTER]
    frames_px = {}
    hb_dst = [(d["dst"], d["ip_dst"]) for d in parsed
              if d.get("kind") == "udp" and d.get("ptype") == P.T_HEARTBEAT and d["dut"] == 0][:1]
    last_seq = 0
    for d in rasters:
        try:
            r = P.decode_raster(d["body"])
        except ValueError as e:
            err("raster decode: %s" % e)
            continue
        where = "raster frame %d line %d" % (r["frame"], r["line"])
        if d["dut"] != 0 or d["src"] != DUT_MAC[0] or d["ip_src"] != DUT_IP[0] or \
           d["sport"] != P.PORT_RASTER or d["dport"] != P.PORT_RASTER or \
           (d["dst"], d["ip_dst"]) != (HOST_MAC, HOST_IP) or d["plen"] != 44 + r["payload_bytes"]:
            err("%s: addressing/header wrong" % where)
        if (r["encoding"], r["h_total"], r["v_total"], r["v_active"], r["active_count"],
                r["payload_bytes"], r["hs_start"], r["hs_end"]) != \
                (P.ENC_RAW, V_HT, V_VT, V_VA, V_HA, 3 * V_HA, V_HS0, V_HS1):
            err("%s: fields %r" % (where, {k: v for k, v in r.items() if k not in ("pixels", "uart_rx_history")}))
        want_flags = P.RF_ACTIVE | P.RF_LOCKED | (P.RF_FIRST if r["line"] == 0 else 0)
        if r["flags"] != want_flags:
            err("%s: flags %02x != %02x" % (where, r["flags"], want_flags))
        if r["line"] >= V_VA or r["pixels"] != pattern_line(r["line"]):
            err("%s: pixels differ" % where)
        if r["uart_rx_seq"] < last_seq:
            err("%s: uart_rx_seq went backwards" % where)
        last_seq = r["uart_rx_seq"]
        n = min(r["uart_rx_seq"], 16)
        want_hist = bytes(16 - n) + b"HELLO"[5 - n:] if r["uart_rx_seq"] <= 5 else None
        if want_hist is not None and r["uart_rx_history"] != want_hist:
            err("%s: uart history %r (rx_seq %d)" % (where, r["uart_rx_history"], r["uart_rx_seq"]))
        frames_px.setdefault(r["frame"], {})
        if r["line"] in frames_px[r["frame"]]:
            err("%s: duplicate line" % where)
        frames_px[r["frame"]][r["line"]] = r["pixels"]
    fnums = sorted(frames_px)
    if not fnums or fnums != list(range(fnums[0], fnums[0] + len(fnums))):
        err("raster frame numbers not consecutive: %r" % fnums)
    complete = [f for f in fnums if sorted(frames_px[f]) == list(range(V_VA))]
    expect = b"".join(pattern_line(y) for y in range(V_VA))
    for f in complete:
        if b"".join(frames_px[f][y] for y in range(V_VA)) != expect:
            err("raster frame %d differs from the source image" % f)
    # every frame but the last (cut off by the end of the run) must be complete
    if fnums and complete != fnums[:len(complete)] or len(complete) < len(fnums) - 1:
        err("incomplete raster frames: %r" % {f: sorted(frames_px[f]) for f in fnums})
    if len(complete) < 4:
        err("expected >= 4 complete raster frames, got %d" % len(complete))
    if not any(r_seq == 5 for r_seq in [P.decode_raster(d["body"])["uart_rx_seq"] for d in rasters]):
        err("no raster packet with uart_rx_seq 5 (HELLO)")
    if hb0 and complete and hb0[-1]["frames_captured"] < len(complete) - 1:
        err("heartbeat frames_captured %d < %d" % (hb0[-1]["frames_captured"], len(complete) - 1))
    print("raster: %d line packets, %d complete frames (%r) rebuilt and equal to the source"
          % (len(rasters), len(complete), complete))

    # thumbnails (issues 0035/0038): relay frames to the forced host MAC,
    # pictures rebuilt and compared with the box-filtered source
    ths = [(d, P.decode_thumb(f[14:-4])) for d, f in zip(parsed, frames) if d["etype"] == P.ETH_THUMB]
    pics, nosrc = {}, set()
    for d, t in ths:
        if d["dst"] != HOST_MAC:
            err("thumbnail frame to %s" % d["dst"].hex())
        if t["sub"] == P.TH_SUB_NOSRC:
            nosrc.add((t["machine"], d["src"]))
            continue
        if t["sub"] != P.TH_SUB_LINES or t["machine"] != 0 or d["src"] != DUT_MAC[0] or \
           t["scale"] != P.TH_SCALE_HALF or t["height"] != 4 or t["width"] != 320:
            err("thumbnail frame fields %r" % {k: v for k, v in t.items() if k != "lines"})
            continue
        pic = pics.setdefault(t["frame"], {})
        for i, line in enumerate(t["lines"]):
            pic[t["row"] + i] = line
    done = [f for f in sorted(pics) if sorted(pics[f]) == [0, 1, 2, 3]]
    for f in done:
        if [pics[f][y] for y in range(4)] != THUMB_TILE:
            err("thumbnail picture %d differs from the box-filtered source" % f)
    if len(done) < 2:
        err("expected >= 2 complete thumbnail pictures, got %d (%r)" % (len(done), sorted(pics)))
    if (3, DUT_MAC[1]) not in nosrc:
        err("no 'present, no source' frame for machine 3 from DUT1 (%r)" % nosrc)
    print("thumbnails: %d relay frames, %d complete pictures equal to the source, no-source %r"
          % (len(ths), len(done), sorted(m for m, _ in nosrc)))

    # issue 0060: inter-board relay frames carry the VLAN 1650 tag; the full
    # view requests DUT1's machine 3 (targeted, priority, 1/1, divisor 1)
    tagged = [(vid, u) for vid, u in (P.vlan_untag(f[:-4]) for f in frames) if vid is not None]
    for vid, u in tagged:
        if vid != VLAN or u[12:14] != b"\x88\xb5":
            err("tagged frame VID %d EtherType %s" % (vid, u[12:14].hex()))
    treqs = [(u, P.decode_thumb(u[14:])) for vid, u in tagged if u[12:14] == b"\x88\xb5"]
    full = [u for u, t in treqs if t["sub"] == P.TH_SUB_REQ]
    if not full:
        err("no tagged requests for the full view")
    for u in full:
        if u[:6] != BCAST or u[6:12] != DUT_MAC[0] or u[14:22] != bytes.fromhex("01014d3603010303"):
            err("full-view request %s" % u[:22].hex())
    if any(t["sub"] != P.TH_SUB_REQ for u, t in treqs):
        err("tagged relay frames other than requests (nothing was requested from this board)")
    # (the full view itself is checked by the testbench: full_on; with the
    # shortened 1 s = 1 ms a heartbeat rarely falls into it)
    shown = sorted(set(h["console_screen"] for h in hb0))
    # relay counters (issue 0061) in the last heartbeat: one request heard,
    # good lines frames (two thumbnails, the full pictures, the long one),
    # the untagged frame dropped, the long frame counted and not taken
    if hb0:
        r = {k: hb0[-1][k] for k in P.RELAY_FIELDS}
        nfull = sum(1 for k in (1, 2) for _ in P.thumb_packets(DUT_MAC[0], PEER_MAC, 3, k, FULL_PIC,
                                                                P.TH_SCALE_FULL, budget=1000))
        want = dict(rl_rx_req=1, rl_rx_lines=3 + nfull, rl_rx_bad=0, rl_rx_ovf=0, rl_rx_vlan=1,
                    rl_rx_long=1, rl_rx_foreign=1, rl_full_pics=2, rl_last_machine=9, rl_last_scale=3)
        if any(r[k] != v for k, v in want.items()) or r["rl_req_full"] < 1 or \
                r["rl_req_sent"] < r["rl_req_full"] or r["rl_req_sent"] < len(full) or \
                not r["rl_flags"] & P.RLF_LAST_VALID or not r["rl_flags"] & P.RLF_FULL_WANT or \
                r["rl_flags"] & P.RLF_LAST_NOSRC:
            err("relay counters %r (want %r, requests >= %d)" % (r, want, len(full)))
        # relay-rx-speed: live view by default, receive load block
        x = {k: hb0[-1][k] for k in P.RXLOAD_FIELDS}
        if not r["rl_flags"] & P.RLF_LIVE or x["rl_fifo_aw"] != 14 or x["rl_wf_hwm"] > 255:
            err("relay view / receive load %r flags %#x" % (x, r["rl_flags"]))
        print("receive load: %s" % " ".join("%s=%d" % (k[3:], v) for k, v in x.items()))
        print("relay counters: %s" % " ".join("%s=%d" % (k[3:], v) for k, v in r.items()))
    # neighbour block (issue 0069): the testbench's other supervisor has
    # B = 0 (DIP 0x0A), DNA 0x77, build C0DE0077 and claims primary; HELLOs
    # every 1 ms both ways. Every heartbeat has the block; once the first
    # HELLO is in, both endpoints report the same peer and the core (B = 1)
    # is secondary; no link errors.
    nbs = [h for _, h in hbs]
    if any("nb_flags" not in h for h in nbs):
        err("heartbeat without the neighbour block (expected 228-byte payload)")
    else:
        if any(not h["nb_flags"] & P.NBF_BUILD for h in nbs):
            err("nb_flags without b0 (bitstream has the link)")
        want_f = P.NBF_BUILD | P.NBF_PRESENT | P.NBF_HEARD_US | P.NBF_VALID
        for d, h in hbs[-4:]:
            n = {k: h[k] for k in P.NB_FIELDS}
            want = dict(nb_flags=want_f, nb_role=P.NB_SECONDARY, nb_peer_dip=0x0A, nb_peer_role=P.NB_PRIMARY,
                        nb_peer_dna=0x77, nb_peer_build=0xC0DE0077, nb_crc_errs=0, nb_uart_errs=0, nb_fmt_errs=0)
            if any(n[k] != v for k, v in want.items()) or n["nb_rx_frames"] < 2 or n["nb_tx_frames"] < 2 or \
                    n["nb_peer_seq"] != n["nb_rx_frames"] - 1:
                err("DUT%d neighbour block %r (want %r)" % (d, n, want))
                break
        early = [h for h in nbs if not h["nb_flags"] & P.NBF_VALID]
        if any(h["nb_role"] != P.NB_STANDALONE or h["nb_flags"] != P.NBF_BUILD or h["nb_rx_frames"]
               for h in early):
            err("neighbour block before the first HELLO not standalone/zero")
        print("neighbour: %d heartbeats before the first HELLO, last role %s rx %d tx %d" %
              (len(early), P.NB_ROLES.get(nbs[-1]["nb_role"], "?"), nbs[-1]["nb_rx_frames"],
               nbs[-1]["nb_tx_frames"]))
    print("full view: %d tagged requests (%s), console shown %r"
          % (len(full), full[0][14:22].hex() if full else "-", shown))

    print("DHCP: %d DISCOVER, %d REQUEST" % (len(disc), len(reqs)))
    print("captured %d frames: %d ARP, %d ICMP, %d ACK, %d JTAG (%d keyboard), %d snapshots, %d heartbeats"
          % (len(frames), len(arps), len(icmps), len(acks), len(jrall), len(jk), len(snaps), len(hbs)))
    for e in errors:
        print("ERROR:", e)
    print("core_scenario check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
