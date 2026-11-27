# ADR 0005: UDP wire protocol v1 (interface control document)

Status: Proposed (2026-11-25). The owner reviews; implementation proceeds on
this basis. Every change bumps `PROTO_VERSION` or uses a reserved field.

Canonical sources: this document, `hdl/src/proto/proto_pkg.vhd` (FPGA
constants) and `sw/dutctl/include/dutproto.h` (host). Golden packets in
`tests/vectors/` are checked by both the nvc testbenches and the C unit tests,
so the two implementations cannot silently diverge.

## 1. Addressing

> Default MAC/IP assignment is superseded by ADR 0011 (DIP-switch DUT IDs,
> deterministic MACs, DHCP with fallback). Port 6508 TEXT_WRITE: ADR 0012.

* Each Mimas presents **two logical endpoints** (DUT0, DUT1), each with its own
  MAC and IPv4 address, on one PHY. ARP replies for both. ICMP echo for both
  (bounded to 64 payload bytes; larger echo requests are dropped).
* Default MAC: `02:4D:36:35:xx:yy` where `xx` = low 8 bits of a hash of the
  FPGA DNA (or DIP[3:0] when DNA is unavailable) and `yy` = DUT index. The
  `02` prefix is locally administered unicast.
* Default IP: `192.168.65.(16 + 2*node + dut)` where `node` = DIP[3:0]
  (default 0 → 192.168.65.16 and .17). Host can set both via management;
  settings are volatile and restored by the host after reboot.
* Same port numbers on every endpoint; the destination IP picks the DUT.

| Port | Service | Direction |
|---|---|---|
| 6500 | management | host → FPGA (ack back to sender) |
| 6501 | heartbeat | FPGA → telemetry destination |
| 6502 | keyboard | host → FPGA |
| 6503 | UART | both (TX requests in; snapshots out) |
| 6504 | raster (phase 2) | FPGA → telemetry destination |
| 6505 | audio (phase 4) | FPGA → telemetry destination |
| 6507 | JTAG | host → FPGA; response to request's source |

* Telemetry destination (heartbeat/UART/raster/audio) per DUT: IP+MAC+port
  base, default broadcast `255.255.255.255` / `ff:ff:ff:ff:ff:ff`, settable via
  management. Responses (MGMT ack, JTAG) go to the source MAC/IP/port of the
  request that caused them.
* FPGA TX UDP checksum = 0 (permitted for IPv4). FPGA RX ignores UDP checksum
  (Ethernet FCS protects the hop; this is an isolated lab VLAN). IPv4 header
  checksum is generated and verified. No fragmentation: fragments are dropped.
* MTU: control-plane packets fit 1500. Raster packets need jumbo (≈2.2 kB).
* Broadcast-addressed management is ignored except `SET_IDENTITY` carrying the
  exact board DNA (recovery when the IP is unknown).

## 2. Common header (8 bytes, all custom packets)

All multi-byte fields big-endian (network order). No padding; offsets below are
exact.

| Off | Size | Field | Notes |
|---|---|---|---|
| 0 | 2 | magic | `0x4D36` ("M6") |
| 2 | 1 | version | `1` |
| 3 | 1 | type | see per-port tables |
| 4 | 2 | length | bytes following this header |
| 6 | 1 | dut | 0/1 = endpoint index (must match the endpoint addressed, else dropped); 0xFF = wildcard "whichever endpoint this IP is". FPGA → host packets always carry the real index |
| 7 | 1 | flags | type specific, 0 unless stated |

Datagrams with bad magic/version, `length` ≠ UDP payload − 8, out-of-range
fields or wrong `dut` are dropped and counted in `rx_rejects`.

## 3. Heartbeat (port 6501, type 0x01, FPGA → host)

Sent per DUT at ~50 Hz (configurable period; 20 ms default), and expedited
(≥1 ms spacing) on a physical-keyboard change on the master.

