# 0046: Keyboard type 3: async protocol for a physical keyboard on a cable up to 3 m

Status: Open (design)
Opened: 2026-11-26 (owner request)

The bench MEGA65 keyboard (MK-I) talks to the supervisor's physical keyboard
port (P12 rows 10-14, `kbd_phys_host`) over the synchronous MK-I protocol:
the host clocks KIO8, sends LED data on KIO9, and receives key data on KIO10.
The data comes back on the host's clock, so at 3 m the cable delay and
ringing eat the timing margin. The goal is to allow a keyboard cable of up
to 3 m.

## Proposal (owner)

New keyboard CPLD firmware with an **asynchronous** mode, **keyboard type
3** (after type 1 MK-I and type 2 MK-II in `kbd_phys_host`):

* UART, 8N1, **2 or 4 Mb/s**, in both directions: host to keyboard on KIO9,
  keyboard to host on KIO10.
* Data is sent as **byte pairs**: the first byte has bit 7 set and its low 7
  bits give the address (one of up to 128 words); the second byte has bit 7
  clear and carries that 7-bit word.
* The "pages" hold exactly the bits of the synchronous protocol, so nothing
  is lost:
  * keyboard to host: the 128-bit MK-I frame (82 matrix bits, 14-bit git
    date, 32-bit git version) = 19 words;
  * host to keyboard: the 128-bit control frame (the 4 RGB LEDs x 8-bit
    brightness, and so on) = 19 words;
  * the CAPS LOCK / SHIFT LOCK LED state (driven locally by the CPLD today),
    as words of their own.
* **Activation:** the keyboard switches to type 3 when it receives a valid
  pair, and stays in it for 100 ms after the last valid pair. The host must
  keep sending (handshake) pairs, or the keyboard falls back to listening
  for the MK-I sync protocol.
* **Safe probing:** type 3 runs with **KIO8 not ticking** (held low). An MK-I
  keyboard only counts a frame while KIO8 clocks, so it ignores KIO9 traffic.
  With KIO8 low, an MK-II's I2C (SCL low) sees no START/STOP either; check
  that in `kbd_phys_host`. So the host can try type 3 first, then fall back to
  the type 1/2 detection.
* **Trade-off:** 20 bits per 7-bit word (start + 8 + stop, twice) = 35 %
  efficiency. At 2 Mb/s that's 100 k pairs/s, so a full 19-word frame takes
  ~0.19 ms, ~5 kHz full updates. That's still faster than the keyboard
  needs; send changed words first, then the full set in rotation.

## Keyboard CPLD facts (from MEGA65/mega65-keyboard-cpld, 2ed09bd)

Cloned to `~/Projects/mega65/mega65-keyboard-cpld` (the path CLAUDE.md
names). One file, `src/top.vhd` (485 lines). Lattice **LCMXO2-1200HC**,
built with Lattice Diamond (`build.sh`, `env.sh`, licence file).

* **Clock:** internal OSCH at **12.09 MHz**, accurate only to about +/-5.5 %.
  That's too coarse for a plain fixed-rate UART (it needs < ~3-4 % total)
  and too slow for 4 Mb/s (3 samples per bit). Options:
  * raise NOM_FREQ (OSCH goes up to 133 MHz; e.g. 38 or 66.5 MHz);
  * **auto-baud from the host's handshake pairs:** measure the start bit
    or a known pattern, and derive the keyboard's TX timing from it. Then the
    host's accurate clock sets the rate.
* **Compatibility:** the sync MK-I mode must keep working unchanged, so the
  same keyboard still works on a real MEGA65.
* **Fit:** check how much of the 1200 LUTs the current design uses
  (Diamond report) before adding the UART RX/TX and decoder.
* An open flow (yosys + nextpnr-machxo2) could avoid the Diamond licence:
  try it, but Diamond is the reference build.

## Flashing the keyboard from the host (remote JTAG)

The physical keyboard harness already wires the keyboard's JTAG (J5 pins
3-7) to unused, never-driven FPGA pins (ADR 0008 amendment 4/5, XDC
comment). With column B = odd pins, that gives these balls (to confirm
against the XDC and the cable):

| J5 pin | Signal | P12 row/col | Ball |
|---|---|---|---|
| 3 | KB_JTAGEN | 13 B | L21 |
| 4 | KB_TMS | 13 A | M21 |
| 5 | KB_TCK | 12 B | L20 |
| 6 | KB_TDI | 12 A | L19 |
| 7 | KB_TDO (in) | 11 B | K19 |

Plan: a third `jtag_engine` instance (or a mux on an existing one) exposed
as an XVC endpoint for the "keyboard", driven only when the keyboard is
detected and powered (tri-state otherwise, like the DUT outputs). Then
`openFPGALoader -c xvc-client --ip BOARD --port PORT -f megakey.jed` (or
Diamond's programmer through XVC) flashes it with no hot-wired JTAG cable.
Check the MachXO2 JTAGEN polarity and whether the configured CPLD keeps
the JTAG port enabled.

## Electrical notes for 3 m

* Single-ended 3.3 V LVCMOS: add series resistors (33-100 ohm) at both
  drivers, use SLOW slew, and twist each signal with a ground (or use
  CAT5/6, pairs = signal + GND). A UART tolerates the 15 ns cable delay
  easily; the risk is ringing at the edges.
* **Supply:** the keyboard's 3.3 V comes from the supervisor (VADJ). Check
  the voltage drop over 3 m at peak LED current; consider sending 5 V and
  regulating locally on the keyboard (then it's a hardware change).

## Steps

1. Write ADR (protocol): word map, handshake, timeout, auto-baud, version
   word.
2. Remote JTAG to the keyboard (FPGA + dutctl), and read the IDCODE: useful
   on its own, and needed for flashing.
3. CPLD firmware with type 3, plus the FPGA host side (`kbd_phys_host`
   type 3) with testbenches. Try it on a short cable, then 3 m.

## 2026-11-26 owner decisions

* **2 Mb/s** (no 4 Mb/s mode). At 12.09 MHz that is only 6 samples per bit,
  and with the OSCH's +/-5.5 % tolerance a fixed divider is still not safe.
  So either raise the OSCH frequency (e.g. 38 MHz = 19 samples per bit), or
  auto-baud from the host's pairs, or both. Decide in the ADR after checking
  the CPLD fit.
* Remote JTAG to the keyboard CPLD (XVC) as proposed.

## 2026-11-27 owner decision

Raise the CPLD oscillator (OSCH NOM_FREQ) for the 2 Mb/s UART, **without
breaking the MK-I protocol**. Everything timed in OSCH cycles has to be
rescaled: the KIO8 frame-start detect (`clock_duration = 31`), the 4-sample
KIO8 filter, the LED PWM (`cnt`) and the idle/ambulance counter
(`cnt_idle(20)`). A testbench must show that the MK-I frames are
bit-identical before and after, using the supervisor's `kbd_mk1_host` as
the reference host.
