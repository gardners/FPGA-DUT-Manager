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
    f += fcs([P.thumb_request(HOST, P.TH_SCALE_QUARTER, 3)])
    # machine 3, 1/2 scale: frame 7 good (-> buffer 1), frame 8 with a bad
    # FCS on its second frame (never shown), frame 9 good (-> buffer 0)
    f += fcs(P.thumb_packets(MAC0, PEER, 3, 7, T3[7], P.TH_SCALE_HALF, budget=2000))
    f += fcs(P.thumb_packets(MAC0, PEER, 3, 8, T3[8], P.TH_SCALE_HALF, budget=2000), bad=(1,))
    f += fcs(P.thumb_packets(MAC0, PEER, 3, 9, T3[9], P.TH_SCALE_HALF))
    # machine 8, 1/4 scale, raw only, to the other endpoint MAC
    f += fcs([P.thumb_frame(MAC1, PEER, 8, 1, 0, T8[:3], P.TH_SCALE_QUARTER, 4, enc=P.TH_ENC_RAW),
              P.thumb_frame(MAC1, PEER, 8, 1, 3, T8[3:], P.TH_SCALE_QUARTER, 4, enc=P.TH_ENC_RLE24)])
    # this board's own machine 1: ignored (stored locally, never via the network)
    f += fcs(P.thumb_packets(MAC0, PEER, 1, 1, T1, P.TH_SCALE_QUARTER))
    # another board's MAC: not for us
    f += fcs(P.thumb_packets(OTHER, PEER, 20, 1, T8, P.TH_SCALE_QUARTER))
    # present, no source
    f += fcs([P.thumb_nosrc(MAC1, PEER, 12)])
    # a request to another unicast MAC is not ours either
    f += fcs([P.eth(OTHER, PEER, P.ETH_THUMB, P.thumb_request(PEER, 1, 1)[14:])])
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
                nreq, rmac, rsc, rdv = int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4], 16)
            elif p[0] == "row":
                rows[(int(p[1]), int(p[2]))] = row_pixels(p[3:])

    def bits(*ms):
        return sum(1 << m for m in ms)
    if seen != bits(0, 1, 3, 8, 12):
        errors.append("seen %08x" % seen)
    if fresh != bits(3, 8):
        errors.append("fresh %08x" % fresh)
    if cur & bits(3, 8) != bits(8):
        errors.append("cur %08x (want m3 buffer 0, m8 buffer 1)" % cur)
    if quarter != bits(8):
        errors.append("quarter %08x" % quarter)
    if pics != 3 or nseen != 5:
        errors.append("pictures %d / n_seen %d" % (pics, nseen))
    if (nreq, rmac, rsc, rdv) != (1, int.from_bytes(HOST, "big"), 2, 3):
        errors.append("request %r" % ((nreq, hex(rmac), rsc, rdv),))
    for y in range(6):
        if rows[(3, y)] != T3[9][y]:
            errors.append("machine 3 row %d differs" % y)
    for y in range(4):
        if rows[(8, y)] != T8[y]:
            errors.append("machine 8 row %d differs" % y)
    encs = [P.decode_thumb(fr[14:-4])["enc"] for fr in scenario()[1:4]]
    print("tb_thumb_rx: status cur %08x seen %08x fresh %08x quarter %08x, %d pictures; encodings %r"
          % (cur, seen, fresh, quarter, pics, encs))
    for e in errors:
        print("ERROR:", e)
    print("tb_thumb_rx check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