| Off | Size | Field |
|---|---|---|
| 8 | 4 | hb_seq (per DUT, wraps) |
| 12 | 4 | boot_id (random per configuration) |
| 16 | 4 | build_id (git short hash of the bitstream) |
| 20 | 8 | board_dna (57-bit DNA, 0 if unavailable) |
| 28 | 1 | topo_index (0 = master, 0xFF unknown) |
| 29 | 1 | topo_count |
| 30 | 1 | dip_switches |
| 31 | 1 | link_flags: b0 eth link up, b1 1000 Mb/s, b2 full duplex, b3 chain up-link ok, b4 chain down-link ok, b5 is master, b6 reserved (was DUT ID conflict; IDs cannot collide since ADR 0011 amendment) |
| 32 | 4 | capabilities: b0 uart, b1 jtag, b2 kbd device, b3 phys kbd host, b4 hdmi capture, b5 chain, b6 audio, b7 thumbnails (section 10), b8 JTAG to the physical keyboard's CPLD (section 7, ADR 0014) |
| 36 | 4 | config_generation |
| 40 | 1 | target_flags: b0 kbd 3V3 sense, b1 JTAG VREF sense, b2 outputs enabled (UART TXD, KIO10), b3 sense valid, b4 power-off hold: the shield power control switched this DUT's CTRL bit off and all its outputs, JTAG included, are forced off (key 0x0062, issue 0056) |
| 41 | 1 | kbd_owner: 0 UDP, 1 physical |
| 42 | 1 | kbd_policy: 0 REQUIRE_FRESH_PRESS, 1 ACCEPT_HELD |
| 43 | 1 | selected: hi nibble video target 0..7/F none, lo nibble kbd target |
| 44 | 10 | kbd_effective (80-bit, bit k = matrix key k, 1 = pressed) |
| 54 | 10 | kbd_udp |
| 64 | 10 | kbd_physical (master: raw physical bitmap; else zero) |
| 74 | 2 | kbd_phys_change_count |
| 76 | 1 | kbd_phys_type: 0 none, 1 MK-I, 2 MK-II, 3 type 3 (async UART, ADR 0014) |
| 77 | 1 | jtag_status: b0 busy, b1 result ready, b2 aborted, b3 JTAG outputs off (target unpowered, out-policy 2 or power-off hold) |
| 78 | 4 | jtag_next_seq |
| 82 | 4 | uart_rx_seq |
| 86 | 4 | uart_tx_accepted |
| 90 | 2 | rx_rejects |
| 92 | 2 | tx_drops (scheduler/ring) |
| 94 | 12 | dut_leds (MK-I LED vector bits 95..0 received from the DUT) |
| 106 | 1 | addr_src: 0 none yet, 1 DHCP, 2 fallback, 3 static (ADR 0011) |
| 107 | 1 | dut_id (0x0n P12 / 0x1m P13 from DIP switches, ADR 0011) |

Total 108 bytes (header + 100). Since 2026-11-25 the supervisor always
appends the video block (section 8; zeros until HDMI capture exists) and
the link block (section 3a): 140 bytes on the wire (header + 132); with
the memory block (section 3b, issue 0034) 152 bytes (header + 144); with
the shield block (section 3c, issue 0049) 160 bytes (header + 152).
Decoders must accept >= 100 and use the blocks only when present.

### 3a. Heartbeat link block (bytes 132..139; payload >= 132)

RGMII RX self-calibration status (issue 0028).

| Off | Size | Field |
|---|---|---|
| 132 | 1 | rx_phase_pos: RX sample phase, positions of 5.625 deg from the power-up phase |
| 133 | 1 | rx_eye_width: passing positions found by the last hunt (0 = never hunted) |
| 134 | 2 | rx_hunts: hunts since configuration |
| 136 | 2 | rx_bad_frames: frames seen (RX_CTL >= 64 cycles) without a good FCS |
| 138 | 1 | rx_link_flags: b0 hunting, b1 RX MMCM locked |
| 139 | 1 | reserved |

### 3b. Heartbeat memory block (bytes 140..151; payload >= 144)

DDR3 frame store status (issue 0034, ADR 0013). Appended 2026-11-25; the
heartbeat is then 152 bytes on the wire (header + 144). Decoders use the
block only when the payload is >= 144.

| Off | Size | Field |
|---|---|---|
| 140 | 1 | mem_flags: b0 DDR3 calibrated, b1 self-test running, b2 self-test done, b3 self-test passed (valid with b2) |
| 141 | 1 | reserved |
| 142 | 2 | mem_errors: self-test words read back wrong (saturates at 0xFFFF) |
| 144 | 2 | mem_dq_fail: bit i = DDR3 data line DQ i returned a wrong bit at least once |
| 146 | 2 | mem_test_kib: self-test region size in KiB (0 = no memory subsystem) |
| 148 | 4 | mem_first_err: 16-byte word address of the first failing word (0xFFFFFFFF none) |

### 3c. Heartbeat shield block (bytes 152..159; payload >= 152)

