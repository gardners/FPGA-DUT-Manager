#!/usr/bin/env python3
"""Cross-check the C PNG writer (issue 0042) with Python's zlib: the test
image written by test_main is 720x480 with R = x, G = y, B = x ^ y."""
import struct
import sys
import zlib


def main(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "signature"
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        (n,) = struct.unpack(">I", data[pos:pos + 4])
        typ, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + n]
        (crc,) = struct.unpack(">I", data[pos + 8 + n:pos + 12 + n])
        assert crc == zlib.crc32(typ + body), f"CRC of {typ}"
        if typ == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, ctype, _, _, _ = ihdr
    assert (w, h, depth, ctype) == (720, 480, 8, 2), ihdr
    raw = zlib.decompress(idat)
    assert len(raw) == h * (1 + 3 * w)
    for y in range(h):
        row = raw[y * (1 + 3 * w):(y + 1) * (1 + 3 * w)]
        assert row[0] == 0
        exp = bytes(v for x in range(w) for v in (x & 255, y & 255, (x ^ y) & 255))
        assert row[1:] == exp, f"row {y}"
    try:  # optional: PIL agrees too
        from PIL import Image
        im = Image.open(path)
        assert im.size == (720, 480) and im.mode == "RGB" and im.getpixel((300, 7)) == (300 & 255, 7, (300 ^ 7) & 255)
        how = "zlib + PIL"
    except ImportError:
        how = "zlib"
    print(f"check_png: {path} ok ({how})")


if __name__ == "__main__":
    main(sys.argv[1])
