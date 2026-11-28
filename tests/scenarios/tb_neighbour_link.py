"""Neighbour link (issue 0069, ADR 0007): injected frames for
tb_neighbour_link and the check of the HELLOs it captured from instance A.

  python3 -I tests/scenarios/tb_neighbour_link.py gen   <in.txt>
  python3 -I tests/scenarios/tb_neighbour_link.py check <captured.txt>

Input lines "<gap_us> <n> <hex bytes>" are sent back to back on A's RX
(after gap_us of idle line) while B is disconnected; n = 0 means a break
(line low for 15 bit times, one UART framing error). The VHDL testbench
checks A's counters after each line (expected values in the comments here
and in hdl/tb/tb_neighbour_link.vhd).

Captured lines "<label> <hex bytes>": the first HELLOs A sent (label A),
decoded here with the reference decoder.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import netproto as P  # noqa: E402

# same values as the testbench
DNA_A = 0x0000_0123_4567_89AB
DNA_C = 0x0100_0000_0000_0042     # an injected third board
BUILD_A = 0xC0DE0A0A
BOOT_A = 0x0B00_7A00
DIP_A = 0x23                      # B = 2


def injected():
    hello_c = P.nb_hello(0x71, P.NB_STANDALONE, 0, DNA_C, 0xC0DE0C0C, 0x12345678, 7)
    bad_crc = hello_c[:-1] + bytes([hello_c[-1] ^ 0x40])
    return [
        (50, bad_crc),                                           # crc_errs 1
        (50, bytes.fromhex("a55a01001c 4e4201")),                # truncated: fmt_errs 1 (byte timeout)
        (100, bytes.fromhex("1337a599ff") + hello_c),            # garbage then a good HELLO: rx +1, peer C
        (50, P.nb_frame(0x10, b"\x01\x02\x03")),                 # unknown type, good CRC: rx +1, ignored
        (50, P.nb_frame(P.NB_T_HELLO, bytes(10))),               # HELLO too short: fmt_errs 2
        (50, b""),                                               # break: uart_errs 1
        (50, P.nb_frame(P.NB_T_HELLO, bytes(28))),               # good CRC, magic wrong: rx +1, fmt_errs 3
    ]


def gen(path):
    with open(path, "w") as fh:
        for gap, data in injected():
            fh.write("%d %d %s\n" % (gap, len(data), " ".join("%02x" % b for b in data)))


def check(path):
    errors = []
    hellos = []
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if parts and parts[0] == "A":
                hellos.append(bytes(int(x, 16) for x in parts[1:]))
    if len(hellos) < 3:
        errors.append("captured %d HELLOs from A (want >= 3)" % len(hellos))
    seqs = []
    for i, f in enumerate(hellos):
        try:
            d = P.nb_decode(f)
        except ValueError as e:
            errors.append("frame %d: %s (%s)" % (i, e, f.hex(" ")))
            continue
        if not d["crc_ok"] or d["type"] != P.NB_T_HELLO or d["len"] != 28 or d["payload"][26:] != b"\0\0":
            errors.append("frame %d: crc/type/len %r" % (i, d))
        if (d["magic"], d["version"], d["dip"], d["dna"], d["build_id"], d["boot_id"]) != \
                (P.NB_HELLO_MAGIC, 1, DIP_A, DNA_A, BUILD_A, BOOT_A):
            errors.append("frame %d: identity fields %r" % (i, d))
        seqs.append(d["seq"])
        if i == 0 and (d["role"], d["flags"]) != (P.NB_STANDALONE, 0):
            errors.append("first HELLO: role %d flags %d (want standalone, 0)" % (d["role"], d["flags"]))
        if i >= 1 and (d["role"], d["flags"]) != (P.NB_PRIMARY, P.NBH_PRESENT):
            errors.append("HELLO %d: role %d flags %d (want primary, present)" % (i, d["role"], d["flags"]))
    if seqs != list(range(len(seqs))):
        errors.append("HELLO seq %r (want 0, 1, ...)" % seqs)
    print("captured %d HELLOs from A, seq %r" % (len(hellos), seqs))
    for e in errors:
        print("ERROR:", e)
    print("neighbour_link check", "FAILED" if errors else "PASSED")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2]))
