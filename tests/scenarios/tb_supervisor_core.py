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
BAUD_12M5 = 429496730
# JTAG: TLR x5, RTI, SELDR, CAPDR, SHDR (9 nav bits) then 32 bits, last exits
JTAG_TMS = "11111" + "0100" + "0" * 31 + "1"
JTAG_TDI = "0" * len(JTAG_TMS)


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
    want = [(1, 0x0010, 0), (2, 0x0050, 0), (2, 0x0050, 4), (3, 0x7777, 1)]
    got = [(a["cmd_id"], a["key"], a["status"]) for a in acks]
    if got != want:
        err("MGMT acks %r != %r" % (got, want))
    elif acks[-1]["cfg_gen"] != 2:
        err("cfg_gen %d != 2" % acks[-1]["cfg_gen"])

    jr = [P.decode_jtag_resp(d["body"]) for d in parsed
          if d.get("kind") == "udp" and d.get("ptype") == P.T_JTAG_RESP]
    if len(jr) != 3:
        err("expected 3 JTAG responses, got %d" % len(jr))
    else:
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
        if h["uart_rx_seq"] != 5 or h["uart_tx_acc"] != 5 or h["jtag_next_seq"] != 1:
            err("heartbeat DUT0 counters wrong: %r" % h)
        if h["rx_rejects"] != 1:
            err("DUT0 rx_rejects %d != 1" % h["rx_rejects"])
        seqs = [x["hb_seq"] for x in hb0]
        if seqs != sorted(seqs):
            err("heartbeat seq not increasing")
    if hb1 and hb1[-1]["rx_rejects"] != 1:
        err("DUT1 rx_rejects %d != 1" % hb1[-1]["rx_rejects"])
    if hb0 and (hb0[-1]["addr_src"] != 1 or hb0[-1]["dut_id"] != 0):
        err("DUT0 heartbeat addr_src/dut_id %r" % ((hb0[-1]["addr_src"], hb0[-1]["dut_id"]),))
    if not hb1 or hb1[-1]["addr_src"] != 2 or hb1[-1]["dut_id"] != 0x11:
        err("DUT1 heartbeat missing or addr_src/dut_id wrong")

    print("DHCP: %d DISCOVER, %d REQUEST" % (len(disc), len(reqs)))
    print("captured %d frames: %d ARP, %d ICMP, %d ACK, %d JTAG, %d snapshots, %d heartbeats"
          % (len(frames), len(arps), len(icmps), len(acks), len(jr), len(snaps), len(hbs)))
    for e in errors:
        print("ERROR:", e)
    print("core_scenario check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