Shield I2C status (issue 0049, `shield_io`; bit maps in
`docs/hardware/shield-pinplan.md`). Appended 2026-11-27; all zero in a
bitstream without the shield I2C master (normal build, `SHIELD_RX` = 0).
Board-wide: the same in both endpoints' heartbeats.

| Off | Size | Field |
|---|---|---|
| 152 | 1 | shd_flags: b0 bitstream has the shield I2C master, b1 first probe finished, b2 shield present (expander A answered; bytes 153/154 valid), b3 sense valid (the last poll of expander B succeeded; bytes 155/156 inputs valid), b4 power board PRESENT (expander B P0.7, valid with b3), b5 CTRL state kept from before an FPGA reconfiguration (the host has not set key 0x0062 since), b6-b7 0 |
| 153 | 1 | shd_revision: expander A port 0 straps (shield v1 = 0x01) |
| 154 | 1 | shd_features: expander A port 1 straps: b0 HDMI1 capture, b1 power header, b2 HDMI2, b3 HDMI3, b4 DUT2 ports, b5 DUT3 ports, b6 neighbour UART, b7 reserved |
| 155 | 1 | shd_sense: b0-b3 VIO sense DUT0..DUT3, b4-b7 keyboard 3.3 V sense DUT0..DUT3 |
| 156 | 1 | shd_hdmi: b0-b2 +5V sense HDMI1..HDMI3, b3 PK_JTAGEN driven high, b4-b6 HPD driven HDMI1..HDMI3, b7 0 |
| 157 | 1 | shd_pwr: power CTRL0..CTRL7 (expander A port 2) as driven, bit n = power-board output n |
| 158 | 2 | shd_i2c_errors: failed shield I2C transactions (NACK, stretch timeout, bus stuck), saturating |

In the shield build the DUT0/DUT1 "powered" sense (target_flags, output
gating) comes from bytes 155 b0/b1 and b4/b5 while b3 is set; with b2 set
and b3 clear the DUTs count as unpowered; with no shield answering (b1 set,
b2 clear) the J/K block sense pins are used as in the normal build.

## 4. Management (port 6500)

`MGMT_SET` type 0x10, host → FPGA:

| Off | Size | Field |
|---|---|---|
| 8 | 2 | cmd_id (host-chosen; repeat of the last applied id is acked, not re-applied) |
| 10 | 2 | key |
| 12 | 2 | value_len |
| 14 | n | value |

`MGMT_ACK` type 0x11, FPGA → requester: cmd_id(2) key(2) status(1: 0 ok,
1 bad key, 2 bad length, 3 bad value, 4 duplicate) pad(1)
config_generation(4).

Keys (whole values, never toggles):

