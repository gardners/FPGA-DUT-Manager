# 0020: Hardware smoke test script

Status: Done (2026-11-25)
Opened: 2026-11-25

scripts/hwtest.sh using dutctl against a running board (heartbeats, ping/ARP, text screen, management read-back, UART loopback with a jumper, JTAG refusal when unpowered). The dev laptop is on NATed Wi-Fi (192.168.188.x) and cannot see the board's 203.28.176.x broadcasts; needs a host on that segment or unicast telemetry (dest-ip) to a routable host.

## 2026-11-25: scripts/hwtest.sh (branch feature/smoke-test)

`scripts/hwtest.sh [--quick]` runs against the board already on this host's
segment (the build host on 203.28.176.x sees the broadcasts; the NATed
laptop still cannot). No bitstream load, no root. One PASS/FAIL/SKIP/WARN/
INFO line per check, summary line, exit 1 on any FAIL, 2 if no board answers.
Checks: discovery, heartbeat fields (build id + matching commit, DNA, dut_id
0x0n/0x1m, link and video blocks, endpoints agree), HDMI loopback lock
720x480 of 858x525 ~27 MHz, ping 20/20 and ARP MAC 02:4d:36:35:00:<dut_id>,
heartbeat period as found / at 50 ms / restored (period from hb_seq deltas,
loss from received vs sent), every settable key (valid, bad value, bad
length, config_generation +1 on ok and unchanged on reject), bad keys,
duplicate cmd_id, wrong dut index (no ack, rx_rejects grows), console screen
1/2/3/0 vs the shown field, keyboard type + kbd-leds 0/1/2, JTAG refusal
when unpowered (IDCODE when powered), UART bytes when powered, raster when
capability b4 is set. Settings are restored from an EXIT trap; keys the
heartbeat does not report are written with their power-up defaults.
New dutctl conveniences: `listen --kv [-n N]` and raw `mgmt IP KEY [HEX]
[--cmd-id N] [--dut N]`; nothing on the wire changed.

First run against build d3db353e: 52 pass, 8 fail, 1 warn, 3 skip (~27 s).
Findings:
* **Wrong-length values get status 3 (bad value), not 2 (bad length)** for
  keys 0x0020 kbd-policy, 0x0021 kbd-override, 0x0050 hb-period-ms and
  0x0060 out-policy: `net_rx` S_MGMT folds the length test into the value
  test (`if vlen = 1 and ... else st := ST_BAD_VALUE`), unlike 0x0013,
  0x0033 and 0x0035, which separate the two. ADR 0005 section 4 defines
  status 2 for a bad length. These are the 8 FAILs (both endpoints). The
  values are not applied, so it is a reporting bug only. Fix in HDL (lead).
* capabilities = 0x7: b3 (physical keyboard host) is clear although
  kbd_phys_type = 1 (MK-I attached); `supervisor_core` hard-codes
  `bstat.caps <= x"00000007"`. Reported as WARN.
* Everything else as specified: heartbeats 20.00 ms with no loss, 50 ms
  when set, video locked 720x480 of 858x525 27.000 MHz, console screen
  mapping 1->0 2->1 3->2 0(auto, video present)->0, JTAG refused with
  "target not powered" (target_flags 8, jtag_status 8). UART/raster
  skipped (DUT unpowered; capture not advertised yet).

## 2026-11-25 closed

scripts/hwtest.sh (sub-agent): 61 PASS / 0 FAIL on d29ea748 incl. raster capture.
