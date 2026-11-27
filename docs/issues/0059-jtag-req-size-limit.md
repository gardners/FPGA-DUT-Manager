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
