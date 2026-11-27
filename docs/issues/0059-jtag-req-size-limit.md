# 0059: JTAG_REQ above 7904 bits is never answered; MTU limits

Status: open (found 2026-11-27 during 0057). Related: ADR 0005, 0057.

## Problem

* Build 618e7266 (and later) never answers a JTAG_REQ with more than 7904
  bits (UDP payload > 2000 bytes), although ADR 0005 and proto_pkg allow
  8192 (JTAG_MAX_BITS). Bisected by the 0057 agent with raw XVC shifts:
  7904 answers, 7912 does not.
* `dutctl xvc` sends up to DP_JTAG_MAX_BITS = 8192 per request, so
  openFPGALoader over `dutctl xvc` stalled with "jtag: no response". The
  0057 workaround is `targets/qmtech-k325t/xvc-split.py`, a proxy that
  splits shifts to <= 7904 bits.
* Independently, requests above ~5792 bits (payload > 1472 bytes) need IP
  fragmentation on a standard 1500-byte MTU, which the FPGA does not
  reassemble; it only worked here because of the host's MTU.

## Plan

* Find the real receive limit in the HDL (frame buffer size) and make ADR
  0005 / proto_pkg / dutproto.h / netproto.py state the true maximum, or
  raise the buffer if cheap.
* dutctl: split every JTAG shift (xvc, jtag-speed, jtag-idcode) into
  requests that fit one unfragmented frame for the path MTU (default 1500:
  <= 5792 bits; an option for jumbo frames), without extra TCK edges, so
  the proxy is no longer needed.

## Progress 2026-11-27 (agent, branch feature/jtag-req-size)

* **Root cause.** `eth_mac_rx` stores frames in two 2 KiB slots and
  discarded any frame reaching 2047 stored bytes (incl. FCS) with only a
  `stat_drop` pulse, so net_rx never saw it. Largest frame: 2047 bytes incl.
  FCS = 2043 without = 14 + 20 + 8 + UDP payload 2001. A JTAG_REQ payload is
  8 + 16 + 2 * ceil(bits/8): 7904 bits = 2000 bytes fits, 7912 = 2002 does
  not, exactly the bisected limit. The jtag_engine vector RAM (2 KiB, TMS at
  0..1023, TDI at 1024..2047) does hold 8192 bits; the limit is the RX slot.
* **Not raised to 8192:** that needs 4 KiB slots (8 KiB RX RAM, 13-bit
  slot addresses/lengths through net_rx and the taps) for a size that needs
  MTU >= 2092 anyway; the protocol maximum is now the true one instead.
* **HDL:** `JTAG_MAX_BITS = 7904`. The MAC keeps the head (2047 bytes) of an
  oversize frame, still counts it as a drop (no phase-hunter event), and
  publishes it if the FCS over the whole frame is good; net_rx then sees
  IPv4 total length > slot length and answers a JTAG_REQ to us with status
  3 (bad format, nothing clocked, seq not consumed, rx_rejects + 1); every
  other truncated frame is still dropped. tb_supervisor_core: 7904-bit
  request clocked (TDO 988 bytes), 7912-bit request answered status 3.
* **dutctl:** every JTAG shift (xvc, jtag-idcode, jtag-speed) goes through
  `xvc_split_shift` with `dp_jtag_max_bits_for_mtu(MTU)` bits per request:
  MTU 1500 (default) -> 5792 bits (datagram exactly 1500 bytes), >= 2028 ->
  7904. Global `--mtu N` / `$DUTCTL_MTU` (576..65535). jtag-speed's 3608-bit
  probe stays one request. Unit tests: MTU table, datagram sizes at the
  limits, split at m-1/m/m+1/2m/2m+1 etc. for several maxima (exact
  TMS/TDI concatenation, TDO reassembly, padding zero, failure stops).
* `targets/qmtech-k325t/k325t.sh` talks to `dutctl xvc` directly;
  `SPLIT=1` keeps `xvc-split.py` as a fallback.
* ADR 0005 §7 (size limits paragraph), ADR 0010, README updated.
