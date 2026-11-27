"""VLAN identity (issue 0063): input frames for tb_vlan_ident and the check
of its captured output.

  python3 -I tests/scenarios/tb_vlan_ident.py gen   <out.txt>
  python3 -I tests/scenarios/tb_vlan_ident.py check <captured.txt>

DIP = 0x35: board number B = 3, so the identity is 10.231.50.19 (key 0x0047
default base 10.231.50.0 + 16 + 3) at DUT0's MAC 02:4d:36:35:00:05 on VID
1650 (key 0x0043 default).

  1 before any address (no DHCP server, fallback not yet taken): tagged ARP
    and ping for the identity answered tagged from it; untagged, VID 1651,
    wrong destination MAC and another board's identity ignored.
  2 fallback addresses: host-side ARP/ICMP unchanged (untagged, from the
    fallback address; tagged ARP for it dropped while key 0x0046 is 0);
    identity still answered; key 0x0047 bad value / bad length / new base
    192.168.99.0 (identity moves to .19 there, the old one is ignored).
  3 key 0x0043 = 0: identity off (tagged and untagged ARP ignored).
  4 base back, key 0x0043 = 1650 and key 0x0046 = 1650 (host traffic on the
    same VID): identity and the endpoint both answered on VID 1650, each
    from its own address.
Heartbeats (network block bytes 200..207): vlan_ip, vlan (key 0x0043),
vlan_hits per phase.
"""
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import netproto as P  # noqa: E402

VID = 1650
HOST_MAC = P.mac("02:00:00:00:00:01")
HOST_IP = P.ip("192.168.65.1")
BOB_MAC = P.mac("02:00:00:00:00:b0")
BOB_IP = P.ip("10.231.50.1")               # bob's eno2.1650
BCAST = b"\xff" * 6
DUT_MAC = [bytes([0x02, 0x4D, 0x36, 0x35, 0x00, d]) for d in (0x05, 0x13)]
FALLBACK = [P.ip("192.168.65.21"), P.ip("192.168.65.35")]
VIP = P.ip("10.231.50.19")
VIP_OTHER = P.ip("10.231.50.20")           # board 4's identity
BASE2 = P.ip("192.168.99.0")
VIP2 = P.ip("192.168.99.19")
HITS = 6
DROPS = 7   # VID 1651 ARP + ping, wrong MAC, other board, tagged ARP for FB0, old identity, identity off


def tag(frame, vid):
    return P.with_fcs(P.vlan_tag(frame, vid))


def arp(tpa, spa=BOB_IP, sha=BOB_MAC):
    return P.eth(BCAST, sha, 0x0806, P.arp_request(sha, spa, tpa))


def ping(dst, seq, src=BOB_IP, smac=BOB_MAC, dmac=DUT_MAC[0]):
    return P.eth(dmac, smac, 0x0800, P.ipv4(src, dst, 1, P.icmp_echo(0x0063, seq, bytes(range(16)))))


def mgmt(cmd, key, value, dst=FALLBACK[0]):
    return P.eth(DUT_MAC[0], HOST_MAC, 0x0800,
                 P.ipv4(HOST_IP, dst, 17, P.udp(40000, P.PORT_MGMT, P.mgmt_set(0, cmd, key, value))))


