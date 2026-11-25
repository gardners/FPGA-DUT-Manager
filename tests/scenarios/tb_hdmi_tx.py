"""Checker for tb_hdmi_tx (issue 0037, HDMI OUT InfoFrames).

gen:   nothing to generate (the testbench drives its own video and SPD
       machine schedule); writes an empty vector file.
check: every packet the testbench decoded from the TMDS lanes:
       * BCH ECC of the header (BCH(32,24)) and the four subpackets
         (BCH(64,56)), recomputed here by polynomial long division with
         G(x) = x^8 + x^7 + x^6 + 1 on the bit stream in transmission order
         (an independent formulation of the LFSR in hdmi_framer);
       * InfoFrame checksum;
       * AVI: version 2, RGB, full range, IT content, VIC 3, 16:9;
       * SPD: vendor "MEGA65", product "MEGA KVM M03", "MEGA KVM" and
         "MEGA KVM M27" all seen (the schedule in the testbench), source 0x09;
       * AVI and SPD each about once per frame.
"""
import sys

G = 0b111000001  # x^8 + x^7 + x^6 + 1


def bits_lsb_first(data):
    for byte in data:
        for k in range(8):
            yield (byte >> k) & 1


def bch_parity(data):
    """Remainder of M(x) * x^8 mod G(x); the first transmitted bit is the
    highest-order coefficient. Returns the parity byte in transmission order
    (bit k of the result = k-th transmitted parity bit)."""
    reg = 0
    for b in bits_lsb_first(data):
        reg = (reg << 1) | b
        if reg & 0x100:
            reg ^= G
    for _ in range(8):
        reg <<= 1
        if reg & 0x100:
            reg ^= G
    # coefficient of x^7 is transmitted first
    return sum(((reg >> (7 - k)) & 1) << k for k in range(8))


def gen(path):
    open(path, "w").close()


def check(path):
    errs = []
    pkts, stat = [], None
    for line in open(path):
        f = line.split()
        if f and f[0] == "PKT":
            pkts.append(bytes(int(x, 16) for x in f[1:]))
        elif f and f[0] == "STAT":
            stat = dict(kv.split("=") for kv in f[1:])
    if stat is None:
        return ["no STAT line"]
    print("testbench:", stat)
    products = []
    n_avi = n_spd = 0
    for p in pkts:
        if len(p) != 36:
            errs.append("packet length %d" % len(p))
            continue
        hb, subs = p[0:3], [p[4 + 8 * i:11 + 8 * i] for i in range(4)]
        if bch_parity(hb) != p[3]:
            errs.append("header ECC %02X != %02X" % (p[3], bch_parity(hb)))
        for i in range(4):
            if bch_parity(subs[i]) != p[11 + 8 * i]:
                errs.append("subpacket %d ECC" % i)
        pb = b"".join(subs)
        if (sum(hb) + sum(pb)) & 0xFF:
            errs.append("checksum")
        if hb == b"\x82\x02\x0d":
            n_avi += 1
            want = {1: 0x12, 2: 0x28, 3: 0x88, 4: 3, 5: 0}
            for k, v in want.items():
                if pb[k] != v:
                    errs.append("AVI PB%d = %02X, want %02X" % (k, pb[k], v))
            if any(pb[6:28]):
                errs.append("AVI bar data not zero")
        elif hb == b"\x83\x01\x19":
            n_spd += 1
            vendor = pb[1:9].rstrip(b"\0").decode("ascii")
            product = pb[9:25].rstrip(b"\0").decode("ascii")
            if vendor != "MEGA65":
                errs.append("SPD vendor %r" % vendor)
            if pb[25] != 0x09:
                errs.append("SPD source %02X" % pb[25])
            if product not in products:
                products.append(product)
        else:
            errs.append("unexpected packet header %s" % hb.hex())
    print("AVI x%d, SPD x%d, products %r" % (n_avi, n_spd, products))
    if products != ["MEGA KVM M03", "MEGA KVM", "MEGA KVM M27"]:
        errs.append("SPD products %r" % products)
    frames = int(stat["lines"]) // 8
    for name, n in (("AVI", n_avi), ("SPD", n_spd)):
        if abs(n - frames) > 1:
            errs.append("%s sent %d times in %d frames" % (name, n, frames))
    if int(stat["errors"]):
        errs.append("testbench errors")
    return errs


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        e = check(sys.argv[2])
        for m in e:
            print("FAIL:", m)
        print("tb_hdmi_tx check: %s" % ("PASSED" if not e else "FAILED"))
        sys.exit(1 if e else 0)
