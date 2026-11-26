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
T_RASTER = 0x60
K_PK_LED_MODE, K_PK_LED_HOST = 0x0033, 0x0034  # physical keyboard LEDs (ADR 0005 s4)
K_CON_SCREEN = 0x0035  # console screen: 0 auto, 1 editable, 2 no video, 3 select
K_PK_JTAG = 0x0061  # physical keyboard CPLD JTAG: 0 auto, 1 force on, 2 force off (ADR 0014)
# JTAG_REQ flags (offset 18): b0 abort/reset session, b1 target = physical
# keyboard CPLD (ADR 0014); JTAG_RESP byte 17 = target (0 DUT, 1 keyboard)
JF_ABORT, JF_KBD = 0x0001, 0x0002
JT_DUT, JT_KBD = 0, 1
# heartbeat capabilities (byte 32)
CAP_UART, CAP_JTAG, CAP_KBD_DEV, CAP_PHYS_KBD, CAP_HDMI, CAP_THUMBS, CAP_KBD_JTAG = \
    0x01, 0x02, 0x04, 0x08, 0x10, 0x80, 0x100
# heartbeat byte 76 kbd_phys_type
PHYS_TYPES = {0: "none", 1: "MK-I", 2: "MK-II", 3: "type3"}
# heartbeat byte 109, what HDMI OUT shows (issues 0029, 0032)
CON_SHOWN = {0: "editable", 1: "no-video", 2: "select", 3: "passthrough"}
CON_PASSTHROUGH = 3
# heartbeat byte 108 video_flags (ADR 0005 s8; b3/b4 issue 0040)
VF_CLOCK, VF_LOCKED, VF_CAPTURE, VF_HDMI, VF_ISLANDS = 0x01, 0x02, 0x04, 0x08, 0x10
PORT_MGMT, PORT_HB, PORT_KBD, PORT_UART, PORT_JTAG = 6500, 6501, 6502, 6503, 6507
PORT_RASTER = 6504
# raster flags (ADR 0005 section 8)
RF_VSYNC, RF_VPOL, RF_HPOL, RF_ACTIVE, RF_FIRST, RF_DROPPED, RF_LOCKED = 1, 2, 4, 8, 16, 32, 64
ENC_RAW, ENC_RLE24 = 0, 1


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
    f["addr_src"], f["dut_id"] = b[98], b[99]
    if len(b) >= 124:  # video block (ADR 0005 section 8), bytes 108..131 of the datagram
        (f["video_flags"], f["console_screen"], f["h_total"], f["v_total"], f["h_active"], f["v_active"],
         f["pixel_clock_hz"], f["frames_captured"], f["raster_lines_dropped"],
         f["tmds_decode_errors"], _) = struct.unpack(">BBHHHHIIHHH", b[100:124])
    if len(b) >= 132:  # link block (ADR 0005 section 3a), bytes 132..139 of the datagram
        (f["rx_phase_pos"], f["rx_eye_width"], f["rx_hunts"], f["rx_bad_frames"],
         f["rx_link_flags"]) = struct.unpack(">BBHHBx", b[124:132])
    if len(b) >= 144:  # memory block (ADR 0005 section 3b), bytes 140..151 of the datagram
        (f["mem_flags"], f["mem_errors"], f["mem_dq_fail"], f["mem_test_kib"],
         f["mem_first_err"]) = struct.unpack(">BxHHHI", b[132:144])
    return f


MEM_FIELDS = ("mem_flags", "mem_errors", "mem_dq_fail", "mem_test_kib", "mem_first_err")
# mem_flags bits: b0 DDR3 calibrated, b1 self-test running, b2 self-test done,
# b3 self-test passed (valid when done)
MEM_CALIBRATED, MEM_ST_RUNNING, MEM_ST_DONE, MEM_ST_PASS = 1, 2, 4, 8

LINK_FIELDS = ("rx_phase_pos", "rx_eye_width", "rx_hunts", "rx_bad_frames", "rx_link_flags")

VIDEO_FIELDS = ("video_flags", "h_total", "v_total", "h_active", "v_active", "pixel_clock_hz",
                "frames_captured", "raster_lines_dropped", "tmds_decode_errors")


def rle24_encode(pixels):
    """Raw RGB888 bytes -> RLE24 (count u8 1..255, R, G, B) tuples."""
    assert len(pixels) % 3 == 0
    out = bytearray()
    i, n = 0, len(pixels)
    while i < n:
        px = pixels[i:i + 3]
        c = 1
        while c < 255 and i + 3 * c < n and pixels[i + 3 * c:i + 3 * c + 3] == px:
            c += 1
        out += bytes([c]) + px
        i += 3 * c
    return bytes(out)


