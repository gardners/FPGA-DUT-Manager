# 0056: Release (tri-state) DUT JTAG outputs when idle

Status: done, on hardware (build cf8acc83: no JTAG back-feed on the K325T; UART follow-up 0067) (refreshed 2026-11-28; was: implemented on `feature/no-backfeed` (2026-11-27), hardware check pending. Owner question 2026-11-27. Related: 0054, 0055,)
docs/cabling/dut-cable.md section 4.

## Question (owner, 2026-11-27)

"When you finish a JTAG transaction, do you tri-state all pins again? Just
thinking back to what looked like back-powering over JTAG before."

## Current behaviour (lead, from the HDL)

No. `jtag_engine` drives `jtag_oe <= powered`: TCK, TMS and TDI are driven
for as long as the DUT's power sense (VIO or the keyboard cable's 3.3 V)
reads high, with or without a transaction. Between transactions TCK is low
and TMS/TDI hold their last bit (TMS usually '1' after a return to
Test-Logic-Reset). `out-policy` (key 0x0060) does not affect JTAG.

Risk: when the DUT is switched off, a high TMS/TDI back-feeds its 3V3
through the input clamp diodes (8 mA drive, no series resistor on the bench
leads). If that holds the DUT rail above the sense threshold, the sense keeps
reading powered and the outputs keep driving: a self-sustaining back-power
state, which may explain what the owner saw earlier.

## Proposal

* Drive TCK/TMS/TDI only from the start of a transaction until a hold time
  after its end (an output lease, default ~1 s, so a Vivado XVC session
  keeps a steady TAP between shifts); tri-state otherwise. Before releasing,
  park TCK low; at re-drive, start with TCK low and TMS/TDI at their last
  values. The DUT's own pull-ups (7-series TMS/TDI) hold the TAP in a safe
  state while released; TCK edges with TMS high only move it towards
  Test-Logic-Reset.
* Keep the power sense as an additional condition (never drive an
  unpowered DUT), and check it with the outputs released, so our own drive
  cannot hold it up.
* Same for the physical keyboard JTAG engine (it already has a lease, key
  0x0061 auto).
* Possibly a key for the lease length (0 = old behaviour, always driven
  while powered).

## 2026-11-27 owner: do it ("let's burn that down")

Revised plan (lead), simpler than releasing the pins on a timer:

1. **Park TMS and TDI low after every transaction** (TCK is already low).
   No TCK edge happens, so the TAP state is unchanged (TMS/TDI are only
   sampled on TCK edges); XVC sessions keep working. Low outputs cannot
   back-feed an unpowered DUT, and nothing holds its rail up, so the sense
   drops and the existing tri-state takes over. A powered DUT only sees its
   own TMS/TDI pull-ups' ~0.1-0.3 mA into our low outputs. Releasing on a
   timer instead would risk a TCK edge when the line floats to the DUT's
   pull level, which could move the TAP mid-session.
2. **`out-policy` 2 (force off) also forces the JTAG outputs off** (today
   it only covers UART and keyboard), so the host can switch a DUT's
   outputs off before it cuts that DUT's power.
3. **UART to DUT and KIO10 also idle high** and back-feed the same way.
   When the supervisor itself switches a DUT's power (shield power-ctl key
   0x0062, bit n = 0), it forces that DUT's outputs off at the same moment.
   For the relay path, `dutctl relay ... power N off` sets out-policy 2 on
   the DUT mapped to relay channel N in duts.conf first, and `on` restores
   out-policy 0 after switching on.
4. Applies to all three jtag_engines (DUT0, DUT1, keyboard CPLD).

## 2026-11-27 implementation started (sub-agent, branch `feature/no-backfeed`)

