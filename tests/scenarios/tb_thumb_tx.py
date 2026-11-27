"""Check tb_thumb_tx's frames against the reference packing (issue 0038).

  python3 -I tests/scenarios/tb_thumb_tx.py gen   <in.txt>   (no input needed)
  python3 -I tests/scenarios/tb_thumb_tx.py check <out.txt>
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import netproto as P  # noqa: E402


def pat(m, x, y):
    """Same picture as pat() in hdl/tb/tb_thumb_tx.vhd."""
    if y % 3 == 0 and y < 6:
        r = ((x // 40) * 37 + y + m) % 256
        return (r, r, r)
    if y % 3 == 2 and y < 6 and x < 160:
        return (10, 20, 30)
    return ((x * 13 + y * 7 + m) % 256, (x * x + y) % 256, (x + 3 * y * y) % 256)


def tile(m, w, h, zero=False):
    return [bytes(0 for _ in range(3 * w)) if zero else
            b"".join(bytes(pat(m, x, y)) for x in range(w)) for y in range(h)]


DST_A = P.mac("02:00:00:00:00:aa")
DST_R = P.mac("02:4D:36:35:00:22")
DST_T = P.mac("02:4D:36:35:00:33")     # targeted requester (issue 0060)
# (machine, endpoint, dst, frame, scale, tile)
PICTURES = [(4, 0, DST_A, 1, P.TH_SCALE_HALF, tile(4, 320, 16)),
            (5, 1, DST_A, 2, P.TH_SCALE_QUARTER, tile(5, 160, 6)),
            (4, 0, DST_R, 3, P.TH_SCALE_QUARTER, tile(4, 160, 3, zero=True)),
            (5, 1, DST_T, 4, P.TH_SCALE_HALF, tile(5, 320, 6, zero=True))]


def check(path):
    errors = []
    got, nos, treqs = [], [], []
    with open(path) as fh:
        for line in fh:
            p = line.split()
            if p[0] == "treq":
                treqs.append(tuple(int(x) for x in p[1:5]))
                continue
            sub, d, dst = int(p[1]), int(p[2]), bytes.fromhex(p[3])
            (machine, flags, scale, enc, frame, row, nlines, height, width,
             nbytes) = (int(x) for x in p[4:14])
            tag = p[14] == "1"
            payload = bytes.fromhex(p[15]) if len(p) > 15 else b""
            # issue 0060: frames to a requester are tagged, to the forced MAC not
            if tag != (dst != DST_A):
                errors.append("frame to %s tagged %r" % (dst.hex(), tag))
            body = struct.pack(P.TH_HDR, P.TH_VERSION, sub, P.MAGIC, machine, flags, scale, enc,
                               frame, row, nlines, width, height, nbytes) + payload
            if sub == P.TH_SUB_NOSRC:
                nos.append((machine, d, dst))
            else:
                got.append((machine, d, dst, body))
    for machine, d, dst, frame, scale, t in PICTURES:
        want = [x[14:] for x in P.thumb_packets(dst, b"\0" * 6, machine, frame, t, scale)]
        mine = [b for (m, dd, ds, b) in got if m == machine and ds == dst and
                P.decode_thumb(b)["frame"] == frame]
        if [b for (m, dd, ds, b) in got if m == machine and ds == dst and dd != d]:
            errors.append("machine %d sent from the wrong endpoint" % machine)
        if mine != want:
            errors.append("picture m%d f%d: %d frames, want %d; first difference at frame %r" % (
                machine, frame, len(mine), len(want),
                next((i for i, (a, b) in enumerate(zip(mine, want)) if a != b), None)))
        else:
            dec = [P.decode_thumb(b) for b in mine]
            print("picture m%d f%d: %d frames %r, encodings %r" % (
                machine, frame, len(mine), [x["nlines"] for x in dec], [x["enc"] for x in dec]))
    if len(got) != sum(len(P.thumb_packets(b"", b"", m, f, t, s)) for m, _, _, f, s, t in PICTURES):
        errors.append("%d lines frames in total" % len(got))
    if (4, 0, DST_A) not in nos or (5, 1, DST_A) not in nos:
        errors.append("no-source frames %r" % nos[:4])
    if any(x[2] not in (DST_A, DST_R, DST_T) for x in nos):
        errors.append("no-source frame to another destination")
    if any(x[0] != 5 for x in nos if x[2] == DST_T):
        errors.append("targeted requester got no-source frames for other machines %r" % nos)
    sel = [x for x in treqs if x[0] != P.TH_SCALE_FULL]
    full = [x for x in treqs if x[0] == P.TH_SCALE_FULL]
    if len(sel) < 3 or any(x != (P.TH_SCALE_QUARTER, 2, 0, 0) for x in sel):
        errors.append("select-screen requests %r" % sel)
    if len(full) < 2 or any(x != (P.TH_SCALE_FULL, 1, P.TH_RF_TARGETED | P.TH_RF_PRIORITY, 9) for x in full):
        errors.append("full-view requests %r" % full)
    print("%d lines frames, %d no-source, %d requests" % (len(got), len(nos), len(treqs)))
    for e in errors:
        print("ERROR:", e)
    print("tb_thumb_tx check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        open(sys.argv[2], "w").close()
    else:
        sys.exit(check(sys.argv[2]))
