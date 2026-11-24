# ADR 0006: Keyboard — always present MK-I to DUTs; host both MK-I and MK-II

Status: Accepted (2026-11-25)

## Context

MEGA65 mainboards (R3 onwards) share one 3-signal keyboard connector:
`KIO8`/`kb_io0`, `KIO9`/`kb_io1`, `KIO10`/`kb_io2`. Two keyboard generations exist:

* **MK-I**: a CPLD on the keyboard. The mainboard (`mega65kbd_to_matrix.vhdl`)
  drives KIO8 as a ~305 kHz clock (cpuclock/2/65 at 40.5 MHz) with a long
  high "sync" pulse after 128 bits, shifts LED data out on KIO9 (128 bits,
  12 × 8-bit RGB values for four LEDs), and samples key state on KIO10
  (bits 0–79 matrix, 72–78 extra lines, 82–95 datestamp, 96–127 commit id).
* **MK-II**: a passive matrix with I2C IO expanders on KIO8/KIO9 (SDA/SCL);
  holds KIO10 low. Newer mainboard bitstreams auto-detect: KIO10 ever high →
  MK-I, else MK-II after 5000 cycles (`mega65r6.vhdl`). They convert MK-II to
  the MK-I stream internally with `mk2_to_mk1.vhdl`.

## Decision

* **DUT side**: each supervisor emulates an MK-I keyboard on each DUT's
  keyboard connector (`kbd_mk1_device`). The serial behaviour is lifted from
  the keyboard-facing half of `mk2_to_mk1.vhdl` (LGPL, mega65-core
  467d2b0a8): detect sync as KIO8 high for ≥ 6 µs, then on each KIO8 rising
  edge shift out the 128-bit response (matrix with DEL/RETURN duplicated at
  76/77, datestamp, "MKII"-style id replaced by our own id `"SUPV"`), and shift
  in the 96-bit LED vector from KIO9. KIO10 is driven only when target power is
  sensed; otherwise tri-stated. Since KIO10 goes high, any MEGA65 bitstream
  selects MK-I.
* **Physical keyboard** (master's own connector): `kbd_phys_host` runs the
  MK-I host protocol (from `mega65kbd_to_matrix.vhdl`) and the MK-II I2C
  scanner (from `mk2_to_mk1.vhdl`) behind the same auto-detection rule as
  `mega65r6.vhdl`, producing one 80-bit bitmap and accepting a 96-bit LED
  vector to display (selected-target colour / DUT LED passthrough).
* Bitmap canonical form everywhere inside the supervisor and on the wire:
  80 bits, index = MEGA65 matrix key number, **1 = pressed**. Inversion to
  active-low happens only at the MK-I serial boundary.
* The physical keyboard needs +5 V and GND from the supervisor side cable,
  never from a DUT (design brief §6).
* CAPS LOCK (key 72) is a latched state on the real keyboard. For UDP control
  it is just a bit the host sets; MK-II latching logic stays in the physical
  host path.

## Consequences

* The mega65-core files are imported verbatim into `third_party/mega65-core/`
  for testbench use (host model) and adapted copies with attribution live in
  `hdl/src/kbd/`.
* Testbench pairs our device emulator with the real `mega65kbd_to_matrix`
  (host) and checks every key reaches the matrix RAM, and that LED vectors
  round-trip.