def rle24_decode(data):
    if len(data) % 4:
        raise ValueError("RLE24 length not a multiple of 4")
    out = bytearray()
    for i in range(0, len(data), 4):
        if data[i] == 0:
            raise ValueError("RLE24 count 0")
        out += data[i + 1:i + 4] * data[i]
    return bytes(out)


RASTER_VERSION = 1
RASTER_HDR = ">BBBxIHHHHHHHHI16s"  # 44 bytes after the common header (ADR 0005 s8)
RASTER_MAX_PX = 1024


def encode_raster(dut, frame, line, h_total, v_total, pixels, hs_start=0, hs_end=0, flags=0,
                  uart_rx_seq=0, uart_hist=b"", rle=False, v_active=0):
    """pixels: raw RGB888 bytes (empty for blanking lines). rle=True uses RLE24 only when
    strictly smaller than raw (ADR rule)."""
    assert len(pixels) % 3 == 0 and len(uart_hist) <= 16
    active = len(pixels) // 3
    enc, payload = ENC_RAW, pixels
    if rle and pixels:
        r = rle24_encode(pixels)
        if len(r) < len(pixels):
            enc, payload = ENC_RLE24, r
    hist = bytes(16 - len(uart_hist)) + uart_hist
    b = struct.pack(RASTER_HDR, RASTER_VERSION, enc, flags, frame, line, h_total, v_total,
                    active, v_active, hs_start, hs_end, len(payload), uart_rx_seq, hist)
    return custom(T_RASTER, dut, b + payload)


def decode_raster(b):
    """b: datagram body after the 8-byte common header. Returns dict incl. 'pixels'
    (always raw RGB888, RLE24 expanded)."""
    f = {}
    (f["version"], f["encoding"], f["flags"], f["frame"], f["line"], f["h_total"], f["v_total"],
     f["active_count"], f["v_active"], f["hs_start"], f["hs_end"], f["payload_bytes"],
     f["uart_rx_seq"], f["uart_rx_history"]) = struct.unpack(RASTER_HDR, b[:44])
    if f["version"] != RASTER_VERSION:
        raise ValueError("unknown raster format version %d" % f["version"])
    if f["active_count"] > RASTER_MAX_PX:
        raise ValueError("raster line wider than %d px" % RASTER_MAX_PX)
    data = b[44:44 + f["payload_bytes"]]
    if len(data) != f["payload_bytes"]:
        raise ValueError("raster payload truncated")
    f["pixels"] = rle24_decode(data) if f["encoding"] == ENC_RLE24 else data
    if len(f["pixels"]) != 3 * f["active_count"]:
        raise ValueError("raster pixel count != active_count")
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
    seq, nxt, status, target, nbytes, bits = struct.unpack(">IIBBHI", b[:16])
    return {"seq": seq, "next_seq": nxt, "status": status, "target": target, "tdo_bytes": nbytes,
            "bit_count": bits, "tdo": b[16:16 + nbytes]}


def decode_ack(b):
    cmd, key, status, _, gen = struct.unpack(">HHBBI", b[:10])
    return {"cmd_id": cmd, "key": key, "status": status, "cfg_gen": gen}


# ------------------------------------------------- FPGA -> host encoders (tests)
def encode_heartbeat(dut, f):
    b = struct.pack(">IIIQBBBBIIBBBB", f["hb_seq"], f["boot_id"], f["build_id"], f["dna"],
                    f["topo_index"], f["topo_count"], f["dip"], f["link_flags"], f["caps"],
                    f["cfg_gen"], f["target_flags"], f["kbd_owner"], f["kbd_policy"], f["selected"])
    b += f["kbd_eff"].to_bytes(10, "little") + f["kbd_udp"].to_bytes(10, "little") + \
        f["kbd_phys"].to_bytes(10, "little")
    b += struct.pack(">HBBIIIHH", f["phys_change"], f["phys_type"], f["jtag_status"],
                     f["jtag_next_seq"], f["uart_rx_seq"], f["uart_tx_acc"], f["rx_rejects"],
                     f["tx_drops"])
    b += f["dut_leds"] + bytes([f.get("addr_src", 0), f.get("dut_id", 0)])
    assert len(b) == 100
    if "video_flags" in f:  # optional video block -> 124-byte payload
        b += struct.pack(">BBHHHHIIHHH", f["video_flags"], f.get("console_screen", 0), f["h_total"], f["v_total"],
                         f["h_active"], f["v_active"], f["pixel_clock_hz"], f["frames_captured"],
                         f["raster_lines_dropped"], f["tmds_decode_errors"], 0)
    if "rx_phase_pos" in f:  # link block (needs the video block) -> 132-byte payload
        assert len(b) == 124
        b += struct.pack(">BBHHBB", f["rx_phase_pos"], f["rx_eye_width"], f["rx_hunts"],
                         f["rx_bad_frames"], f["rx_link_flags"], 0)
    if "mem_flags" in f:  # memory block (needs the link block) -> 144-byte payload
        assert len(b) == 132
        b += struct.pack(">BBHHHI", f["mem_flags"], 0, f["mem_errors"], f["mem_dq_fail"],
                         f["mem_test_kib"], f["mem_first_err"])
    return custom(T_HEARTBEAT, dut, b)


