# ADR 0014: Keyboard type 3 (async UART for long cables) and keyboard CPLD JTAG

Status: Proposed (2026-11-27); owner decisions of 2026-11-26/27 in issue 0046.

## Context

The bench MEGA65 keyboard (MK-I, a Lattice LCMXO2-1200HC CPLD) speaks the
synchronous MK-I protocol: the host clocks KIO8, the keyboard answers on
KIO10 on the host's clock. Over a 3 m cable the round trip and ringing eat
the timing margin. The owner wants a third protocol, keyboard **type 3**,
that is asynchronous, can be probed safely, and leaves MK-I working
unchanged (the same keyboard must still work on any MEGA65). The firmware
lives in MEGA65/mega65-keyboard-cpld (branch `long-keyboard-cable-protocol`, pushed 2026-11-28; was local `type3`); the host side
is `kbd_t3_host` inside `kbd_phys_host`.

The owner also wants to flash the keyboard CPLD from the host through the
keyboard's JTAG pins (J5 pins 3-7), which the physical keyboard harness
already wires to FPGA pins.

## Decision: the type-3 protocol

### Physical layer

* UART 8N1, LSB first, idle high, **2 Mb/s** (the supervisor uses 125 MHz /
  62 = 2.016 Mb/s; the keyboard follows whatever rate the host uses).
* Host -> keyboard on **KIO9**, keyboard -> host on **KIO10**. The host holds
  **KIO8 low** (push-pull) the whole time.
* Everything is sent as **byte pairs**, back to back: an address byte
  (bit 7 = 1, bits 6..0 = word address) followed immediately by a data byte
  (bit 7 = 0, bits 6..0 = the word). A data byte without a preceding address
  byte, a framing error, or an address byte followed by another address
  byte discards the pending address. **Address 0 is never sent** (see
  auto-baud).

### Word map

Words 1..19, **in order**, carry exactly the 128 bits of the synchronous
frames, in MK-I order: word a bit b = stream bit i = 7(a-1)+b; bits 128..132
(word 19 bits 2..6) are padding (host -> keyboard: 0; keyboard -> host:
unspecified, ignored).

* Host -> keyboard stream: the control frame as an MK-I host shifts it out,
  bit 127 first: stream bit i = control bit 127 - i, where the control
  frame is `mega65_control_data` in the CPLD (`kbd_mk1_host`:
  `x"00000000" & leds`, so control bits 95..0 = the LED vector).
* Keyboard -> host stream: stream bit i = frame bit i as a MEGA65 reads it
  (`sampled(i)` in `kbd_mk1_host`): 0..81 matrix (active low; 72 = not CAPS
  LOCK state, 78 = CAPS key, 76/77 = DEL/RETURN copies), 82..95 date stamp,
  96..127 commit id. Unlike the MK-I wire, keys 0 and 1 arrive directly.

The keyboard shifts the received words into its MK-I input shift register
and latches the control frame after word 19, exactly like the MK-I path
(so a frame applies atomically); a word out of order (an address 1..19 other
than the next expected, or a framing error) restarts at word 1. It sends
its words by rotating its MK-I output shift register, loaded as at an MK-I
frame start before each word 1. Reusing the MK-I registers keeps the CPLD
logic small.

| Address | Host -> keyboard | Keyboard -> host |
|---|---|---|
| 1..19 | control stream, in order (above) | key frame stream (above) |
| 20 | lock LED override: b0 CAPS override, b1 CAPS LED value, b2 SHIFT override, b3 SHIFT LED value (value = shown as if the lock were on; 0 = the CPLD drives the LEDs from its own lock state, as today) | lock state: b0 CAPS LOCK on, b1 SHIFT LOCK on, b2 CAPS LED lit, b3 SHIFT LED lit |
| 21 | (reserved) | protocol version, currently 1 |
| 127 | sync: data must be 0 (auto-baud reference) | (reserved) |
| 0 | never used | never used |
| 22..126 | reserved, ignored | reserved, ignored |

### Schedule

* Host: sends continuously. Every fourth pair is the sync pair (127, 0); the
  others cycle through words 1..20 (27 pairs, ~270 us, for a full update).
* Keyboard: while in type 3, sends words 1..21 in rotation, back to back
  (21 pairs = 420 bits = 210 us at 2 Mb/s, about 4.8 kHz full updates; the
  matrix itself is scanned every 212 us). Words 1..19 are a snapshot of the
  matrix taken before word 1.
* The host publishes a frame when word 19 arrives and all of words 1..19
  arrived since the last publication. The keyboard latches a control frame
  when words 1..19 arrived in order (sync and word-20 pairs may be
  interleaved).

