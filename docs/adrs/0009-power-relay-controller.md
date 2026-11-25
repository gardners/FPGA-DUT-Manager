# ADR 0009: Relay controller protocol (Arduino now, Mimas GPIO later)

Status: Proposed (2026-11-25)

## Context

Jaycar XC4418 8-channel relay module, active-high inputs (owner confirmed),
5 V coil supply. Initially driven by an Arduino Uno or Nano over USB serial;
later by the master Mimas P13 X-block through level shifters.

## Decision

* Sketch `firmware/relay-controller/relay-controller.ino` builds unchanged for
  Uno and Nano (both ATmega328P); the pin map is a table at the top
  (default D2..D9 → relay 0..7, optional D10 → ATX PS_ON# via transistor).
* Before `setup()` drives anything, outputs are written LOW then set as
  outputs (relays OFF). External 10 kΩ pull-downs on the relay inputs are
  recommended so the board is OFF while the Arduino resets/bootloads.
* Line protocol, 115200 8N1, `\n` terminated, case insensitive. Each command
  may be prefixed `#<id> ` and the reply echoes it:

  | Command | Reply |
  |---|---|
  | `STATUS [<ch> ...]` | `OK STATUS 0 ON 1 OFF 2 CYCLING ... PSU OFF UPTIME <ms>` (all 8 channels, or only those listed) |
  | `POWER <ch> [<ch> ...] ON\|OFF` | `OK POWER <ch> ... ON\|OFF`; all listed channels or none (idempotent) |
  | `CYCLE <ch> <ms>` | `OK CYCLE <ch> <ms>` then `EVENT CYCLED <ch> ON` |
  | `ALL OFF` | `OK ALL OFF` |
  | `PSU ON\|OFF` | `OK PSU ON\|OFF` |
  | `VERSION` | `OK VERSION relay-controller 3 LIMIT <n>` |
  | anything else | `ERR <reason>` |

  Version 3 (owner 2026-11-25): `ON`/`OFF` words instead of 0/1 to avoid
  ambiguity, several channels per `POWER`, per-channel `STATUS`. Channels
  are 0..7 (relay module IN1..IN8). At boot the controller prints
  `EVENT BOOT relay-controller 3`.

  A repeated `#<id>` within the last 4 state-changing commands is answered
  from cache without re-executing (duplicate protection for `CYCLE`;
  STATUS and VERSION are not cached). Cycles run non-blocking; `POWER` on a channel cancels its pending cycle.
* Off-time minimum 500 ms enforced for `CYCLE` (protect DUT supplies).
* `dutctl relay ...` speaks this protocol; later the daemon owns the port.
* Mimas-driven relays reuse the same command semantics through management
  keys (future ADR).

## Wiring (amendment, owner 2026-11-25)

Eight consecutive digital lines plus a separate 2-pin power header:

| Uno R3 pin | Strip | XC4418 |
|---|---|---|
| D2..D7 | 6-way (digital header D0..D7) | IN1..IN6 |
| D8, D9 | 2-way (digital header D8..D13) | IN7, IN8 |
| 5V, GND (adjacent on the power header) | 2-way | VCC, GND |

* There is no run of 8 usable lines on one Uno header. D0/D1 carry USB
  serial, D8..D13 has only six pins, and the R3's two digital headers sit
  0.16" apart (not on the 0.1" grid), so D2..D9 needs a 6-way strip and a
  2-way strip. The relay side can be one 1x8 housing on IN1..IN8.
  VCC and GND sit at the two ends of the module's header, so the 2-way
  power strip splits there.
* Unused on purpose: D0/D1 (serial), D10 (optional PS_ON#), D13 (blinks
  during bootloading).
* **Relays and power (corrected 2026-11-25):** the module's relays are
  SRLD-12VDC-SL-C, with 12 V coils (about 30-37 mA each; must-operate
  voltage at most 9 V). Feed 12 V into the Uno's DC barrel, for example
  from the PC supply's 12 V. The Uno then runs from its own regulator,
  not from USB. Power the module from the power header's adjacent **VIN
  and GND** pins: VIN is the barrel voltage minus the reverse-protection
  diode, about 11.3 V. Six coils draw about 0.2 A, well within the diode
  (1 A). 5 V into the barrel does not work: VIN would be about 4.3 V,
  which cannot pull in a 12 V relay, and the Uno falls back to USB power.
* **Check before connecting the IN lines:** with the module powered at
  12 V and the Uno disconnected, measure each IN pin to GND. It must be
  near 0 V or floating, never pulled up towards 12 V, which would damage
  the Uno's pins.
* **Limit:** the firmware can refuse to have more than `RELAY_MAX_ON`
  relays on at once, counting channels whose `CYCLE` will switch them back
  on. It answers `ERR LIMIT n ON`; switching off is always allowed. With 12 V
  coils run from VIN, the owner set the limit to 8 (no limit). The unit
  tests build with 5 to exercise it. `VERSION` reports
  `relay-controller 3 LIMIT 8`.
