#!/usr/bin/env python3
"""XVC 1.0 splitting proxy (issue 0057 workaround).

Listens for an XVC client (openFPGALoader, Vivado hw_server) and forwards to
an upstream XVC server (`dutctl xvc`), splitting every shift into pieces of
at most --max-bits bits. Splitting a shift adds no TCK edges, so the JTAG
sequence is unchanged.

Why: `dutctl xvc` sends up to 8192 bits per UDP JTAG_REQ, but the supervisor
(build 618e7266) drops requests whose UDP payload exceeds 2000 bytes
(> 7904 bits), so bitstream loads stall with "jtag: no response".

  dutctl xvc 203.28.176.87 1 --port 2557 --half 6 &
  ./xvc-split.py --listen 2558 --upstream 2557 &
  openFPGALoader -c xvc-client --ip 127.0.0.1 --port 2558 build/k325t_bringup.bit
"""
import argparse
import socket
import struct


def recv_exact(s, n):
    b = bytearray()
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise ConnectionError("peer closed")
        b += c
    return bytes(b)


def recv_cmd(s):
    """Read up to and including the ':' of the next XVC command."""
    b = bytearray()
    while not b.endswith(b":"):
        c = s.recv(1)
        if not c:
            raise ConnectionError("peer closed")
        b += c
        if len(b) > 16:
            raise ValueError("bad command %r" % bytes(b))
    return bytes(b)


def shift_bits(vec, start, n):
    """Bits [start, start+n) of an LSB-first vector, as a new LSB-first vector."""
    v = int.from_bytes(vec, "little") >> start
    v &= (1 << n) - 1
    return v.to_bytes((n + 7) // 8, "little")


def serve(cli, up, max_bits):
    while True:
        cmd = recv_cmd(cli)
        if cmd == b"getinfo:":
            up.sendall(cmd)
            line = bytearray()
            while not line.endswith(b"\n"):
                line += recv_exact(up, 1)
            cli.sendall(bytes(line))
        elif cmd == b"settck:":
            arg = recv_exact(cli, 4)
            up.sendall(cmd + arg)
            cli.sendall(recv_exact(up, 4))
        elif cmd == b"shift:":
            n = struct.unpack("<I", recv_exact(cli, 4))[0]
            nb = (n + 7) // 8
            tms = recv_exact(cli, nb)
            tdi = recv_exact(cli, nb)
            tdo = 0
            done = 0
            while done < n:
                k = min(max_bits, n - done)
                kb = (k + 7) // 8
                up.sendall(b"shift:" + struct.pack("<I", k) +
                           shift_bits(tms, done, k) + shift_bits(tdi, done, k))
                part = int.from_bytes(recv_exact(up, kb), "little") & ((1 << k) - 1)
                tdo |= part << done
                done += k
            cli.sendall(tdo.to_bytes(nb, "little"))
        else:
            raise ValueError("unknown command %r" % cmd)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--listen", type=int, default=2558)
    ap.add_argument("--upstream", type=int, default=2557)
    ap.add_argument("--upstream-host", default="127.0.0.1")
    ap.add_argument("--max-bits", type=int, default=7904)
    a = ap.parse_args()
    ls = socket.socket()
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", a.listen))
    ls.listen(1)
    print("xvc-split: 127.0.0.1:%d -> %s:%d, <= %d bits per shift"
          % (a.listen, a.upstream_host, a.upstream, a.max_bits), flush=True)
    while True:
        cli, _ = ls.accept()
        cli.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            up = socket.create_connection((a.upstream_host, a.upstream))
            up.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            serve(cli, up, a.max_bits)
        except (ConnectionError, ValueError) as e:
            print("xvc-split: session ended:", e, flush=True)
        finally:
            cli.close()
            try:
                up.close()
            except NameError:
                pass


if __name__ == "__main__":
    main()