def scenario():
    u = P.with_fcs
    f = []
    # 1: no address yet
    f.append((5, tag(arp(VIP), VID)))                                       # reply from VIP
    f.append((5, tag(ping(VIP, 1), VID)))                                   # reply from VIP
    f.append((5, u(arp(VIP))))                                              # ignored (untagged)
    f.append((5, u(ping(VIP, 90))))                                         # ignored (untagged)
    f.append((5, tag(arp(VIP), VID + 1)))                                   # ignored (VID 1651)
    f.append((5, tag(ping(VIP, 91), VID + 1)))                              # ignored (VID 1651)
    f.append((5, tag(ping(VIP, 92, dmac=DUT_MAC[1]), VID)))                 # ignored (not the board MAC)
    f.append((5, tag(arp(VIP_OTHER), VID)))                                 # ignored (board 4)
    # 2: fallback addresses
    f.append((3000, u(mgmt(1, 0x0050, struct.pack(">H", 1)))))              # hb period 1 ms
    f.append((5, u(arp(FALLBACK[0], HOST_IP, HOST_MAC))))                   # host side: untagged reply
    f.append((5, u(ping(FALLBACK[0], 2, HOST_IP, HOST_MAC))))               # host side: untagged reply
    f.append((5, tag(arp(FALLBACK[0]), VID)))                               # dropped (key 0x0046 = 0)
    f.append((5, tag(ping(VIP, 3), VID)))                                   # reply from VIP
    f.append((1500, u(mgmt(2, P.K_VLAN_BASE, P.ip("10.231.50.5")))))        # bad value
    f.append((5, u(mgmt(3, P.K_VLAN_BASE, b"\x0a\xe7\x32"))))               # bad length
    f.append((5, u(mgmt(4, P.K_VLAN_BASE, BASE2))))                         # ok
    f.append((50, tag(arp(VIP2), VID)))                                     # reply from VIP2
    f.append((5, tag(arp(VIP), VID)))                                       # ignored (old identity)
    # 3: identity off
    f.append((1500, u(mgmt(5, P.K_VLAN, b"\x00\x00"))))
    f.append((50, tag(arp(VIP2), VID)))                                     # ignored
    f.append((5, u(arp(VIP2))))                                             # ignored
    # 4: back on, host VLAN on the same VID
    f.append((1500, u(mgmt(6, P.K_VLAN_BASE, P.ip("10.231.50.0")))))
    f.append((5, u(mgmt(7, P.K_VLAN, struct.pack(">H", VID)))))
    f.append((5, u(mgmt(8, P.K_HOST_VLAN, struct.pack(">H", VID)))))
    f.append((3000, tag(arp(VIP), VID)))                                    # reply from VIP
    f.append((5, tag(arp(FALLBACK[0]), VID)))                               # reply from FB0 (host path)
    f.append((5, tag(ping(VIP, 4), VID)))                                   # reply from VIP
    f.append((5, tag(ping(FALLBACK[0], 5), VID)))                           # reply from FB0
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
    err = errors.append
    ds = [P.parse_frame_vlan(f) for f in frames]
    for i, d in enumerate(ds):
        if not d["fcs_ok"] or d.get("ip_ok") is False:
            err("frame %d: bad FCS / IP checksum" % i)
        if d["vid"] not in (0, VID):
            err("frame %d: VID %d" % (i, d["vid"]))

    def udp(d, ptype=None):
        return d.get("kind") == "udp" and (ptype is None or d.get("ptype") == ptype)

    acks = [(i, P.decode_ack(d["body"]), d) for i, d in enumerate(ds) if udp(d, P.T_MGMT_ACK)]
    got = [(a["cmd_id"], a["key"], a["status"], d["vid"], d["ip_src"]) for _, a, d in acks]
    fb = FALLBACK[0]
    want = [(1, 0x0050, 0, 0, fb), (2, P.K_VLAN_BASE, 3, 0, fb), (3, P.K_VLAN_BASE, 2, 0, fb),
            (4, P.K_VLAN_BASE, 0, 0, fb), (5, P.K_VLAN, 0, 0, fb), (6, P.K_VLAN_BASE, 0, 0, fb),
            (7, P.K_VLAN, 0, 0, fb), (8, P.K_HOST_VLAN, 0, 0, fb)]
    if got != want:
        err("MGMT acks (cmd, key, status, VID, src) %r != %r" % (got, want))
        return report(errors, frames)
    ia = [i for i, _, _ in acks]

    def phase(i):
        return 1 if i < ia[0] else 2 if i < ia[4] else 3 if i < ia[7] else 4

    arps = [(phase(i), d["vid"], d["src"], d["sha"], d["spa"], d["dst"], d["tpa"], d["oper"])
            for i, d in enumerate(ds) if d.get("kind") == "arp"]
    m0 = DUT_MAC[0]
    want = [(1, VID, m0, m0, VIP, BOB_MAC, BOB_IP, 2),
            (2, 0, m0, m0, fb, HOST_MAC, HOST_IP, 2),
            (2, VID, m0, m0, VIP2, BOB_MAC, BOB_IP, 2),
            (4, VID, m0, m0, VIP, BOB_MAC, BOB_IP, 2),
            (4, VID, m0, m0, fb, BOB_MAC, BOB_IP, 2)]
    if arps != want:
        err("ARP replies (phase, VID, src, sha, spa, dst, tpa, oper)\n  %r\n  != %r" % (arps, want))
    icmps = [(phase(i), d["vid"], d["src"], d["dst"], d["ip_src"], d["ip_dst"],
              struct.unpack(">H", d["icmp"][6:8])[0]) for i, d in enumerate(ds) if d.get("kind") == "icmp"]
    want = [(1, VID, m0, BOB_MAC, VIP, BOB_IP, 1),
            (2, 0, m0, HOST_MAC, fb, HOST_IP, 2),
            (2, VID, m0, BOB_MAC, VIP, BOB_IP, 3),
            (4, VID, m0, BOB_MAC, VIP, BOB_IP, 4),
            (4, VID, m0, BOB_MAC, fb, BOB_IP, 5)]
    if icmps != want:
        err("ICMP replies (phase, VID, src, dst, ip_src, ip_dst, seq)\n  %r\n  != %r" % (icmps, want))
    if any(d["icmp"][0] != 0 or not d["icmp_ok"] or d["icmp"][8:] != bytes(range(16))
           for d in ds if d.get("kind") == "icmp"):
        err("ICMP reply type / checksum / data")

    # heartbeats: network block bytes 200..207
    hbs = [(i, d, P.decode_heartbeat(d["body"])) for i, d in enumerate(ds)
           if udp(d, P.T_HEARTBEAT) and d["dut"] == 0]
    if not hbs or any("vlan_ip" not in h for _, _, h in hbs):
        err("DUT0 heartbeats without the VLAN identity fields")
        return report(errors, frames)
    # (first ack, next ack): what heartbeats in between carry
    spans = [(0, 3, VIP, VID), (3, 4, VIP2, VID), (4, 5, bytes(4), 0), (7, None, VIP, VID)]
    for a, b, ip, vid in spans:
        sel = [h for i, d, h in hbs if i > ia[a] and (b is None or i < ia[b])]
        if not sel:
            err("no DUT0 heartbeat after ack %d" % (a + 1))
        elif any(h["vlan_ip"] != ip or h["vlan"] != vid for h in sel):
            err("heartbeats after ack %d: vlan_ip/vlan %r (want %s/%d)" %
                (a + 1, {(".".join(map(str, h["vlan_ip"])), h["vlan"]) for h in sel},
                 ".".join(map(str, ip)), vid))
    last = hbs[-1][2]
    if last["vlan_hits"] != HITS or last["host_vlan_drops"] != DROPS or last["host_vlan"] != VID:
        err("last heartbeat vlan_hits %d (want %d) host_vlan_drops %d (want %d) host_vlan %d" %
            (last["vlan_hits"], HITS, last["host_vlan_drops"], DROPS, last["host_vlan"]))
    if last["rx_rejects"]:
        err("rx_rejects %d" % last["rx_rejects"])
    print("ARP replies %d, ICMP replies %d, DUT0 heartbeats %d, last vlan_ip %s hits %d" %
          (len(arps), len(icmps), len(hbs), ".".join(map(str, last["vlan_ip"])), last["vlan_hits"]))
    return report(errors, frames)


def report(errors, frames):
    print("captured %d frames" % len(frames))
    for e in errors:
        print("ERROR:", e)
    print("vlan_ident check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
