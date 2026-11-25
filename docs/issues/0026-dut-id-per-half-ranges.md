# 0026: DUT IDs per half: 0x0n (P12) and 0x1m (P13)

Status: Done (2026-11-25)
Opened: 2026-11-25

Owner request (2026-11-25). Today ADR 0011 gives each half a DUT ID 0..15
from `DIP[3:0]` (P12) and `DIP[7:4]` (P13). With the same DIP nibble on both
halves (e.g. DIP = 0xFF, as on the bring-up board) both halves are DUT 15,
the P13 half goes silent and `id_conflict` is raised. Hardware 2026-11-25:
only `dut0` heartbeats were seen, for exactly that reason.

Proposal:

* P12 half DUT ID = `0x0n`, n = `DIP[3:0]` (0x00..0x0F);
  P13 half DUT ID = `0x1m`, m = `DIP[7:4]` (0x10..0x1F).
  The two halves can then never collide, and IDs are farm-wide unique
  provided each DIP nibble is used once per range.
* Seven-segment: `n-1m`, i.e. P12 as one hex digit, a dash, then P13 as two
  digits (`1m`) — fits the 4 digits (e.g. `F-1F`).
* Derived identities follow the ID: MAC `02:4D:36:35:00:<ID>` (now 0x00..0x1F),
  DHCP host name `m65dutNN` (decide: decimal `00..31` or hex `00..1F`;
  ADR 0011 currently says decimal), fallback IP `192.168.65.(16 + ID)`.
* The intra-board conflict check becomes unnecessary (keep the
  `id_conflict` flag bit reserved / always 0, or drop it).
* Touches: ADR 0011 (amend), `supervisor_core` (id0/id1, conflict logic),
  `seg7_status`, `net_tx` DHCP host name digits, heartbeat `dut_id` byte,
  `tests/netproto.py` + scenario, `dutctl listen` display, text status screen.

## 2026-11-25 implemented

IDs `'0' & DIP[3:0]` / `'1' & DIP[7:4]`; ep_enable always "11"; hex host
names; seg7 `n-1m`; ADR 0011 amended, ADR 0005 b6 reserved. System test now
expects DUT1 = 0x11 (DIP 0x10): MAC ..:11, m65dut11, fallback .33.
Status: Done pending hardware check (owner reported " 0-0" before this).

## 2026-11-25 closed

0x0n/0x1m IDs verified on hardware (seg7 0-10, DUT 0 and DUT 0x10 on DHCP).