def encode_snapshot(dut, f):
    b = struct.pack(">IIIIIHHHHHIIH", f["boot_id"], f["snap_seq"], f["rx_seq"], f["tx_accepted"],
                    f["tx_emitted"], f["tx_free"], f["framing_errors"], f["rx_overflows"],
                    f["tx_rejects"], f["clear_gen"], f["rx_seq_at_clear"], f["baud_nco"], 0)
    b += f["rx_history"] + f["tx_history"]
    assert len(b) == 680
    return custom(T_UART_SNAP, dut, b)


def encode_jtag_resp(dut, seq, nxt, status, bits, tdo, target=JT_DUT):
    return custom(T_JTAG_RESP, dut, struct.pack(">IIBBHI", seq, nxt, status, target, len(tdo), bits) + tdo)


def encode_ack(dut, cmd, key, status, gen):
    return custom(T_MGMT_ACK, dut, struct.pack(">HHBBI", cmd, key, status, 0, gen))


# ------------------------------------------------------------------ DHCP
def dhcp_reply(msg_type, xid, yiaddr, chaddr, server, lease=3600):
    """BOOTREPLY with options 53, 54, 51, 1 (UDP payload)."""
    b = bytearray(236)
    b[0], b[1], b[2] = 2, 1, 6
    struct.pack_into(">I", b, 4, xid)
    b[16:20] = yiaddr
    b[28:34] = chaddr
    opts = bytes([53, 1, msg_type, 54, 4]) + server + bytes([51, 4]) + struct.pack(">I", lease) + \
        bytes([1, 4, 255, 255, 255, 0, 255])
    return bytes(b) + b"\x63\x82\x53\x63" + opts


def parse_dhcp(p):
    """Decode a client DHCP message (UDP payload) -> dict with options."""
    d = {"op": p[0], "xid": struct.unpack(">I", p[4:8])[0], "flags": struct.unpack(">H", p[10:12])[0],
         "ciaddr": p[12:16], "chaddr": p[28:34], "cookie": p[236:240], "opts": {}, "len": len(p)}
    i = 240
    while i < len(p) and p[i] != 255:
        if p[i] == 0:
            i += 1
            continue
        d["opts"][p[i]] = p[i + 2:i + 2 + p[i + 1]]
        i += 2 + p[i + 1]
    return d


# ------------------------------------------- thumbnail relay (ADR 0005 s10)
# Raw Ethernet, EtherType 0x88B5 (IEEE local experimental), issue 0038.
ETH_THUMB = 0x88B5
TH_VERSION = 1
TH_SUB_REQ, TH_SUB_LINES, TH_SUB_NOSRC = 1, 2, 3
TH_SCALE_HALF, TH_SCALE_QUARTER = 1, 2      # 320x200 / 160x100 tiles
TH_ENC_RAW, TH_ENC_RLE24 = 0, 1             # RAW888 / RLE24 (as raster)
TH_FLAG_PRESENT, TH_FLAG_LAST = 1, 2
TH_HDR = ">BBHBBBBIHHHHH"                   # 22 bytes after the Ethernet header
TH_REQ = ">BBHBBH"                          # 8 bytes
TH_PKT_BUDGET = 8000                        # payload bytes per frame (FPGA packing)
BCAST_MAC = b"\xff" * 6


def thumb_tile_size(scale):
    return (320, 200) if scale == TH_SCALE_HALF else (160, 100)


def thumb_request(src, scale=TH_SCALE_HALF, div=2):
    """Broadcast request frame (no FCS)."""
    return eth(BCAST_MAC, src, ETH_THUMB, struct.pack(TH_REQ, TH_VERSION, TH_SUB_REQ, MAGIC, scale, div, 0))


def thumb_line_bytes(line, enc):
    """One tile line (RGB888 bytes) in the given encoding."""
    return line if enc == TH_ENC_RAW else rle24_encode(line)