Scope: points 1-4 above: TMS/TDI parked low after every transaction in
`jtag_engine` (all three engines), out-policy 2 also gates JTAG, a
power-off hook on the shield CTRL bits (bit n -> DUT n, n = 0..1, matching
the power board's "CTRLn = DUTn power on" labelling), and the `dutctl relay
... power N on|off` hooks via duts.conf. Testbenches, ADR 0005 key text and
`docs/cabling/dut-cable.md` follow.

## 2026-11-27 progress: implemented (sub-agent, `feature/no-backfeed`)

* **Parking**: `jtag_engine` S_DONE (completion and abort) sets TMS = TDI =
  '0' with TCK '0'; no TCK edge. The next transaction drives its first
  TMS/TDI at the start of the low phase, half_period (>= 2) clk cycles
  before the first rising edge (unchanged sequencing). All three engines.
  `tb_jtag_engine` now asserts the parked pins on every idle cycle and
  fails on any TCK edge outside a transaction; new cases end a
  transaction in Run-Test/Idle and in Pause-DR, wait 1 us parked, and
  continue (IDCODE read in two halves across a parked Pause-DR); abort on
  power loss also parks.
* **out-policy 2** (key 0x0060) now also forces JTAG off: new entity
  `hdl/src/top/dut_out_gate.vhd` (+ `tb_dut_out_gate`) feeds the engine's
  `powered` input with `sense and not forced-off`, so a JTAG_REQ gets
  status 4 (unpowered) without consuming the seq and a running one aborts.
  1 still forces only UART TXD / KIO10 on. Heartbeat jtag_status b3 now
  reports the engine's view (unpowered or forced off).
* **Shield power-off hold**: CTRL bit n = DUT n (the power board labels
  CTRLn "DUTn power on"; this board's endpoints are DUT0/DUT1, bits 2-7
  have no effect here). Effective bit = key 0x0062 value once set, else the
  adopted CTRL state. While the shield answers (shd flags b2), bit n 1 -> 0,
  or bit n = 0 when the shield first answers with DUT n unsensed, sets a
  hold: UART TXD, KIO10 and JTAG of DUT n off from the next clock, i.e.
  before the I2C write drops CTRL n. The hold ends when bit n is 1 again or
  the sense goes low and then high (DUT powered from elsewhere); it
  overrides out-policy 1. Heartbeat target_flags b4 = hold (ADR 0005,
  proto_pkg TF_PWR_HOLD, dutproto.h DP_TF_*, netproto TF_*). Not exercised
  in `tb_supervisor_core` (its shield inputs stay at defaults so the
  shield-block checks hold); covered by `tb_dut_out_gate`.
* **dutctl**: `dutctl relay [--raw] TTY POWER N.. OFF|ON`, `ALL OFF`,
  `CYCLE N MS`: out-policy 2 on the DUTs duts.conf maps to those channels
  before switching off; out-policy 0 500 ms after switching on (CYCLE:
  MS + 500 ms). TTYs match by name or realpath. Hook failures warn but do
  not stop the relay command. `src/relayhook.c` + unit tests.
  `jtag-discover --power-cycle` still calls the relay without hooks.
* `tb_supervisor_core` scenario: out-policy 2 -> DUT0 JTAG_REQ status 4,
  out-policy 0 -> same seq reads IDCODE; last heartbeat shows outputs on.
* Tests: 34/34 HDL testbenches, dutctl 356 checks, relay_core 52 checks.
* Vivado build of cf8acc8 (build id cf8acc83; later commits change no
  HDL behaviour, only an unused proto_pkg constant): **WNS 0.095 ns, WHS
  0.049 ns, timing met**. Not loaded on hardware.

Hardware checks for the lead: (1) after an XVC / `jtag-idcode` run, TMS and
TDI on the DUT header read low with the sense powered; (2) `dutctl set IP
out-policy 2` -> `jtag-idcode` answers unpowered, heartbeat target_flags
b2 = 0; 0 -> IDCODE again; (3) a Vivado XVC session over the parked pins
still works (TAP state kept across shifts); (4) switch a DUT off with
out-policy 0: the sense now drops (no back-powered hold-up); (5) shield
build: key 0x0062 bit 0/1 1 -> 0 shows target_flags b4 and tri-states
before CTRL drops.
