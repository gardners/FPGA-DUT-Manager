# ADR 0005: UDP wire protocol v1 (interface control document)

Status: Proposed (2026-11-25). The owner reviews; implementation proceeds on
this basis. Every change bumps `PROTO_VERSION` or uses a reserved field.

Canonical sources: this document, `hdl/src/proto/proto_pkg.vhd` (FPGA
constants) and `sw/dutctl/include/dutproto.h` (host). Golden packets in
`tests/vectors/` are checked by both the nvc testbenches and the C unit tests,
so the two implementations cannot silently diverge.

## 1. Addressing

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
| 6 | 1 | dut | 0/1; must equal the endpoint addressed, else dropped |
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
| 31 | 1 | link_flags: b0 eth link up, b1 1000 Mb/s, b2 full duplex, b3 chain up-link ok, b4 chain down-link ok, b5 is master |
| 32 | 4 | capabilities: b0 uart, b1 jtag, b2 kbd device, b3 phys kbd host, b4 hdmi capture, b5 chain, b6 audio |
| 36 | 4 | config_generation |
| 40 | 1 | target_flags: b0 kbd 3V3 sense, b1 JTAG VREF sense, b2 outputs enabled, b3 sense valid |
| 41 | 1 | kbd_owner: 0 UDP, 1 physical |
| 42 | 1 | kbd_policy: 0 REQUIRE_FRESH_PRESS, 1 ACCEPT_HELD |
| 43 | 1 | selected: hi nibble video target 0..7/F none, lo nibble kbd target |
| 44 | 10 | kbd_effective (80-bit, bit k = matrix key k, 1 = pressed) |
| 54 | 10 | kbd_udp |
| 64 | 10 | kbd_physical (master: raw physical bitmap; else zero) |
| 74 | 2 | kbd_phys_change_count |
| 76 | 1 | kbd_phys_type: 0 none, 1 MK-I, 2 MK-II |
| 77 | 1 | jtag_status: b0 busy, b1 result ready, b2 aborted, b3 target unpowered |
| 78 | 4 | jtag_next_seq |
| 82 | 4 | uart_rx_seq |
| 86 | 4 | uart_tx_accepted |
| 90 | 2 | rx_rejects |
| 92 | 2 | tx_drops (scheduler/ring) |
| 94 | 12 | dut_leds (MK-I LED vector bits 95..0 received from the DUT) |
| 106 | 2 | reserved (video lock/geometry block follows in phase 2) |

Total 108 bytes (header + 100).

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
| 0x0040 | 1 | Ethernet capture enable (phase 2) |
| 0x0050 | 2 | heartbeat period ms |
| 0x0060 | 1 | target output enable policy: 0 auto (sense), 1 force on, 2 force off |

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
| 18 | 2 | flags: b0 abort/reset session |
| 20 | 4 | bit_count (1..8192) |
| 24 | n | TMS bytes (ceil(bit_count/8)), LSB first |
| 24+n | n | TDI bytes |

`JTAG_RESP` type 0x41, FPGA → requester:

| Off | Size | Field |
|---|---|---|
| 8 | 4 | seq (of the transaction this reports) |
| 12 | 4 | next_seq |
| 16 | 1 | status: 0 done, 1 busy, 2 rejected-seq, 3 rejected-format, 4 aborted-unpowered |
| 17 | 1 | reserved |
| 18 | 2 | tdo_bytes (0 unless status = done) |
| 20 | 4 | bit_count |
| 24 | n | TDO (LSB first, unused high bits zero) |

A repeat of the last completed `seq` returns the cached result without clocking.
A request while busy returns status busy. Exactly `bit_count` TCK pulses; TCK
idles low; TMS/TDI change on the falling edge; TDO sampled on the rising edge
(XVC semantics, design brief §12.1).

## 8. Raster and audio

Phase 2/4; layouts per design brief §9 will be added here before
implementation.