| Key | Len | Meaning |
|---|---|---|
| 0x0001 | 6 | endpoint MAC |
| 0x0002 | 4 | endpoint IPv4 |
| 0x0003 | 4 | telemetry dest IPv4 |
| 0x0004 | 6 | telemetry dest MAC |
| 0x0006 | 1 | DHCP enable (1 = DHCP with fallback; `K_IP` sets static and clears this) |
| 0x0005 | 8 | `SET_IDENTITY`: DNA(8) — only valid in broadcast, followed by MAC(6)+IP(4) (len 18) |
| 0x0010 | 4 | UART baud as NCO increment: `round(baud * 2^32 / 125e6)` |
| 0x0011 | 1 | UART fast mode enable |
| 0x0012 | 1 | UART snapshots enable |
| 0x0013 | 2 | UART snapshot period µs (default 1000) |
| 0x0020 | 1 | keyboard held-key policy |
| 0x0021 | 1 | keyboard ownership override: 0 none, 1 force UDP, 2 force physical, 3 all-up |
| 0x0030 | 1 | keyboard target select (master only) |
| 0x0031 | 1 | video target select (master only) |
| 0x0032 | 1 | coupled selection (1 = default) |
| 0x0033 | 1 | physical keyboard LEDs (master): 0 status (power LED = machine colour, red pulse when the selected DUT is unpowered; default), 1 pass through the selected DUT's LED vector, 2 host vector (key 0x0034) |
| 0x0034 | 12 | host LED vector for mode 2: LED0 R,G,B, LED1 R,G,B, LED2 R,G,B, LED3 R,G,B (LED0/1 drive LED, LED2/3 power LED) |
| 0x0035 | 1 | console screen (issue 0029): 0 auto (select while choosing; else passthrough of HDMI IN to HDMI OUT when the video target is one of this board's DUTs and its video is present (issue 0032); else editable when text is forced or video is present, else no video), 1 editable, 2 no video, 3 select (1..3 force a console screen and disable passthrough) |
| 0x0040 | 1 | Ethernet capture enable (phase 2) |
| 0x0041 | 8 | thumbnail relay forced destination (section 10): MAC(6), scale(1: 1 = 1/2, 2 = 1/4), frame divisor(1: 1..15). MAC 00:00:00:00:00:00 = off (default). A group (multicast/broadcast) MAC, another scale or divisor -> bad value. Board-wide |
| 0x0043 | 2 | inter-board VLAN ID (section 10, issue 0060): u16, 0 = untagged (the behaviour before 2026-11-27), 1..4094 = thumbnail relay requests, lines and no-source frames between boards carry an 802.1Q tag (TPID 0x8100, PCP 0, DEI 0, this VID) and relay frames are accepted only with that VID. Default **1650**. Host-facing traffic (UDP to the host, and relay frames to the key 0x0041 forced MAC) is never tagged. Values > 4094 -> bad value. Board-wide |
| 0x0044 | 1 | HDMI IN owner (section 10, issue 0060): which of this board's DUTs is cabled to the on-board HDMI IN. 0 (default) the video target's DUT (the behaviour before 2026-11-27: both DUTs share the input); 1 DUT0; 2 DUT1; 3 none. A local machine that does not own the HDMI IN (only with 1..3) shows relayed video for its machine number (thumbnails in the mosaic) and, as the video target, a full-resolution relayed picture (section 10, "selected target without local video"). Values > 3 -> bad value. Board-wide |
| 0x0050 | 2 | heartbeat period ms |
| 0x0060 | 1 | target output enable policy (issue 0056): 0 auto: UART TXD, KIO10 and JTAG driven while the DUT is sensed powered (default); 1 force UART TXD and KIO10 on (JTAG still follows the sense); 2 force all of them off, JTAG included (JTAG_REQ then answers status 4, a running transaction is aborted): the host sets 2 before it cuts the DUT's power (`dutctl relay ... power N off`). The shield power-off hold (key 0x0062) overrides 0 and 1 |
| 0x0061 | 1 | physical keyboard CPLD JTAG (section 7, ADR 0014): 0 auto (pins driven while a keyboard is detected and for 10 s after the last detection or keyboard JTAG transaction; default), 1 force on, 2 force off, 3 force on with KB_JTAGEN driven low (diagnostic: does J5 pin 3 gate the CPLD's JTAG port?). Board-wide |
| 0x0062 | 1 | shield power outputs (issue 0049): bit n = CTRL n of the master shield's 1x11 power header = power-board output n (`docs/hardware/power-board.md`; the host maps outputs to machines, as for the relay channels of ADR 0009). Complete state, not a toggle. **Power-off hold** (issue 0056): CTRL0 and CTRL1 are DUT0 and DUT1 of this board (power board CTRLn = DUTn on the master shield); when bit n goes from 1 to 0 (or is 0 when the shield first answers and DUT n is not sensed powered), DUT n's UART TXD, KIO10 and JTAG outputs are forced off from the next clock, before the I2C write drops CTRL n, until bit n is 1 again or DUT n's sense goes low and then high again (powered from elsewhere); target_flags b4 shows it. Bits 2-7 have no effect on this board's outputs. Default after configuration: what expander A already drives if the shield stayed powered (heartbeat shd_flags b5), else all off. Accepted on any board; it only has an effect where `shield_io` runs and the shield answers. Board-wide |
| 0x0063 | 1 | keyboard JTAG quiet (issue 0054): 0 off (the physical keyboard host keeps scanning during keyboard JTAG; measured error floor ~1e-5 per bit on a 0.75 m cable); 1 (default since 2026-11-27: 0 errors in 3.6e7 bits at 2, 7.8 and 20.8 MHz) pause the physical keyboard host while the keyboard JTAG engine is busy: from admission until done, the host runs on to a clean point (MK-I sync phase, KIO8 high; MK-II between I2C transactions, bus released; type 3 between pairs, KIO9 idle high) and stops there with static lines; the first TCK edge waits for that plus a 4 µs guard (start anyway after 4 ms), the resume waits 4 µs after the last edge. The detected keyboard type is kept, the reported matrix is frozen until one complete frame after the resume. 2 physical keyboard host stopped (no keyboard reported, keys released; detection restarts when the key leaves 2); keyboard JTAG then needs key 0x0061 = 1 (the auto lease follows detection). Values > 2 -> bad value. Board-wide |
| 0x0064 | 1 | JTAG TDO sampling (all three JTAG engines, issue 0054; latched when a JTAG_REQ is accepted): 0 one sample of the synchronised TDO at the end of the high half period (default); 1 majority of the last three clk_sys cycles of the high half period (tck_half_period >= 4, else one sample); 2 majority of the last five (half >= 6; half 4..5 -> three). Values > 2 -> bad value. Board-wide |

## 5. Keyboard (port 6502)

`KBD_SET` type 0x20: bitmap(10) at offset 8 (80-bit, bit k = MEGA65 matrix
key k, **1 = pressed**; byte 8 bit 0 = key 0, byte 17 bit 7 = key 79).
The FPGA stores it whether or not the target is powered. Ownership rules per
the design brief §10 (differing bitmap → UDP ownership; identical retransmit
does not). Keys 72–78 are the MK-I extra lines (CAPS LOCK state, UP, LEFT,
RESTORE, DEL dup, RETURN dup, CAPS key) per `mk2_to_mk1.vhdl`.

## 6. UART (port 6503)

`UART_TX` type 0x30, host → FPGA:

| Off | Size | Field |
|---|---|---|
| 8 | 4 | expected_tx_offset (must equal next accepted-byte offset) |
| 12 | 2 | cmd_id |
| 14 | 1 | flags: b0 CLEAR_RX_HISTORY |
| 15 | 1 | reserved |
| 16 | 2 | count (0..1024) |
| 18 | n | data |

All-or-nothing admission. Offset mismatch / insufficient space → rejected,
counter++, expedited snapshot. `count = 0` with CLEAR flag is an idempotent
clear keyed on cmd_id.

`UART_SNAPSHOT` type 0x31, FPGA → telemetry destination:

| Off | Size | Field |
|---|---|---|
| 8 | 4 | boot_id |
| 12 | 4 | snap_seq |
| 16 | 4 | rx_seq (offset of next RX byte; bytes `[rx_seq-512, rx_seq)` below) |
| 20 | 4 | tx_accepted (next expected TX offset) |
| 24 | 4 | tx_emitted |
| 28 | 2 | tx_free |
| 30 | 2 | framing_errors |
| 32 | 2 | rx_overflows |
| 34 | 2 | tx_rejects |
| 36 | 2 | clear_generation |
| 38 | 4 | rx_seq_at_clear |
| 42 | 4 | baud_nco |
| 46 | 2 | reserved |
| 48 | 512 | rx_history (oldest → newest, zero padded at the start) |
| 560 | 128 | tx_history (last emitted bytes, oldest → newest) |

Total 688 bytes. Periodic (1 ms default) and on events per the brief's fast
mode (≥100 µs spacing, coalesced, last byte never lost).

## 7. JTAG (port 6507)

`JTAG_REQ` type 0x40, host → FPGA:

| Off | Size | Field |
|---|---|---|
| 8 | 4 | seq (must equal `jtag_next_seq`) |
| 12 | 4 | tck_half_period (in `clk_sys` cycles, ≥2 → ≤31.25 MHz; default 6 ≈ 10.4 MHz) |
| 16 | 2 | report_period_us (0 = only on completion) |
| 18 | 2 | flags: b0 abort/reset session, b1 target = the physical keyboard's CPLD instead of this endpoint's DUT (ADR 0014; same on either endpoint, own sequence/session) |
| 20 | 4 | bit_count (1..7904, see size limits below) |
| 24 | n | TMS bytes (ceil(bit_count/8)), LSB first |
| 24+n | n | TDI bytes |

`JTAG_RESP` type 0x41, FPGA → requester:

| Off | Size | Field |
|---|---|---|
| 8 | 4 | seq (of the transaction this reports) |
| 12 | 4 | next_seq |
| 16 | 1 | status: 0 done, 1 busy, 2 rejected-seq, 3 rejected-format, 4 aborted-unpowered (keyboard target: JTAG off, key 0x0061) |
| 17 | 1 | target: 0 the DUT, 1 the physical keyboard's CPLD (was reserved, 0) |
| 18 | 2 | tdo_bytes (0 unless status = done) |
| 20 | 4 | bit_count |
| 24 | n | TDO (LSB first, unused high bits zero) |

A repeat of the last completed `seq` returns the cached result without clocking.
A request while busy returns status busy. Exactly `bit_count` TCK pulses; TCK
idles low; TMS/TDI change on the falling edge; TDO sampled on the rising edge
(XVC semantics, design brief §12.1).

**Size limits (amended 2026-11-27, issue 0059).** The supervisor's RX slots
hold 2047 bytes of Ethernet frame including the FCS, so the largest
JTAG_REQ datagram is a UDP payload of 2001 bytes = 8 + 16 + 2 x 988 bytes:
**bit_count <= 7904** (`JTAG_MAX_BITS`, `DP_JTAG_MAX_BITS`; was stated as
8192, which never worked: longer frames were silently dropped by the MAC).
A request whose frame is longer than a slot is now answered with status 3
(rejected-format, nothing clocked, seq not consumed) instead of silence;
the MAC keeps the head of the oversize frame for that purpose (still
counted as an RX drop). The engine itself holds 8192 bits per vector.
The FPGA does not reassemble IP fragments, so a request must also fit one
unfragmented packet on the path: `28 + 8 + 16 + 2 * ceil(bit_count / 8)
<= MTU`, i.e. 5792 bits at MTU 1500; the full 7904 needs MTU >= 2028.
Hosts split longer shifts into consecutive requests (no extra TCK edges;
`dutctl --mtu N` / `$DUTCTL_MTU`, default 1500).

## 8. Raster (port 6504, type 0x60 RASTER, FPGA -> telemetry destination)

One datagram per source raster line (active and, if enabled, blanking),
only while capture is enabled for that DUT (key 0x0040, default off).
Jumbo frames required for active lines (720 px RGB888 = 2160 bytes).

Raster format **version 1** (revised 2026-11-25 before any FPGA
implementation; the leading version byte lets the layout change
independently of PROTO_VERSION — receivers drop unknown versions).

| Off | Size | Field |
|---|---|---|
| 8 | 1 | raster_version = 1 |
| 9 | 1 | encoding: 0 raw RGB888, 1 RLE24 |
| 10 | 1 | flags: b0 VSYNC active, b1 VSYNC polarity (1 = active high), b2 HSYNC polarity, b3 active line, b4 line 0, b5 lines were dropped since the previous packet sent, b6 source locked |
| 11 | 1 | reserved (0) |
| 12 | 4 | frame (increments when line 0 is sent; wraps) |
| 16 | 2 | line: 0 = first active line; active lines 0..v_active-1, then the vertical blanking lines v_active..v_total-1 of the same frame |
| 18 | 2 | h_total (pixels per line incl. blanking, measured) |
| 20 | 2 | v_total (lines per frame incl. blanking, 0 until measured) |
| 22 | 2 | active_count (pixels on this line after decoding; 0 for blanking lines) |
| 24 | 2 | v_active (active lines per frame, 0 until measured) |
| 26 | 2 | hs_start (pixel position where HSYNC becomes active, first active pixel = 0, modulo h_total) |
| 28 | 2 | hs_end (position where HSYNC becomes inactive; half-open) |
| 30 | 2 | payload_bytes |
| 32 | 4 | uart_rx_seq (same counter as UART snapshots, section 6) |
| 36 | 16 | uart_rx_history: latest 16 RX bytes, oldest first; zero padded at the start when fewer were received |
| 52 | n | pixels: raw = R, G, B per pixel, left to right; RLE24 = (count u8 1..255, R, G, B) tuples |

Rules (resolving the issue 0021 questions):

* Common-header length = 44 + payload_bytes. Maximum line width 1024 px:
  payload <= 3072, datagram <= 3124 bytes (+ 28 IP/UDP); the host needs a
  jumbo MTU >= 3200 (a 720-px raw line is 2212 + 28).
* Flag b0 is VSYNC as sampled at this line's x = 0 position (the first
  active pixel's position, also for blanking lines). b4 marks line 0.
  The vertical blanking (including the VSYNC lines) belongs to the frame
  whose active lines precede it.
* A frame is complete when lines 0..v_active-1 all arrived and every one
  has active_count = the frame's h_active (all equal); anything missing
  marks it incomplete (CI must reject it).
* b5 is set on the first packet sent after one or more lines were dropped
  (ring overflow), and only on that packet.
* RLE24 is used only when strictly smaller than raw; active_count always
  counts decoded pixels.
* The heartbeat always carries the video block (payload >= 132 with the
  link block); its h_total/v_total/h_active/v_active are the same
  measurement as in raster packets.

### Heartbeat video block (bytes 108..131, appended; heartbeat payload grows
to 124 bytes; decoders must accept >= 100)

| Off | Size | Field |
|---|---|---|
| 108 | 1 | video_flags: b0 TMDS clock present, b1 locked (aligned + decoding), b2 capture enabled, b3 HDMI mode seen (video/data-island preambles; 0 = DVI source), b4 data islands seen (InfoFrames/audio), both over the last two frames and only while locked (issue 0040; guard bands and islands never count as pixels), b5-b7 reserved (0) |
| 109 | 1 | HDMI OUT shown: 0 editable, 1 no video, 2 select (console screens, issue 0029), 3 passthrough of HDMI IN (issue 0032), 4 full-resolution relayed picture of the video target (section 10, issue 0060) |
| 110 | 2 | h_total |
| 112 | 2 | v_total |
| 114 | 2 | h_active |
| 116 | 2 | v_active |
| 118 | 4 | pixel_clock_hz (measured) |
| 122 | 4 | frames_captured |
| 126 | 2 | raster_lines_dropped |
| 128 | 2 | tmds_decode_errors |
| 130 | 2 | reserved |

## 9. Audio (port 6505)

Phase 4; defined before implementation.

## 10. Thumbnail relay (raw Ethernet, EtherType 0x88B5)

Issues 0035 (local capture, frame store) and 0038 (relay); owner
decisions 2026-11-25. Not IP/UDP: raw Ethernet frames with the IEEE
local-experimental EtherType 0x88B5, so they never leave the lab segment.
Every frame body (after the 14-byte Ethernet header) starts with
`version` (1), `subtype` and `magic` 0x4D36 ("M6", so other users of the
experimental EtherType are ignored). Receivers drop other versions.

Thumbnails: the centre 640x400 of the active picture (x offset
(h_active - 640)/2, y offset (v_active - 400)/2: 40/40 at 480p, 40/88 at
576p), averaged over 2x2 boxes (scale 1/2 -> 320x200) or 4x4 boxes (1/4 ->
160x100), RGB888, every `div`-th source frame (2 = 30 Hz from 60 Hz).

**VLAN (issue 0060, 2026-11-27).** Relay traffic between boards (requests,
lines and no-source frames) carries an 802.1Q tag after the source MAC
(TPID 0x8100, PCP 0, DEI 0, VID = key 0x0043, default **1650**), so the
offsets below are after the 4-byte tag (EtherType 0x88B5 at bytes 16..17 of
the frame). Broadcast requests stay broadcast, only tagged. A board accepts
relay frames only with its VID (untagged only when the key is 0, the
behaviour before). Frames to the key 0x0041 forced MAC (host screenshots)
stay untagged: the lab host has no VLAN interface. Today the thumbnail
relay is the only inter-board traffic (no other Mimas-to-Mimas frames
exist yet; issue 0044's keyboard frames would use the same VLAN). Frames
are padded to 60 bytes + FCS as before (a tagged request is 26 bytes of
header and body).

**Request** (subtype 1), broadcast (ff:ff:ff:ff:ff:ff), 8 bytes:

| Off | Size | Field |
|---|---|---|
| 0 | 1 | version = 1 |
| 1 | 1 | subtype = 1 |
| 2 | 2 | magic 0x4D36 |
| 4 | 1 | scale: 1 = 1/2 (320x200), 2 = 1/4 (160x100), 3 = 1/1 (the whole active picture, issue 0060) |
| 5 | 1 | frame divisor (1..15) |
| 6 | 1 | flags (was reserved 0, issue 0060): b0 targeted (byte 7 is the target machine), b1 priority (the source sends video ahead of its other traffic; 0 = only with spare TX bandwidth), b2..b7 0 |
| 7 | 1 | target machine number 0..31 (was reserved 0), used only with b0; 32..255 match no board |

Examples: untargeted 1/2 at divisor 2 (the select screen's request)
`01 01 4D 36 01 02 00 00`; targeted at machine 5, 1/1, divisor 1, priority
`01 01 4D 36 03 01 03 05` (tests/netproto.py selftest).

A board whose console shows the select screen sends an untargeted request
about every **500 ms** (2 Hz; 250 ms before issue 0060), from its DUT0 MAC,
with scale 1/2 when it has seen <= 4 machines, else 1/4, and divisor 2.
Every board that hears a request (broadcast or to one of its MACs, good
FCS, its VLAN) that is untargeted or targeted at one of its machine numbers
streams its thumbnails for the next ~1 s, **unicast to the request's source
MAC** (latest request wins), at the requested scale and divisor; a targeted
request streams only the target machine. A source drops what it cannot send
at once, never queues or retransmits. The Mimas source stores only 1/2 and
1/4 thumbnails, so it answers a scale 3 request at 1/2 (its lines frames say
scale 1); the full-resolution sources are boards without a frame store of
their own, such as the HewnWeb K325T (hardweb `src/hwvs/`, its
docs/hwvs_implementation.md). Management key 0x0041 forces streaming to a
given MAC instead (host screenshots). Bulk thumbnail frames never go to a
group MAC. A board stores its own thumbnails directly; they never loop
through the network.

**Lines** (subtype 2) and **present, no source** (subtype 3), unicast,
22-byte header:

| Off | Size | Field |
|---|---|---|
| 0 | 1 | version = 1 |
| 1 | 1 | subtype: 2 lines, 3 present, no source |
| 2 | 2 | magic 0x4D36 |
| 4 | 1 | machine number 0..31 (DUT ID nibble * 2 + half, issue 0029) |
| 5 | 1 | flags: b0 source present (lines follow), b1 last frame of this picture |
| 6 | 1 | scale: 1 = 1/2, 2 = 1/4 (0 for subtype 3) |
| 7 | 1 | encoding: 0 RAW888, 1 RLE24 (all lines of this frame) |
| 8 | 4 | picture number (per sender; increments per picture) |
| 12 | 2 | first row of this frame |
| 14 | 2 | line count n |
| 16 | 2 | width: 320 or 160 (0 for subtype 3) |
| 18 | 2 | height: rows in the picture, <= 200 (fewer when the source has fewer than 400 lines) |
| 20 | 2 | payload bytes |
| 22 | p | n lines, top to bottom. RAW888: R, G, B per pixel, left to right. RLE24: (count u8 1..255, R, G, B) tuples as raster (section 8); runs never cross a line end |

Rules:

* Per line the sender uses RLE24 only when strictly smaller than RAW888.
  Lines share a frame while their encoding is the same and the payload stays
  within 8000 bytes, so frames are variable-length, up to 14 + 22 + 8000
  bytes (jumbo; receivers need an MTU of ~8100).
* A picture is complete when rows 0..height-1 all arrived in frames with
  good FCS; the receiver then shows its new buffer. A lost frame means that
  picture is never shown (the next one replaces it). No retransmission.
* A board with no video for one of its machines sends "present, no source"
  (subtype 3) for it about once a second while it is streaming; receivers
  mark the machine seen.
* RAW888 at 1/2 scale and 30 Hz is ~46 Mb/s per source, 1/4 scale ~12 Mb/s
  (less with RLE24).

**Scale 3 = 1/1 (issue 0060).** Lines frames with byte 6 = 3: width
(bytes 16..17) = the active width (<= 1024; this receiver stores up to
1020 pixels per line), height (18..19) = the active height (e.g. 480 or
576, no longer <= 200). No centre crop and no averaging; everything else as
above (per-line RLE24 when strictly smaller, packing within 8000 payload
bytes, flag b1 on the picture's last frame). 720x480 RAW888 at 60 Hz is
~500 Mb/s; one such stream fits a gigabit link.

**Relayed video for local machines (issue 0060).** A board ignores relay
lines for its own machine numbers only when that machine owns the HDMI IN
(key 0x0044; with the default 0 both DUTs own it, as before). A local
machine without local video (key 0x0044 = 1..3) accepts relayed frames for
its machine number like a remote machine: thumbnails appear in its mosaic
tile. This is how a board without HDMI capture of its own (the K325T, whose
UART/JTAG/keyboard are cabled to a Mimas DUT slot) appears in that slot: it
sends with machine number = the slot's machine number (DUT ID nibble * 2 +
half; DUT1 of the bench board, DIP 0x00, is machine 1). Such a slot also
stops announcing "present, no source" for itself while relayed pictures
arrive.

**Selected target without local video (issue 0060).** When the video target
is a local machine that does not own the HDMI IN (key 0x0044 = 1..3), the
console screen is on auto and no selection is pending, the board sends
**targeted, priority, scale 3, divisor 1** requests for that machine every
500 ms for as long as it stays selected, and shows the received pictures
full-screen at full resolution on HDMI OUT (in the 720x480p60 console
timing: a 576-line picture shows its centre 480 lines; the picture is
placed at the top left; up to 720 pixels per line). Pictures go into a
triple-buffered DDR3 frame buffer (word address 0x200000 + buffer *
0x40000, row stride 256 words, xRGB32 as the thumbnail store); the output
switches to the last complete picture at its vertical blank, so a picture
is never shown torn. Without a complete picture in the last second the
console shows its "no video" screen. Passthrough is used only for a video
target that owns the HDMI IN.