A "changed words first" schedule (issue 0046) was not needed: a full
rotation is already faster than the scan, and it would cost CPLD logic.

### Activation, handshake and timeout

* The keyboard **enters type 3** on a valid pair received while KIO8 has
  been low through three wraps of its 256-cycle scan counter (64-85 us). An
  MK-I host toggles KIO8 every 1.6 us, so MK-I LED data on KIO9 can never
  enter type 3.
* It **stays** in type 3 for 100 ms (1 209 000 MK-I clock-enable cycles,
  counted by the existing `cnt_idle`, which every valid pair restarts) after
  the last valid pair; the host must keep sending.
* It **leaves at once** when KIO8 is high for 3 OSCH cycles (an MK-I host
  started clocking), so a MEGA65 that comes up after noise put the keyboard
  in type 3 is served within one frame. MK-I logic keeps running in
  parallel the whole time; only the KIO10 pin is switched.
* The MK-I ambulance-light timer is reset by every valid pair.

### Clock, auto-baud and oscillator tolerance

* **OSCH NOM_FREQ 12.09 -> 24.18 MHz.** 24.18 is exactly 2 x 12.09, so the
  whole MK-I logic runs unchanged on a clock enable every second cycle, at
  exactly the old rate. Every OSCH-cycle-timed constant (the 4-sample KIO8
  filter, `clock_duration = 31` frame-start detect, the LED PWM / scan
  counter `cnt`, the `cnt_idle` ambulance timer, the CAPS LOCK hold time) is
  rescaled by construction, with no constant edited. `tb_megakey_mk1_compat`
  runs 2ed09bd and the new firmware side by side from aligned oscillator
  models under this repo's `kbd_mk1_host` and checks KIO10, all LED outputs
  and SCAN_OUT at every 12.09 MHz edge, plus identical frames. A frequency
  that is not a multiple of 12.09 (38.00, 66.50) would have meant rescaling
  and rounding each constant by hand; 133.00 (11 x) is a multiple but is a
  poor fit for a -5 MachXO2 with 128-bit shift registers and 32-bit
  counters.
* The UART runs at the full 24.18 MHz: 12.1 samples per bit at 2 Mb/s.
* The OSCH is only accurate to +/-5.5 %, more than a fixed-divider UART
  tolerates (~4.4 % with this sampling). So the keyboard **auto-bauds**:
  * Without address 0, the longest low run in valid traffic is a data byte
    of value 0: start bit + 8 zero bits = **9 bit times** (any other byte
    has at most 7). At 24.18 MHz +/-5.5 % that is 102.8..114.8 cycles, the
    longest 7-bit run at most 89.3. The keyboard accepts a low run of
    96..127 cycles on KIO9 (bits 7..5 = "011", only while KIO8 is quiet) as
    L9 = 9 bit times. (A 10-bit low run could also fall in the window, but
    valid traffic has none.)
  * RX and TX bit timing come from L9 with a fractional timer: add 9 per
    cycle, wrap at L9 (one bit per L9/9 cycles); RX starts at L9/2 on the
    start-bit edge (mid-bit sampling). Error +/-1-2 cycles in 109 = ~1-2 %,
    at most ~20 % of a bit at the stop bit. The keyboard's TX therefore
    matches the host's rate to ~2 %, which the host's fixed-rate receiver
    tolerates.
  * The host's sync pair (127, 0) provides the measurement every fourth
    pair; any zero data word does too. Until the first measurement the
    keyboard uses the nominal value (109).
* `tb_kbd_t3_host` runs the firmware at nominal, 5.5 % slow and 5.5 % fast
  oscillator (each entered with the stale value of the previous run, up to
  11 % off), with 20 ns cable delay each way: locks in ~0.2-0.4 ms, no
  receive errors after lock, keys/commit/date/version/lock word/LEDs right.

### Host side: probe order and safety (`kbd_phys_host`)

1. **Probe type 3 first** (2 ms): drive KIO9 (SCL for an MK-II) low, then
   KIO8 (SDA) low, 2 us apart; then the UART on KIO9. At the end: KIO9 low,
   then release KIO8, then hand the pins over. So SDA never changes while
   SCL is high: an MK-II's expanders see no START or STOP and ignore the SCL
   pulses (checked by `tb_kbd_phys_host` with the TCA9555 models attached).
   An old MK-I keyboard only shifts on KIO8 edges and KIO8 does not move.
2. No answer -> the existing R6 rule (MK-II, KIO10 high -> MK-I).
3. **Re-probe** every 2 s while the port shows no keyboard or an MK-I (a
   type-3 keyboard also speaks MK-I, so this upgrades it; the first two MK-I
   frames after a probe are not published, so the keys do not glitch), but
   **never while an MK-II answers**. A type-3 keyboard that stops answering
   for 10 ms is probed again at once.
