"""Relay frames for tb_thumb_rx and the check of what was stored (issue 0038).

  python3 -I tests/scenarios/tb_thumb_rx.py gen   <in.txt>
  python3 -I tests/scenarios/tb_thumb_rx.py check <out.txt>
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import netproto as P  # noqa: E402

MAC0 = P.mac("02:4D:36:35:00:00")
MAC1 = P.mac("02:4D:36:35:00:11")
OTHER = P.mac("02:4D:36:35:00:05")
PEER = P.mac("02:4D:36:35:00:22")
HOST = P.mac("02:00:00:00:00:aa")


def tile(seed, w, h):
    """Rows mixing solid runs (RLE wins) and noise (raw wins)."""
    rnd = random.Random(seed)
    rows = []
    for y in range(h):
        if y % 3 == 0:
            row = b"".join(bytes([rnd.randrange(256)] * 3) * 40 for _ in range(w // 40))
        elif y % 3 == 1:
            row = bytes(rnd.randrange(256) for _ in range(3 * w))
        else:   # half runs (some > 255 px), half noise
            row = bytes([10, 20, 30]) * (w // 2) + bytes(rnd.randrange(256) for _ in range(3 * (w - w // 2)))
        rows.append(row)
    return rows


T3 = {f: tile(f, 320, 6) for f in (7, 8, 9)}
T8 = tile(80, 160, 4)
T1 = tile(1, 160, 4)
T0 = tile(2, 160, 4)
VLAN = 1650
# 1/1 pictures (issue 0060): 50 x 5 (a partial last word), several frames
F1 = {f: [r + bytes([f, 2 * f, 3 * f]) * 10 for r in tile(100 + f, 40, 5)] for f in (1, 2, 3)}


def fcs(frames, bad=()):
    out = []
    for i, f in enumerate(frames):
        f = P.with_fcs(f)
        if i in bad:
            f = f[:-1] + bytes([f[-1] ^ 0x5A])
        out.append(f)
    return out


def scenario():
    f = []
    # untagged / other VID: dropped (VLAN 1650, issue 0060)
    f += fcs([P.thumb_request(OTHER, P.TH_SCALE_HALF, 1)])
    f += fcs([P.thumb_request(OTHER, P.TH_SCALE_HALF, 1, vlan=1651)])
    f += fcs(P.thumb_packets(MAC0, PEER, 9, 1, T8, P.TH_SCALE_QUARTER))
    f += fcs(P.thumb_packets(MAC0, PEER, 10, 1, T8, P.TH_SCALE_QUARTER, vlan=7))
    f += fcs([P.thumb_nosrc(MAC1, PEER, 13)])
    f += fcs([P.thumb_request(HOST, P.TH_SCALE_QUARTER, 3, vlan=VLAN)])
    # machine 3, 1/2 scale: frame 7 good (-> buffer 1), frame 8 with a bad
    # FCS on its second frame (never shown), frame 9 good (-> buffer 0)
    f += fcs(P.thumb_packets(MAC0, PEER, 3, 7, T3[7], P.TH_SCALE_HALF, budget=2000, vlan=VLAN))
    f += fcs(P.thumb_packets(MAC0, PEER, 3, 8, T3[8], P.TH_SCALE_HALF, budget=2000, vlan=VLAN), bad=(1,))
    f += fcs(P.thumb_packets(MAC0, PEER, 3, 9, T3[9], P.TH_SCALE_HALF, vlan=VLAN))
    # machine 8, 1/4 scale, raw only, to the other endpoint MAC
    f += fcs([P.thumb_frame(MAC1, PEER, 8, 1, 0, T8[:3], P.TH_SCALE_QUARTER, 4, enc=P.TH_ENC_RAW, vlan=VLAN),
              P.thumb_frame(MAC1, PEER, 8, 1, 3, T8[3:], P.TH_SCALE_QUARTER, 4, enc=P.TH_ENC_RLE24,
                            vlan=VLAN)])
    # this board's own machine 0 (local video): ignored (stored locally)
    f += fcs(P.thumb_packets(MAC0, PEER, 0, 1, T0, P.TH_SCALE_QUARTER, vlan=VLAN))
    # local machine 1 has no local video (issue 0060): its relayed picture is stored
    f += fcs(P.thumb_packets(MAC0, PEER, 1, 1, T1, P.TH_SCALE_QUARTER, vlan=VLAN))
    # another board's MAC: not for us
    f += fcs(P.thumb_packets(OTHER, PEER, 20, 1, T8, P.TH_SCALE_QUARTER, vlan=VLAN))
    # present, no source
    f += fcs([P.thumb_nosrc(MAC1, PEER, 12, vlan=VLAN)])
    # a request to another unicast MAC is not ours either
    f += fcs([P.vlan_tag(P.eth(OTHER, PEER, P.ETH_THUMB, P.thumb_request_body(1, 1)), VLAN)])
    # 1/1 pictures of machine 1 (full view): 1 complete (several frames),
    # 2 with a bad frame (never complete), 3 complete; machine 5's and an
    # untagged one are ignored
    f += fcs(P.thumb_packets(MAC0, PEER, 1, 1, F1[1], P.TH_SCALE_FULL, budget=200, vlan=VLAN))
    f += fcs(P.thumb_packets(MAC0, PEER, 5, 7, F1[2], P.TH_SCALE_FULL, budget=200, vlan=VLAN))
    f += fcs(P.thumb_packets(MAC0, PEER, 1, 2, F1[2], P.TH_SCALE_FULL, budget=200, vlan=VLAN), bad=(1,))
    f += fcs(P.thumb_packets(MAC0, PEER, 1, 3, F1[2], P.TH_SCALE_FULL, budget=200))
    f += fcs(P.thumb_packets(MAC0, PEER, 1, 3, F1[3], P.TH_SCALE_FULL, budget=200, vlan=VLAN))
    # the last request: targeted, priority, 1/1 (issue 0060)
    f += fcs([P.thumb_request(HOST, P.TH_SCALE_FULL, 1, P.TH_RF_TARGETED | P.TH_RF_PRIORITY, 5, vlan=VLAN)])
    return f


def gen(path):
    with open(path, "w") as fh:
        for frame in scenario():
            fh.write("5 %d %s\n" % (len(frame), " ".join("%02x" % b for b in frame)))


def row_pixels(words):
    out = bytearray()
    for w in words:
        v = int(w, 16)
        for i in range(4):
            px = (v >> (32 * i)) & 0xFFFFFFFF
            if px >> 24:
                raise ValueError("top byte not zero")
            out += bytes([(px >> 16) & 255, (px >> 8) & 255, px & 255])
    return bytes(out)


def check(path):
    errors = []
    rows = {}
    with open(path) as fh:
        for line in fh:
            p = line.split()
            if p[0] == "status":
                cur, seen, fresh, quarter = (int(x, 16) for x in p[1:5])
                pics, nseen = int(p[5]), int(p[6])
            elif p[0] == "req":
                nreq, rmac, rsc, rdv, rfl, rtg = (int(p[1]),) + tuple(int(x, 16) for x in p[2:7])
            elif p[0] == "row":
                rows[(int(p[1]), int(p[2]))] = row_pixels(p[3:])
            elif p[0] == "full":
                nfull, fbuf, fw, fh = (int(x) for x in p[1:5])
            elif p[0] == "frow":
                rows[("full", int(p[1]))] = row_pixels(p[2:])

    def bits(*ms):
        return sum(1 << m for m in ms)
    if seen != bits(0, 1, 3, 8, 12):
        errors.append("seen %08x" % seen)
    if fresh != bits(1, 3, 8):
        errors.append("fresh %08x" % fresh)
    if cur & bits(3, 8) != bits(8):
        errors.append("cur %08x (want m3 buffer 0, m8 buffer 1)" % cur)
    if quarter != bits(1, 8):
        errors.append("quarter %08x" % quarter)
    if pics != 4 or nseen != 5:
        errors.append("pictures %d / n_seen %d" % (pics, nseen))
    if (nreq, rmac, rsc, rdv, rfl, rtg) != (2, int.from_bytes(HOST, "big"), 3, 1, 3, 5):
        errors.append("request %r" % ((nreq, hex(rmac), rsc, rdv, rfl, rtg),))
    for y in range(4):
        if rows[(1, y)] != T1[y]:
            errors.append("machine 1 (relayed local slot) row %d differs" % y)
    # full view: pictures 1 and 3 complete; 1 -> buffer 1, 3 -> buffer 2
    # (neither shown = 0 nor the last complete = 1)
    if (nfull, fbuf, fw, fh) != (2, 2, 50, 5):
        errors.append("full view: %d pictures, buffer %d, %dx%d" % (nfull, fbuf, fw, fh))
    else:
        for y in range(5):
            if rows[("full", y)][:150] != F1[3][y]:
                errors.append("full picture row %d differs" % y)
    for y in range(6):
        if rows[(3, y)] != T3[9][y]:
            errors.append("machine 3 row %d differs" % y)
    for y in range(4):
        if rows[(8, y)] != T8[y]:
            errors.append("machine 8 row %d differs" % y)
    encs = [P.decode_thumb(P.vlan_untag(fr)[1][14:-4])["enc"] for fr in scenario()[6:9]]
    print("tb_thumb_rx: status cur %08x seen %08x fresh %08x quarter %08x, %d pictures; encodings %r;"
          " full view %d pictures, buffer %d" % (cur, seen, fresh, quarter, pics, encs, nfull, fbuf))
    for e in errors:
        print("ERROR:", e)
    print("tb_thumb_rx check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
