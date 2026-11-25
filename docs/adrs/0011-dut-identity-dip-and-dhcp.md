# ADR 0011: DUT identity from DIP switches, deterministic MACs, DHCP

Status: Accepted (owner request 2026-11-25); supersedes the default
addressing in ADR 0005 §1.

## Context

The farm will hold up to 16 DUTs. Hosts, DHCP reservations, relay channels
and test scripts want a stable "DUT number" that survives moving a Mimas to
another chain position or swapping a supervisor board. Static IPs derived from
a node number (ADR 0005 draft) need per-board configuration and collide easily.

## Decision

* **DUT ID from DIP switches**: each half of a supervisor owns one DUT ID
  (0..15). `DIP[3:0]` = DUT ID of the P12 half (DUT0 port), `DIP[7:4]` = DUT ID
  of the P13 half (DUT1 port). Switch ON = 1, DIP[0] = LSB (to verify against
  the switch legend on hardware). The DUT ID is the farm-wide identity of the
  *target*, not of the supervisor.
* **Deterministic MAC**: `02:4D:36:35:00:<DUT ID>` (locally administered
  unicast). Moving the cables and the DIP setting to another supervisor keeps
  the DUT's MAC, so DHCP reservations follow the DUT.
* If both halves are set to the same DUT ID, the P13 half stays silent (no
  ARP/DHCP/telemetry) and the heartbeat of the P12 half sets an
  `id_conflict` flag (heartbeat `link_flags` bit 6).
* **DHCP client** per endpoint (RFC 2131 subset): DISCOVER → OFFER → REQUEST
  → ACK; option 61 client id = MAC; option 12 host name `m65dut-NN`
  (NN = DUT ID, decimal, 2 digits); options requested: subnet, router, lease.
  Renew by unicast REQUEST at T1 = lease/2; on expiry fall back to DISCOVER.
  NAK → restart. Retries with exponential back-off 1, 2, 4, 8 s (cap 16 s).
* **DHCP is required by default** (owner, 2026-11-25): an endpoint without a
  lease does nothing (no ARP, no telemetry) except DHCP; the seven-segment
  display blinks `dHCP` until every enabled endpoint is addressed, then shows
  the two DUT IDs. A build-time fallback (`DHCP_FALLBACK_MS` generic, 0 =
  off) can instead use `192.168.65.(16 + DUT ID)` after a timeout while DHCP
  keeps trying; the system test uses it with 1 ms. Heartbeat reports the
  address source (DHCP / fallback / static).
* **Static override**: management key `K_IP` sets a static address and stops
  DHCP for that endpoint until reboot or `K_DHCP_EN = 1` (new key 0x0006).
* The DIP-switch-derived defaults replace the DNA hash / node-number scheme.
  The 57-bit DNA (if available) remains the *supervisor* board identity in
  heartbeats.

## Consequences

* A DHCP server (or reservations) on the lab VLAN is recommended; without one
  the fallback still gives deterministic addresses.
* Implementation reuses the owner's HewnWeb/hardweb DHCP sequencer
  (`dhcp_seq`, `dhcp_control`, `dhcp_tx`), relicensed here by the owner
  (see ADR 0012 note on provenance), adapted to the slot/builder structure.