4. Heartbeat `kbd_phys_type` 3 = type 3 (ADR 0005 s3).

### Versioning

Keyboard word 21 carries the protocol version (1). Both ends ignore unknown
addresses, so new words can be added in the reserved range without a new
version; an incompatible change bumps it. The commit id (words 14..19) still
identifies the exact firmware build.

## Decision: JTAG to the keyboard CPLD

* The harness wires J5 pins 3-7 to P12 rows 13-11 B: **KB_JTAGEN L21, KB_TMS
  M21, KB_TCK L20, KB_TDI L19, KB_TDO K19** (row r = GPIO_(r-5), column A =
  _P, B = _N; matches issue 0046's table and ADR 0008 amendments 4/5). All
  five are in `boards/mimas_a7/pk_jtag_bodge.xdc`, read only by the normal
  (bodge) build. The **shield build** (`SHIELD_RX` > 0, issues 0045/0049)
  gives L19/L20/M21/L21 to HDMI3 and uses PK_TCK H19, PK_TMS M20, PK_TDI
  H18, PK_TDO K19 (`shield_v1.xdc`); its PK_JTAGEN is on I2C expander B
  (TCA6416A @0x20, P0.3), so the top level has no `pk_jtagen` port there
  (null vector) and leaves `pk_jtagen_want` for the shield I2C master
  (issue 0049 step 2).
* A **third `jtag_engine`** drives them. It is reached through either
  endpoint with **JTAG_REQ flags b1** (ADR 0005 s7); its response carries
  **byte 17 = 1** (target keyboard). It has its own sequence/session state.
  Capability bit b8 announces it.
* The keyboard is powered from the Mimas, so "powered" means *wanted*: in
  auto mode (MGMT key **0x0061** = 0) the pins are driven while a keyboard
  is detected and for 10 s after the last detection or keyboard JTAG
  transaction (a CPLD being flashed stops answering on KIO10, and erase
  takes seconds). 1 forces them on (a blank CPLD is never detected), 2 off,
  3 on with KB_JTAGEN driven **low** (TCK/TMS/TDI as normal): a diagnostic
  for the pin-3 question below (IDCODE in mode 1 and mode 3: fails in mode
  3 = pin 3 is JTAGENB with `JTAG_PORT = DISABLE`; works = the JTAG port is
  always enabled; flashing works either way in mode 0/1).
  Otherwise TCK/TMS/TDI/JTAGEN are tri-stated, with weak pulls holding the
  TAP quiet (TCK and JTAGEN low, TMS/TDI high, TDO pulled up).
* **KB_JTAGEN** is driven high while enabled. MachXO2 semantics (TN1204):
  with the default sysCONFIG `JTAG_PORT = ENABLE` the four JTAG pins are
  dedicated and always active (JTAGENB is then an ordinary user I/O, unused
  in this design); with `JTAG_PORT = DISABLE` they become GPIO and the
  JTAGENB pin re-enables JTAG when high. Driving it high works in both
  cases; the MEGA65 mainboard holds it low. *Unverified:* that J5 pin 3
  goes to the CPLD's JTAGENB pin (MK-I keyboard schematic not in the
  local repos), and the Diamond strategy's `PROP_BIT_JTAGEnableBitGen =
  False` setting, which Diamond should be asked about before relying on
  JTAGENB.
* Host: `dutctl jtag-idcode IP --kbd` and `dutctl xvc IP --kbd` (default
  TCK ~2 MHz for the keyboard; XVC `settck` overrides);
  `dutctl set IP kbd-jtag 0|1|2`.

## Consequences

* The CPLD firmware must be rebuilt with Lattice Diamond (not installed yet)
  and its fit checked (LCMXO2-1200HC: 1280 LUT4s, 1280 flip-flops). A rough
  open-source estimate (ghdl --synth + yosys `synth_lattice -family xo2
  -abc9`, counting a carry cell CCU2D as two LUT4s): upstream 2ed09bd 675
  LUT4-equivalents / 560 FFs (abc: 664), type-3 firmware 1009 / 681 (abc:
  921), i.e. 72-79 % of the LUTs and 53 % of the FFs. A first version with separate word multiplexers estimated above
  100 %; reusing the MK-I shift registers brought it down. If Diamond does
  not fit it, the next savings are the lock override and lock/version words
  and one shared bit timer for RX and TX.
* Old MK-I keyboards and MK-II keyboards behave as before (after a 2 ms
  probe at power-up and, for MK-I, every 2 s).
* The same keyboard keeps working on a real MEGA65 (MK-I).
* Flashing the keyboard needs no hot-wired JTAG cable: XVC through the
  supervisor (procedure in issue 0046).
