"""Reference encoder/decoder for the FPGA-DUT-Manager wire protocol (ADR 0005).

Pure Python, no third-party modules. Used to generate simulation vectors and
to check frames captured from the VHDL testbenches.
"""
import struct
import zlib

MAGIC = 0x4D36
VERSION = 1
T_HEARTBEAT, T_MGMT_SET, T_MGMT_ACK = 0x01, 0x10, 0x11
T_KBD_SET, T_UART_TX, T_UART_SNAP = 0x20, 0x30, 0x31
T_JTAG_REQ, T_JTAG_RESP = 0x40, 0x41
PORT_MGMT, PORT_HB, PORT_KBD, PORT_UART, PORT_JTAG = 6500, 6501, 6502, 6503, 6507


def mac(s):
    return bytes(int(x, 16) for x in s.split(":"))


def ip(s):
    return bytes(int(x) for x in s.split("."))


def ip_csum(hdr):
    s = 0
    for i in range(0, len(hdr), 2):
        s += (hdr[i] << 8) | hdr[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def with_fcs(frame):
    if len(frame) < 60:
        frame = frame + bytes(60 - len(frame))
    return frame + struct.pack("<I", zlib.crc32(frame) & 0xFFFFFFFF)


def eth(dst, src, etype, payload):
    return dst + src + struct.pack(">H", etype) + payload


def ipv4(src, dst, proto, payload, ident=0):
    hdr = bytearray(struct.pack(">BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), ident,
                                0x4000, 64, proto, 0, src, dst))
    struct.pack_into(">H", hdr, 10, ip_csum(hdr))
    return bytes(hdr) + payload


def udp(sport, dport, payload):
    return struct.pack(">HHHH", sport, dport, 8 + len(payload), 0) + payload


def arp_request(sha, spa, tpa):
    return struct.pack(">HHBBH6s4s6s4s", 1, 0x0800, 6, 4, 1, sha, spa, bytes(6), tpa)


def icmp_echo(ident, seq, data):
    body = bytearray(struct.pack(">BBHHH", 8, 0, 0, ident, seq) + data)
    struct.pack_into(">H", body, 2, ip_csum(body + (b"\0" if len(body) % 2 else b"")))
    return bytes(body)


def custom(ptype, dut, payload, flags=0):
    return struct.pack(">HBBHBB", MAGIC, VERSION, ptype, len(payload), dut, flags) + payload


def mgmt_set(dut, cmd_id, key, value):
    return custom(T_MGMT_SET, dut, struct.pack(">HHH", cmd_id, key, len(value)) + value)


def kbd_set(dut, pressed_keys):
    bits = 0
    for k in pressed_keys:
        bits |= 1 << k
    return custom(T_KBD_SET, dut, bits.to_bytes(10, "little"))


def uart_tx(dut, offset, cmd_id, data, clear=False):
    return custom(T_UART_TX, dut,
                  struct.pack(">IHBBH", offset, cmd_id, 1 if clear else 0, 0, len(data)) + data)


def bits_to_bytes(bits):
    """bits: string of '0'/'1', first character = first bit shifted."""
    out = bytearray((len(bits) + 7) // 8)
    for i, c in enumerate(bits):
        if c == "1":
            out[i // 8] |= 1 << (i % 8)
    return bytes(out)


def jtag_req(dut, seq, tms, tdi, half=2, report_us=0, flags=0):
    assert len(tms) == len(tdi)
    return custom(T_JTAG_REQ, dut,
                  struct.pack(">IIHHI", seq, half, report_us, flags, len(tms)) +
                  bits_to_bytes(tms) + bits_to_bytes(tdi))


# ----------------------------------------------------------------- decoding
def parse_frame(f):
    """Return a dict describing an Ethernet frame (FCS stripped and checked)."""
    body, fcs = f[:-4], f[-4:]
    d = {"fcs_ok": struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF) == fcs,
         "dst": body[0:6], "src": body[6:12], "etype": struct.unpack(">H", body[12:14])[0]}
    if d["etype"] == 0x0806:
        (_, _, _, _, oper, sha, spa, tha, tpa) = struct.unpack(">HHBBH6s4s6s4s", body[14:42])
        d.update(kind="arp", oper=oper, sha=sha, spa=spa, tha=tha, tpa=tpa)
    elif d["etype"] == 0x0800:
        iph = body[14:34]
        total = struct.unpack(">H", iph[2:4])[0]
        d.update(ip_ok=ip_csum(iph) == 0, proto=iph[9], ip_src=iph[12:16], ip_dst=iph[16:20])
        l4 = body[34:14 + total]
        if iph[9] == 1:
            d.update(kind="icmp", icmp=l4, icmp_ok=ip_csum(l4 + (b"\0" if len(l4) % 2 else b"")) == 0)
        elif iph[9] == 17:
            sport, dport, ulen, _ = struct.unpack(">HHHH", l4[:8])
            p = l4[8:ulen]
            d.update(kind="udp", sport=sport, dport=dport, payload=p)
            if len(p) >= 8:
                magic, ver, ptype, plen, dut, flags = struct.unpack(">HBBHBB", p[:8])
                d.update(magic=magic, ver=ver, ptype=ptype, plen=plen, dut=dut, body=p[8:])
    return d


def decode_heartbeat(b):
    f = {}
    (f["hb_seq"], f["boot_id"], f["build_id"], f["dna"], f["topo_index"], f["topo_count"],
     f["dip"], f["link_flags"], f["caps"], f["cfg_gen"], f["target_flags"], f["kbd_owner"],
     f["kbd_policy"], f["selected"]) = struct.unpack(">IIIQBBBBIIBBBB", b[:36])
    f["kbd_eff"] = int.from_bytes(b[36:46], "little")
    f["kbd_udp"] = int.from_bytes(b[46:56], "little")
    f["kbd_phys"] = int.from_bytes(b[56:66], "little")
    (f["phys_change"], f["phys_type"], f["jtag_status"], f["jtag_next_seq"], f["uart_rx_seq"],
     f["uart_tx_acc"], f["rx_rejects"], f["tx_drops"]) = struct.unpack(">HBBIIIHH", b[66:86])
    f["dut_leds"] = b[86:98]
    return f


def decode_snapshot(b):
    f = {}
    (f["boot_id"], f["snap_seq"], f["rx_seq"], f["tx_accepted"], f["tx_emitted"], f["tx_free"],
     f["framing_errors"], f["rx_overflows"], f["tx_rejects"], f["clear_gen"], f["rx_seq_at_clear"],
     f["baud_nco"], _) = struct.unpack(">IIIIIHHHHHIIH", b[:40])
    f["rx_history"] = b[40:552]
    f["tx_history"] = b[552:680]
    return f


def decode_jtag_resp(b):
    seq, nxt, status, _, nbytes, bits = struct.unpack(">IIBBHI", b[:16])
    return {"seq": seq, "next_seq": nxt, "status": status, "tdo_bytes": nbytes,
            "bit_count": bits, "tdo": b[16:16 + nbytes]}


def decode_ack(b):
    cmd, key, status, _, gen = struct.unpack(">HHBBI", b[:10])
    return {"cmd_id": cmd, "key": key, "status": status, "cfg_gen": gen}