def thumb_frame(dst, src, machine, frame, row, lines, scale, height, enc=None, flags=TH_FLAG_PRESENT):
    """Lines frame (no FCS). lines: list of RGB888 byte strings (one tile row
    each). enc None = RLE24 when the RLE24 bytes of all lines are fewer."""
    width = thumb_tile_size(scale)[0]
    assert all(len(x) == 3 * width for x in lines)
    if enc is None:
        enc = TH_ENC_RLE24 if sum(len(rle24_encode(x)) for x in lines) < sum(len(x) for x in lines) \
            else TH_ENC_RAW
    pl = b"".join(thumb_line_bytes(x, enc) for x in lines)
    hdr = struct.pack(TH_HDR, TH_VERSION, TH_SUB_LINES, MAGIC, machine, flags, scale, enc, frame,
                      row, len(lines), width, height, len(pl))
    return eth(dst, src, ETH_THUMB, hdr + pl)


def thumb_nosrc(dst, src, machine):
    hdr = struct.pack(TH_HDR, TH_VERSION, TH_SUB_NOSRC, MAGIC, machine, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    return eth(dst, src, ETH_THUMB, hdr)


def thumb_packets(dst, src, machine, frame, tile, scale, budget=TH_PKT_BUDGET):
    """The FPGA's packing (thumb_tx): per line RLE24 when strictly smaller
    than RAW888; lines are packed while the encoding stays the same and the
    payload stays within budget. tile: list of RGB888 rows. Flag b1 marks the
    picture's last frame."""
    out, cur, cur_enc, size = [], [], None, 0
    first = 0
    for i, line in enumerate(tile):
        r = rle24_encode(line)
        enc, n = (TH_ENC_RLE24, len(r)) if len(r) < len(line) else (TH_ENC_RAW, len(line))
        if cur and (enc != cur_enc or size + n > budget):
            out.append((first, cur, cur_enc))
            cur, size = [], 0
        if not cur:
            first, cur_enc = i, enc
        cur.append(line)
        size += n
    if cur:
        out.append((first, cur, cur_enc))
    return [thumb_frame(dst, src, machine, frame, f, ls, scale, len(tile), enc=e,
                        flags=TH_FLAG_PRESENT | (TH_FLAG_LAST if k == len(out) - 1 else 0))
            for k, (f, ls, e) in enumerate(out)]


def decode_thumb(body):
    """body: Ethernet payload (after the 14-byte header). Returns a dict; for
    lines frames 'lines' holds the decoded RGB888 rows."""
    if len(body) < 8:
        raise ValueError("thumbnail frame too short")
    ver, sub, magic = body[0], body[1], struct.unpack(">H", body[2:4])[0]
    if ver != TH_VERSION or magic != MAGIC:
        raise ValueError("not a thumbnail frame (version %d magic %04x)" % (ver, magic))
    if sub == TH_SUB_REQ:
        _, _, _, scale, div, _ = struct.unpack(TH_REQ, body[:8])
        return {"sub": sub, "scale": scale, "div": div}
    if len(body) < 22:
        raise ValueError("thumbnail frame too short")
    f = {}
    (_, f["sub"], _, f["machine"], f["flags"], f["scale"], f["enc"], f["frame"], f["row"],
     f["nlines"], f["width"], f["height"], f["payload_bytes"]) = struct.unpack(TH_HDR, body[:22])
    if f["sub"] != TH_SUB_LINES:
        return f
    data = body[22:22 + f["payload_bytes"]]
    if len(data) != f["payload_bytes"]:
        raise ValueError("thumbnail payload truncated")
    lines, i, w = [], 0, f["width"]
    for _ in range(f["nlines"]):
        if f["enc"] == TH_ENC_RAW:
            line, i = data[i:i + 3 * w], i + 3 * w
        else:
            line = bytearray()
            while len(line) < 3 * w:
                if i + 4 > len(data) or data[i] == 0:
                    raise ValueError("bad RLE24 tuple")
                line += data[i + 1:i + 4] * data[i]
                i += 4
            line = bytes(line)
        if len(line) != 3 * w:
            raise ValueError("thumbnail line length")
        lines.append(line)
    if i != len(data):
        raise ValueError("thumbnail payload has extra bytes")
    f["lines"] = lines
    return f


def thumb_box(pixel, x0, y0, s, w, h):
    """Reference S x S box average (truncating) of pixel(x, y) -> (r, g, b),
    as thumb_capture computes it. Returns a list of RGB888 rows."""
    rows = []
    for ty in range(h):
        row = bytearray()
        for tx in range(w):
            acc = [0, 0, 0]
            for j in range(s):
                for i in range(s):
                    p = pixel(x0 + s * tx + i, y0 + s * ty + j)
                    for c in range(3):
                        acc[c] += p[c]
            row += bytes(a // (s * s) for a in acc)
        rows.append(bytes(row))
    return rows
