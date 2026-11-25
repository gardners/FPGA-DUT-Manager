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
  | `STATUS` | `OK STATUS <8-bit mask hex> PSU <0/1> UPTIME <ms>` |
  | `POWER <ch> <0/1>` | `OK POWER <ch> <0/1> MASK <hex>` (idempotent) |
  | `CYCLE <ch> <ms>` | `OK CYCLE <ch> <ms>` then `EVENT CYCLED <ch> MASK <hex>` |
  | `ALL OFF` | `OK ALL OFF MASK 00` |
  | `PSU <0/1>` | `OK PSU <0/1>` |
  | `VERSION` | `OK VERSION relay-controller 1` |
  | anything else | `ERR <reason>` |

  A repeated `#<id>` within the last 4 ids is answered from cache without
  re-executing (duplicate protection for `CYCLE`). Cycles run
  non-blocking; `POWER` on a channel cancels its pending cycle.
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
* **Current:** each relay coil takes about 70-80 mA, so about 0.6 A with
  all eight on. The Uno's 5V pin fed from USB is behind a 500 mA
  polyfuse, so with many relays on the Uno can brown out and reset, and
  the relays then drop. For more than about 4 relays on at once, power the
  relay board VCC from the ATX 5 VSB (or another 5 V supply) with grounds
  common, keeping only the IN lines (and GND) from the Uno. If the module
  has a JD-VCC jumper, coil power can be separated completely.
