"""Host VLAN (key 0x0046, issue 0062): input frames for tb_host_vlan and the
check of its captured output.

  python3 -I tests/scenarios/tb_host_vlan.py gen   <out.txt>
  python3 -I tests/scenarios/tb_host_vlan.py check <captured.txt>

Phases (markers in the capture: the MGMT acks of the key changes):
  1 key 0 (default): untagged DHCP lease for DUT0, tagged frames dropped;
    bad value / bad length for the key; set 1650 with an untagged request
    (ack untagged, still from the old lease address).
  2 key 1650: DHCP starts over tagged (an untagged OFFER is ignored), new
    lease; every host frame tagged (heartbeats, snapshots, DHCP); replies on
    the request's VLAN: tagged ARP/ICMP/MGMT/JTAG -> tagged, untagged
    ARP/ICMP/MGMT (recovery) -> untagged; untagged KBD/TEXT/JTAG and VID
    1651 dropped; set 0 with a tagged request (ack tagged).
  3 key 0 again: untagged; tagged frames dropped; DHCP starts over untagged.
"""
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import netproto as P  # noqa: E402

VID = 1650
HOST_MAC = P.mac("02:00:00:00:00:01")
HOST_IP = P.ip("192.168.65.1")
VHOST_IP = P.ip("10.231.50.1")              # bob's eno2.1650
BCAST = b"\xff" * 6
DUT_MAC = [bytes([0x02, 0x4D, 0x36, 0x35, 0x00, d]) for d in (0x00, 0x11)]
LEASE1 = P.ip("10.65.0.50")
LEASE2 = P.ip("10.231.50.150")
BOGUS = P.ip("10.65.0.99")
SERVER1, SERVER2 = P.ip("10.65.0.1"), VHOST_IP
SERVER_MAC = P.mac("02:00:00:00:00:fe")
FALLBACK = [P.ip("192.168.65.16"), P.ip("192.168.65.33")]
XID0 = 0x4D363501
IDCODE = 0x0362C093
JTAG_TMS = "11111" + "0100" + "0" * 31 + "1"
JTAG_TDI = "0" * len(JTAG_TMS)
CMD_SET_VLAN, CMD_SET_0 = 4, 8


def tag(frame, vid):
    return P.with_fcs(P.vlan_tag(frame, vid))


def udp_to(dst_ip, dport, payload, src_ip=HOST_IP, dut=0, sport=40000):
    return P.eth(DUT_MAC[dut], HOST_MAC, 0x0800, P.ipv4(src_ip, dst_ip, 17, P.udp(sport, dport, payload)))


def dhcp(msg_type, xid, yiaddr, server):
    payload = P.dhcp_reply(msg_type, xid, yiaddr, DUT_MAC[0], server)
    return P.eth(BCAST, SERVER_MAC, 0x0800, P.ipv4(server, b"\xff" * 4, 17, P.udp(67, 68, payload)))


def arp(tpa, spa=HOST_IP):
    return P.eth(BCAST, HOST_MAC, 0x0806, P.arp_request(HOST_MAC, spa, tpa))


def ping(dst, seq, src=HOST_IP):
    return P.eth(DUT_MAC[0], HOST_MAC, 0x0800, P.ipv4(src, dst, 1, P.icmp_echo(0x0062, seq, bytes(range(16)))))


def text(dst_ip, addr, data, src_ip=HOST_IP):
    return udp_to(dst_ip, 6508, P.custom(0x50, 0xFF, struct.pack(">HH", addr, 0) + data), src_ip)


def mgmt(dst_ip, cmd, key, value, src_ip=HOST_IP, dut=0):
    return udp_to(dst_ip, P.PORT_MGMT, P.mgmt_set(dut, cmd, key, value), src_ip, dut)


