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

  A repeated `#<id>` within the last 8 ids is answered from cache without
  re-executing (duplicate protection for `CYCLE`). Cycles run
  non-blocking; `POWER` on a channel cancels its pending cycle.
* Off-time minimum 500 ms enforced for `CYCLE` (protect DUT supplies).
* `dutctl relay ...` speaks this protocol; later the daemon owns the port.
* Mimas-driven relays reuse the same command semantics through management
  keys (future ADR).
