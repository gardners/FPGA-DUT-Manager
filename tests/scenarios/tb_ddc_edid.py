"""Vectors and checker for tb_ddc_edid (issue 0033 EDID emulation).

gen:   the EDID from scripts/gen_edid.py, one hex byte per line (the testbench
       compares what it reads over I2C against it, so a stale
       hdl/src/video/edid_pkg.vhd fails the test).
check: decode the bytes the I2C master read back: header, checksums, version,
       DTD1 = 720x480 (858x525) @ 27 MHz -H -V, DTD2 = 720x576 (864x625)
       @ 27 MHz -H -V, range limits, monitor name, CEA-861 extension with
       VICs 2, 3, 17, 18 and no HDMI VSDB (we are a DVI sink).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "scripts"))
import gen_edid as G  # noqa: E402


def gen(path):
    with open(path, "w") as fh:
        for b in G.edid():
            fh.write("%02X\n" % b)


def check_edid(e):
    errs = []

    def want(cond, msg):
        if not cond:
            errs.append(msg)

    want(len(e) == 256, "length %d" % len(e))
    want(e[:8] == b"\x00\xFF\xFF\xFF\xFF\xFF\xFF\x00", "header")
    for blk in (0, 1):
        want(sum(e[blk * 128:(blk + 1) * 128]) & 0xFF == 0, "block %d checksum" % blk)
    want(e[18:20] == b"\x01\x03", "EDID version %d.%d" % (e[18], e[19]))
    want(e[20] & 0x80, "not a digital input")
    want(e[24] & 0x02, "preferred timing bit clear")
    want(e[35:38] == bytes(3), "established timings present")
    want(e[38:54] == b"\x01" * 16, "standard timings present")
    want(e[126] == 1, "extension count %d" % e[126])
    expect = [(27_000_000, 720, 858, 480, 525, False, False),
              (27_000_000, 720, 864, 576, 625, False, False)]
    for i, x in enumerate(expect):
        got = G.decode_dtd(e[54 + 18 * i:72 + 18 * i])
        want(got == x, "DTD%d %r != %r" % (i + 1, got, x))
        pclk, ha, ht, va, vt = got[:5]
        print("DTD%d: %dx%d, total %dx%d, %.3f MHz, %.2f Hz, %.2f kHz"
              % (i + 1, ha, va, ht, vt, pclk / 1e6, pclk / ht / vt, pclk / ht / 1e3))
    d3, d4 = e[90:108], e[108:126]
    want(d3[:5] == b"\0\0\0\xFD\0" and list(d3[5:10]) == [50, 60, 31, 32, 3], "range limits")
    want(d4[:5] == b"\0\0\0\xFC\0", "no monitor name descriptor")
    name = d4[5:].split(b"\n")[0].decode("ascii")
    want(name == "MEGA KVM", "monitor name %r" % name)
    x = e[128:]
    want(x[0] == 0x02 and x[1] == 0x03, "CEA-861 extension tag/revision")
    vics, oui = [], []
    i = 4
    while i < x[2]:
        tag, n = x[i] >> 5, x[i] & 0x1F
        if tag == 2:
            vics += [v & 0x7F for v in x[i + 1:i + 1 + n]]
        if tag == 3:
            oui.append(x[i + 1:i + 4])
        i += 1 + n
    want(sorted(vics) == [2, 3, 17, 18], "VICs %r" % vics)
    want(not oui, "vendor-specific block present (HDMI sink?)")
    print("EDID: %r, VICs %r, %s" % (name, vics, "OK" if not errs else "; ".join(errs)))
    return errs


def check(path):
    e = bytes(int(ln, 16) for ln in open(path) if ln.strip())
    errs = check_edid(e)
    for m in errs:
        print("FAIL:", m)
    return 1 if errs else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
