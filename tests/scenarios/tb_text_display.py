"""Vectors and checker for tb_text_display (ADR 0012 text display)."""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import netproto as P  # noqa: E402

FONT = open(os.path.join(os.path.dirname(os.path.dirname(HERE)),
                         "third_party/fonts/cp437-8x16.bin"), "rb").read()
MAC = [bytes([2, 0x4D, 0x36, 0x35, 0, d]) for d in (0, 1)]
HOST = P.mac("02:00:00:00:00:01")
VGA = [0x000000, 0x0000AA, 0x00AA00, 0x00AAAA, 0xAA0000, 0xAA00AA, 0xAA5500, 0xAAAAAA,
       0x555555, 0x5555FF, 0x55FF55, 0x55FFFF, 0xFF5555, 0xFF55FF, 0xFFFF55, 0xFFFFFF]


def text_write(addr, data, mac=MAC[0], port=6508):
    payload = P.custom(0x50, 0xFF, struct.pack(">HH", addr, 0) + data)
    return P.with_fcs(P.eth(mac, HOST, 0x0800,
                            P.ipv4(P.ip("10.0.0.1"), P.ip("10.0.0.2"), 17, P.udp(5000, port, payload))))


def model():
    chars = [i % 256 for i in range(2000)]
    attrs = [(i * 7) % 256 for i in range(2000)]
    pal = list(VGA)
    pal[1] = 0x123456
    pal[14] = 0xFEDCBA
    return chars, attrs, pal


def frames():
    chars, attrs, pal = model()
    blob = bytes(chars) + bytes(48) + bytes(attrs) + bytes(48) + \
        b"".join(struct.pack(">I", c)[1:] for c in VGA) + b"\x00"
    f = [(5, text_write(0, blob))]                       # whole screen, jumbo
    f.append((5, text_write(80, b"HELLO")))              # row 1, non-jumbo
    f.append((5, text_write(0x1000 + 3, bytes([0x12, 0x34, 0x56]), mac=MAC[1])))  # palette 1 via DUT1 MAC
    f.append((5, text_write(0x1000 + 42, bytes([0xFE, 0xDC, 0xBA]))))              # palette 14
    f.append((5, text_write(0, b"XXXX", port=6507)))     # wrong port: ignored
    f.append((5, text_write(0, b"XXXX", mac=P.mac("02:4d:36:35:00:09"))))  # wrong MAC: ignored
    return f


def expected():
    chars, attrs, pal = model()
    chars[80:85] = list(b"HELLO")
    img = [[0] * 720 for _ in range(480)]
    for y in range(40, 440):
        row, cy = divmod(y - 40, 16)
        for x in range(720):
            col, cx = divmod(x, 9)
            i = row * 80 + col
            c, a = chars[i], attrs[i]
            glyph = FONT[(cy & 1) * 2048 + c * 8 + (cy >> 1)]
            if cx < 8:
                bit = (glyph >> (7 - cx)) & 1
            else:
                bit = glyph & 1 if 0xC0 <= c <= 0xDF else 0
            img[y][x] = pal[a & 15] if bit else pal[a >> 4]
    return img


def gen(path):
    with open(path, "w") as fh:
        for delay, fr in frames():
            fh.write("%d %d %s\n" % (delay, len(fr), " ".join("%02x" % b for b in fr)))


def check(path):
    rows = [ln.split() for ln in open(path)]
    errs = 0
    if len(rows) != 480 or any(len(r) != 720 for r in rows):
        print("ERROR: frame size %d x %s" % (len(rows), set(len(r) for r in rows)))
        return 1
    exp = expected()
    for y in range(480):
        for x in range(720):
            got = int(rows[y][x], 16)
            if got != exp[y][x]:
                errs += 1
                if errs <= 10:
                    print("ERROR: pixel (%d,%d) got %06x want %06x" % (x, y, got, exp[y][x]))
    print("text frame compare: %d mismatching pixels" % errs)
    print("tb_text_display check", "FAILED" if errs else "PASSED")
    return 1 if errs else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