def scenario():
    u = P.with_fcs
    f = []
    # phase 1: key 0
    f.append((5, u(dhcp(2, XID0, LEASE1, SERVER1))))
    f.append((10, u(dhcp(5, XID0, LEASE1, SERVER1))))
    f.append((5, u(mgmt(LEASE1, 1, 0x0050, struct.pack(">H", 1)))))           # hb period 1 ms
    f.append((5, tag(arp(LEASE1), VID)))                                        # dropped (tagged)
    f.append((5, u(text(LEASE1, 0, b"AB"))))                                    # written
    f.append((5, u(mgmt(LEASE1, 2, P.K_HOST_VLAN, struct.pack(">H", 4095)))))  # bad value
    f.append((5, u(mgmt(LEASE1, 3, P.K_HOST_VLAN, b"\x06"))))                  # bad length
    f.append((1000, u(mgmt(FALLBACK[1], 1, 0x0050, struct.pack(">H", 1), dut=1))))
    f.append((100, u(mgmt(LEASE1, CMD_SET_VLAN, P.K_HOST_VLAN, struct.pack(">H", VID)))))
    # phase 2: key 1650; DHCP restarts 1..2 ms later (DISCOVER xid XID0, or
    # XID0 + 1 after one 2 ms retry): an untagged OFFER (dropped), then
    # tagged OFFER/ACK for both xids (the other one is ignored)
    f.append((2500, u(dhcp(2, XID0, BOGUS, SERVER1))))
    for x in (XID0, XID0 + 1):
        f.append((5, tag(dhcp(2, x, LEASE2, SERVER2), VID)))
    for x in (XID0, XID0 + 1):
        f.append((10, tag(dhcp(5, x, LEASE2, SERVER2), VID)))
    f.append((20, tag(arp(LEASE2, VHOST_IP), VID)))                             # tagged reply
    f.append((5, u(arp(LEASE2))))                                               # untagged reply
    f.append((5, tag(ping(LEASE2, 1, VHOST_IP), VID)))                          # tagged reply
    f.append((5, tag(mgmt(LEASE2, 5, 0x0050, struct.pack(">H", 1), VHOST_IP), VID)))
    f.append((5, tag(mgmt(LEASE2, 6, 0x0050, struct.pack(">H", 1), VHOST_IP), VID + 1)))  # dropped
    f.append((5, u(mgmt(LEASE2, 7, 0x0050, struct.pack(">H", 1)))))           # recovery: untagged ack
    f.append((5, u(udp_to(LEASE2, P.PORT_KBD, P.kbd_set(0, [3])))))            # dropped
    f.append((5, tag(udp_to(LEASE2, P.PORT_KBD, P.kbd_set(0, [10, 63]), VHOST_IP), VID)))
    f.append((5, tag(text(LEASE2, 2, b"CD", VHOST_IP), VID)))                   # written
    f.append((5, u(text(LEASE2, 4, b"EF"))))                                    # dropped
    f.append((5, tag(udp_to(LEASE2, P.PORT_UART, P.uart_tx(0, 0, 1, b"HI"), VHOST_IP), VID)))
    f.append((5, tag(udp_to(LEASE2, P.PORT_JTAG, P.jtag_req(0, 0, JTAG_TMS, JTAG_TDI), VHOST_IP), VID)))
    f.append((60, u(udp_to(LEASE2, P.PORT_JTAG, P.jtag_req(0, 1, JTAG_TMS, JTAG_TDI)))))  # dropped
    f.append((5, u(ping(LEASE2, 2))))                                           # untagged reply
    f.append((1500, tag(mgmt(LEASE2, CMD_SET_0, P.K_HOST_VLAN, b"\x00\x00", VHOST_IP), VID)))
    # phase 3: key 0 again
    f.append((500, tag(ping(LEASE2, 3, VHOST_IP), VID)))                       # dropped
    f.append((5, tag(text(FALLBACK[0], 6, b"GH", VHOST_IP), VID)))              # dropped
    return f


