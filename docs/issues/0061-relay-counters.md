# 0061: thumbnail relay / full-view counters in the heartbeat

Status: implemented and simulated (branch feature/relay-counters); not yet
loaded on hardware. Related: 0060 (relayed full-screen view of the K325T),
0038 (relay), ADR 0005 sections 3d and 10.

## Request (lead, 2026-11-27)

Debugging the relayed full-screen view (HewnWeb K325T streaming 1/1
pictures over VLAN 1650): the heartbeat has no relay counters, so we cannot
tell whether requests go out or pictures arrive. Add board-wide wrapping
counters: requests sent (and targeted 1/1 ones); relay frames received
(lines, no source, wrong VLAN, machine not taken, longer than a MAC slot);
full pictures completed and shown, the full view's "no picture in the last
second" state; the last frame's machine and scale. Show them in `dutctl
listen` (and `--kv`), report them in hwtest as INFO. Investigate whether
1/1 frames longer than the MAC's 2 KiB slot can be received at all.

## Finding: frame size vs the receive path (2026-11-27)

**`thumb_rx_tap` is a streaming tap, not a slot reader.** It sits on the
GMII `rx_dv`/`rxd` bytes in the clk_rx domain beside `eth_mac_rx` (both
fed from the same `supervisor_core` ports), has its own preamble/SFD
state machine and CRC, and its parse index runs to 16383 bytes. So 1/1
RAW888 frames (one 720-pixel line = 2160 payload bytes, up to 3 lines /
~8040 bytes per frame) are received whatever the MAC slot size. The MAC
itself still truncates them to its 2047-byte slot (stat_drop: heartbeat
rx_bad_frames rises with each one, as noted in 0060) and publishes the
head to net_rx, which ignores EtherType 0x88B5; `rx_frame_observer` gives
the RX phase hunter no event for a dropped frame, so long relay frames do
not trigger hunts. The 2 KiB slot is **not** the bug.

Simulated end to end: `tb_supervisor_core` now sends a 2214-byte tagged
1/1 RAW888 frame; the tap counts it good (rl_rx_lines) and long
(rl_rx_long), the MAC counts one drop.

What can still stop 1/1 pictures (now visible in the counters):

* **Jumbo frames on the path.** Every 1/1 RAW888 frame is > 1522 bytes;
  any switch or port that does not pass jumbo (~8100 byte) frames drops
  all of them (rl_rx_long and rl_rx_lines stay 0 while the K325T counts
  frames sent; 1/2 thumbnails, also packed up to 8000 bytes, would fail
  the same way, except RLE24 frames that happen to be small). The
  thumbnail relay has never been tried between two boards over a switch
  (0038 was tested on one board). The K325T's MAC must also send frames
  of that size.
* VLAN mismatch: rl_rx_vlan rises (frames reach us with another VID or
  untagged).
* Machine number mismatch (`board_n` /= the full view's machine, DUT1 =
  machine 1 on the bench): rl_rx_lines and rl_rx_foreign rise, and
  rl_last_machine shows what the K325T sends.
* Writer too slow / DDR3 stalls: rl_rx_bad and rl_rx_ovf rise.
* Lost frames: rl_rx_lines rises but rl_full_pics does not (a picture with
  any frame missing is never complete).
* Display: rl_full_pics rises but rl_full_swaps does not (e.g. DDR3 not
  calibrated: full_display is disabled).

## Implementation

Heartbeat relay block, bytes 160..187 (payload 152 -> 180), ADR 0005
section 3d:

| Off | Field |
|---|---|
| 160 | rl_req_sent (all requests handed to net_tx) |
| 162 | rl_req_full (targeted scale 3) |
| 164 | rl_rx_req (requests heard) |
| 166 | rl_rx_lines (good lines frames for us) |
| 168 | rl_rx_bad (lines frames for us, not good) |
| 170 | rl_rx_ovf (of those, tap FIFO full) |
| 172 | rl_rx_nosrc |
| 174 | rl_rx_vlan (relay frames for us dropped for the VLAN) |
| 176 | rl_rx_long (relay frames for us > 2047 bytes incl. tag and FCS) |
| 178 | rl_rx_foreign (good lines frames, no line taken) |
| 180 | rl_full_pics |
| 182 | rl_full_swaps (full_display buffer changes) |
| 184 | relay_flags: b0 want, b1 live, b2 no picture in 1 s, b3 last valid, b4 last was no-source, b5 own source streaming |
| 185 | rl_last_machine (0xFF none) |
| 186 | rl_last_scale |
| 187 | rl_full_age (8 ms units, 255 = >= 2.04 s / never) |

* `thumb_rx_tap`: per-event toggles (clk_rx) -> 3-FF sync -> u16 counters
  in clk_sys; last machine/scale held and sampled on its own toggle.
* `thumb_rx_writer`: `foreign` = END good with no LINE taken.
* `supervisor_core`: requests on `treq_taken`, swaps on `full_shown`
  changes, flags from full_want / full_fresh / thumb_tx streaming.
* `dutctl listen`: `relay req N (full N) heard N  rx lines N bad N (ovf N)
  nosrc N vlan-drop N long N foreign N  last mM 1/1  full pics N shown N
  LIVE|NO-PICTURE age N ms`; `--kv`: `has_relay` and `rl_*` names as in
  the table (rl_flags, rl_last_machine, rl_last_scale, rl_full_age).
* `scripts/hwtest.sh`: one INFO line "relay counters".

### 2026-11-27 progress (sub-agent)

Tests: netproto selftest (block layout + round trip), C vector
`heartbeat_relay`, tb_thumb_rx (counters add up to the tap's good frames,
bad/VLAN/foreign seen), tb_supervisor_core (untagged relay frame -> VLAN
drop, 2214-byte 1/1 frame for machine 9 -> long + foreign, every counter
of the last heartbeat checked: req_sent 1, req_full 1, rx_req 1, rx_lines
7, rx_vlan 1, rx_long 1, rx_foreign 1, full_pics 2, last machine 9 scale
3). Its RX totals become 62 good / 2 bad (the long frame is a MAC drop).

Observation while extending tb_supervisor_core: inserting two frames
(+120 us) early in the scenario made 6-12 later frames drop in the MAC
(both RX slots full). The frames were then moved to the end. Likely the
testbench's thumbnail streaming to the forced host MAC keeps net_tx busy so
net_rx waits on pending replies; not investigated further.