DROPS = 8   # tagged ARP; bogus OFFER, VID 1651, KBD, TEXT, JTAG; tagged ping, TEXT


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
    err = errors.append
    ds = [P.parse_frame_vlan(f) for f in frames]
    for i, d in enumerate(ds):
        if not d["fcs_ok"] or d.get("ip_ok") is False:
            err("frame %d: bad FCS / IP checksum" % i)
        if d["vid"] not in (0, VID):
            err("frame %d: VID %d" % (i, d["vid"]))
        if d["vid"] and (d["wire_len"] < 68 or frames[i][14] & 0xF0):
            err("frame %d: tagged, %d bytes, TCI %02x%02x" % (i, d["wire_len"], frames[i][14], frames[i][15]))

    def udp(d, ptype=None, sport=None):
        return d.get("kind") == "udp" and (ptype is None or d.get("ptype") == ptype) and \
            (sport is None or d["sport"] == sport)

    acks = [(i, P.decode_ack(d["body"]), d) for i, d in enumerate(ds) if udp(d, P.T_MGMT_ACK)]
    got = [(a["cmd_id"], a["key"], a["status"], d["vid"]) for _, a, d in acks]
    want = [(1, 0x0050, 0, 0), (2, P.K_HOST_VLAN, 3, 0), (3, P.K_HOST_VLAN, 2, 0), (1, 0x0050, 0, 0),
            (CMD_SET_VLAN, P.K_HOST_VLAN, 0, 0), (5, 0x0050, 0, VID), (7, 0x0050, 0, 0),
            (CMD_SET_0, P.K_HOST_VLAN, 0, VID)]
    if got != want:
        err("MGMT acks (cmd, key, status, VID) %r != %r" % (got, want))
        return report(errors, frames)
    i_on = acks[4][0]
    i_off = acks[7][0]
    if acks[4][2]["ip_src"] != LEASE1:
        err("ack of the switch not from the old lease address: %s" % acks[4][2]["ip_src"].hex())
    if acks[5][2]["ip_src"] != LEASE2 or acks[6][2]["ip_src"] != LEASE2 or acks[6][2]["ip_dst"] != HOST_IP:
        err("phase 2 acks addressing")

    def phase(i):
        return 1 if i <= i_on else 2 if i <= i_off else 3

    # every host frame after a switch carries the new VLAN, except replies
    # (they follow their request)
    reply = {i for i, d in enumerate(ds) if d.get("kind") in ("arp", "icmp") or
             udp(d, P.T_MGMT_ACK) or udp(d, P.T_JTAG_RESP)}
    for i, d in enumerate(ds):
        if i in reply or i == i_on or i == i_off:
            continue
        want_vid = VID if phase(i) == 2 else 0
        if d["vid"] != want_vid:
            err("frame %d (phase %d, %s %s) VID %d != %d" % (i, phase(i), d.get("kind"), d.get("ptype"),
                                                             d["vid"], want_vid))

    # DHCP: DISCOVER/REQUEST per phase, on the right VLAN
    dh = [(i, d, P.parse_dhcp(d["payload"])) for i, d in enumerate(ds) if udp(d, sport=68)]
    for ph, vid in ((1, 0), (2, VID), (3, 0)):
        for dut in (0, 1):
            disc = [d for i, d, x in dh if phase(i) == ph and x["chaddr"] == DUT_MAC[dut] and
                    x["opts"].get(53) == b"\x01"]
            if not disc or any(d["vid"] != vid for d in disc):
                err("phase %d DUT%d DISCOVER: %r" % (ph, dut, [d["vid"] for d in disc]))
    reqs = [(phase(i), d["vid"], x["opts"].get(50)) for i, d, x in dh if x["opts"].get(53) == b"\x03"]
    if reqs != [(1, 0, LEASE1), (2, VID, LEASE2)]:
        err("DHCP REQUESTs (phase, VID, requested IP) %r" % reqs)

    # replies on the request's VLAN
    arps = [(phase(i), d["vid"], d["spa"], d["tpa"]) for i, d in enumerate(ds) if d.get("kind") == "arp"]
    if arps != [(2, VID, LEASE2, VHOST_IP), (2, 0, LEASE2, HOST_IP)]:
        err("ARP replies (phase, VID, spa, tpa) %r" % arps)
    icmps = [(phase(i), d["vid"], d["ip_dst"], d["icmp"][6:8]) for i, d in enumerate(ds) if d.get("kind") == "icmp"]
    if icmps != [(2, VID, VHOST_IP, b"\x00\x01"), (2, 0, HOST_IP, b"\x00\x02")] or \
            any(d["icmp"][0] != 0 or not d["icmp_ok"] for d in ds if d.get("kind") == "icmp"):
        err("ICMP replies (phase, VID, dst, seq) %r" % icmps)
    jr = [(phase(i), d["vid"], P.decode_jtag_resp(d["body"])) for i, d in enumerate(ds) if udp(d, P.T_JTAG_RESP)]
    if len(jr) != 1 or jr[0][:2] != (2, VID) or jr[0][2]["status"] != 0 or \
            (int.from_bytes(jr[0][2]["tdo"], "little") >> 9) & 0xFFFFFFFF != IDCODE:
        err("JTAG responses %r" % jr)

    # UART over the VLAN: the tagged UART_TX was taken ("HI" looped back;
    # the snapshot's VLAN is checked with all other frames above)
    snaps = [(phase(i), d["vid"], P.decode_snapshot(d["body"])) for i, d in enumerate(ds)
             if udp(d, P.T_UART_SNAP) and d["dut"] == 0]
    hi = [(p, v) for p, v, s in snaps if s["rx_seq"] == 2 and s["rx_history"][-2:] == b"HI"]
    if not hi:
        err("no DUT0 snapshot with HI")

    # heartbeats: network block, addresses, keyboard over the VLAN
    hbs = [(phase(i), d, P.decode_heartbeat(d["body"])) for i, d in enumerate(ds) if udp(d, P.T_HEARTBEAT)]
    for ph, d, h in hbs:
        if "host_vlan" not in h:
            err("heartbeat without the network block")
            break
        if d["ip_src"] == bytes(4):
            err("heartbeat without an address")
            break
    hb2 = [(d, h) for ph, d, h in hbs if ph == 2 and d["dut"] == 0 and d["ip_src"] == LEASE2]
    if not hb2 or any(h["host_vlan"] != VID for d, h in hb2):
        err("phase 2 DUT0 heartbeats from the new lease: %d, host_vlan %r" % (len(hb2), {h["host_vlan"] for d, h in hb2}))
    elif hb2[-1][1]["kbd_udp"] != (1 << 10) | (1 << 63) or hb2[-1][1]["addr_src"] != 1:
        err("phase 2 DUT0 heartbeat kbd_udp %x addr_src %d" % (hb2[-1][1]["kbd_udp"], hb2[-1][1]["addr_src"]))
    hb3 = [(d, h) for ph, d, h in hbs if ph == 3 and d["dut"] == 0]
    if not hb3:
        err("no DUT0 heartbeats after switching back")
    else:
        d, h = hb3[-1]
        if h["host_vlan"] != 0 or h["host_vlan_drops"] != DROPS or d["ip_src"] != FALLBACK[0] or h["addr_src"] != 2:
            err("last heartbeat host_vlan %d drops %d (want %d) from %s addr_src %d" %
                (h["host_vlan"], h["host_vlan_drops"], DROPS, d["ip_src"].hex(), h["addr_src"]))
        if h["rx_rejects"]:
            err("rx_rejects %d (VLAN drops must not count as rejects)" % h["rx_rejects"])
    print("phases: switch to %d at frame %d, back at frame %d; %d frames tagged" %
          (VID, i_on, i_off, sum(1 for d in ds if d["vid"])))
    print("DHCP REQUESTs %r" % [(p, v, ".".join(map(str, ip))) for p, v, ip in reqs])
    print("snapshots with HI (phase, VID): %r" % hi[:3])
    return report(errors, frames)


def report(errors, frames):
    print("captured %d frames" % len(frames))
    for e in errors:
        print("ERROR:", e)
    print("host_vlan check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
