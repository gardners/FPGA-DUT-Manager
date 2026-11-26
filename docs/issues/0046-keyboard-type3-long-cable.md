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

## 2026-11-27 progress (branch `feature/kbd-type3`; CPLD branch `type3`)

**Decisions taken here** (ADR 0014 has the details):

* OSCH **24.18 MHz** (exactly 2 x 12.09): all MK-I logic runs on a clock
  enable every second cycle, so every OSCH-timed constant keeps its meaning
  with no constant edited. 38/66.5 MHz are not multiples of 12.09; 133 MHz
  is, but is a poor fit for the -5 part.
* **Auto-baud** as well: address 0 is never used, so the only 9-bit low run
  is a zero data byte (host sync pair 127/0 every fourth pair); the keyboard
  measures it (window 96..127 cycles) and times RX and TX from it with a
  fractional timer. Locks in ~0.2 ms at nominal and +/-5.5 % OSCH.
* Words 1..19 carry the MK-I bit streams in order (host -> keyboard control
  bit 127 first; keyboard -> host frame bit 0 first), so the CPLD reuses its
  MK-I shift registers and latch. Word 20 lock state / LED override, 21
  protocol version (1).
* Enter type 3 on a valid pair with KIO8 quiet >= 64 us; leave 100 ms after
  the last pair (existing `cnt_idle`) or at once on KIO8 high.
* Host probes type 3 first (2 ms), SCL low before SDA so an MK-II sees no
  START/STOP; re-probes every 2 s with no keyboard or an MK-I, never with
  an MK-II. Heartbeat `kbd_phys_type` 3.
* Keyboard CPLD JTAG: third `jtag_engine`, JTAG_REQ flags b1 on either
  endpoint, response byte 17 = target, capability b8, MGMT key 0x0061
  (0 auto: while a keyboard is detected + 10 s lease after detection or a
  transaction; 1 on; 2 off). Pins as in the table above (verified against
  the vendor XDC: row r = GPIO_(r-5), A = _P, B = _N): JTAGEN L21, TMS M21,
  TCK L20, TDI L19, TDO K19. They are grouped in `mimas_a7.xdc` so issue
  0045 can move them (it wants the GPIO_7 SRCC pair L19/L20).
* MK-II with KIO8 low: harmless (no START/STOP, see above;
  `tb_kbd_phys_host` checks it with the TCA9555 models on the bus).

**Works in simulation** (`make test`: 30 HDL testbenches, 228 C checks, 52
relay checks, all pass):

* `tb_megakey_mk1_compat`: upstream 2ed09bd and the type-3 firmware side by
  side under this repo's `kbd_mk1_host`, aligned 12.09/24.18 MHz OSCH
  models: KIO10, all 14 LED outputs and SCAN_OUT identical at all 163 117
  compared edges, identical frames (29), plus key positions (F3, DEL,
  RETURN, SPACE, CAPS LOCK latch/raw, SHIFT LOCK).
* `tb_kbd_t3_host`: `kbd_t3_host` + type-3 firmware, 20 ns cable delay each
  way, OSCH nominal / -5.5 % / +5.5 % (each from the previous run's stale
  auto-baud value): keys, commit, date, version, CAPS LOCK word, LED vector
  in the CPLD's control frame, no receive errors after lock, 100 ms
  timeout (shortened), immediate exit on KIO8 high.
* `tb_kbd_phys_host`: MK-II at power-up (probe first, no START/STOP), MK-I
  plus a re-probe without key glitches, the type-3 firmware (MK-I first,
  type 3 after the next re-probe), unplug, MK-II again.
* `tb_supervisor_core`: keyboard TAP model (IDCODE 0x012BA043) unpowered
  without a keyboard, key 0x0061 = 3 rejected, IDCODE after forcing on.
* Simulation pieces: `hdl/sim/machxo2/osch_model.vhd` (library machxo2,
  run-time trim, stop flag), `hdl/sim/kbd_matrix_model.vhd`,
  `third_party/mega65-keyboard-cpld/` (copies made by
  `scripts/sync-kbd-cpld.sh`; the CPLD repo stays the master copy).

**Vivado** (build 08e9a846, first HDL version): TIMING MET, WNS +0.154 ns,
WHS +0.008 ns; 18488 LUTs (56.7 %), 21562 FFs (33.1 %), 33 BRAM tiles, 143
IOBs. (Final build: see the next note.)

**CPLD size (rough, no Diamond here)**: ghdl --synth + yosys `synth_lattice
-family xo2`, CCU2D counted as two LUT4s: upstream 664-675 LUT4-equivalents
/ 560 FFs; type-3 firmware 921-1009 / 681 (72-79 % of 1280 LUTs). A first
version with word multiplexers was over 100 %; reusing the MK-I registers
fixed that. **Diamond must confirm the fit.**

**CPLD repo**: `~/Projects/mega65/mega65-keyboard-cpld` branch `type3`
(local only, not pushed): 37080f6, d45d0ab. Only `src/top.vhd` changes.
Not built: Diamond is not installed.

**Needs the owner**

1. Diamond build of branch `type3` (`./build.sh` as before; it runs
   `version.sh`, synthesis, map, PAR, bitgen, jedecgen): check the fit and
   timing reports (24.18 MHz clock; the MK-I logic is a 2-cycle path through
   the clock enable, but Diamond will time it as 1 cycle, 41 ns, which should
   still be easy). Report LUT/FF use back.
2. Confirm on the MK-I keyboard schematic that J5 pin 3 is the CPLD's
   JTAGENB, and check the strategy setting `PROP_BIT_JTAGEnableBitGen =
   False` (the `JTAG_PORT` sysCONFIG option should stay ENABLE, the
   default, so JTAG is always available).
3. Hardware: load a bitstream from this branch, then with the keyboard on
   the physical port: `dutctl listen` shows `kbd MK-I` (old firmware); `dutctl
   jtag-idcode IP --kbd` should print `IDCODE 0x012ba043`.

**Flashing the keyboard over the remote JTAG** (once Diamond made
`impl1/megakey_impl1.jed`):

```
dutctl jtag-idcode <board-ip> --kbd        # expect IDCODE 0x012ba043
dutctl set <board-ip> kbd-jtag 1           # keep JTAG on while the CPLD
                                           # stops answering during flashing
dutctl xvc <board-ip> --kbd --port 2542 &  # XVC server -> keyboard CPLD
openFPGALoader -c xvc-client --ip 127.0.0.1 --port 2542 --freq 1000000 \
    -f impl1/megakey_impl1.jed             # erase, program, verify, refresh
kill %1
dutctl set <board-ip> kbd-jtag 0           # back to auto
dutctl listen                              # expect kbd type3 within ~2 s
```

(`<board-ip>` = either endpoint of the master board. Keep only one JTAG
client at a time: each `dutctl` session resets the keyboard engine's
sequence. If openFPGALoader's MachXO2 flash support misbehaves over XVC,
Diamond Deployment Tool can export an SVF for `openFPGALoader ... file.svf`
instead; not tried.)

**Not done / not verified**: nothing on hardware; no Diamond build; the
3 m cable (series resistors, slew, supply drop) is still to be tried; the
"changed words first" schedule was not needed.

## 2026-11-27 Vivado build of the final HDL (053367dc)

TIMING MET: WNS +0.079 ns, WHS +0.014 ns (worst path DHCP client ->
net_tx payload register, not the keyboard logic); 18373 LUTs (56.4 %),
21554 FFs (33.1 %). Bitstream `build/bits/supervisor-053367dc.bit` in the
agent worktree; not loaded on hardware. The HDL is unchanged after
053367d (later commits are testbench/docs only).

## 2026-11-27 merged with feature/foundation (shield pin plan, 0049)

* Keyboard CPLD JTAG pins are now per build: `boards/mimas_a7/pk_jtag_bodge.xdc`
  (normal build: JTAGEN L21, TMS M21, TCK L20, TDI L19, TDO K19), read by
  `vivado/build.tcl` only when SHIELD_RX = 0; `shield_v1.xdc` has the shield
  pins (PK_TCK H19, PK_TMS M20, PK_TDI H18, PK_TDO K19; HDMI3 takes
  L19/L20/M21/L21). In the shield build `pk_jtagen` is a null port (PK_JTAGEN
  is on I2C expander B, TCA6416A @0x20 P0.3); `pk_jtagen_want` in
  `mimas_a7_top` is the hook for the shield I2C master (issue 0049 step 2).
* The merged normal build missed timing by 3 ps (net_rx d -> last_cmd RAM ->
  MGMT duplicate compare -> cfg_r). Fix: the compare is registered
  (`mgmt_dup`), S_MGMT takes one more cycle.
* Normal build e131ab30: TIMING MET, WNS +0.161 ns, WHS +0.012 ns; 18608
  LUTs (57.1 %), 21569 FFs (33.1 %). `make test`: 31 HDL testbenches, 228 C
  and 52 relay checks pass.
* Shield build e131ab30 (`VIVADO_GENERICS="SHIELD_RX=3"`): TIMING MET, WNS +0.175 ns, WHS +0.050 ns, 0 critical warnings (only "null port pk_jtagen ignored", as intended).

## 2026-11-27 lead: owner reminders

* **Owner to install Lattice Diamond** (remind the owner), then run
  `./build.sh` on branch `type3` in ~/Projects/mega65/mega65-keyboard-cpld
  and report the fit and timing.
* The J5 pin 3 = JTAGENB check will be done by the lead on the attached
  keyboard over remote JTAG (owner asked).

## 2026-11-27 pin-3 diagnostic (lead request)

MGMT key 0x0061 value 3 (`dutctl set IP kbd-jtag 3`): keyboard JTAG engine
on, KB_JTAGEN driven **low**, TCK/TMS/TDI as normal. Check: `kbd-jtag 1` +
`dutctl jtag-idcode IP --kbd`, then `kbd-jtag 3` + the same. Fails in mode 3
= pin 3 is JTAGENB with `JTAG_PORT = DISABLE`; works = the JTAG port is
always enabled (flashing works either way in modes 0/1). Covered by
tb_supervisor_core (IDCODE in mode 3, JTAGEN seen low). Boundary-scan
dump (`jtag-sample`) skipped: no LCMXO2-1200HC TQFP100 BSDL found without a
Lattice login. Merged foundation b9b5e99. Normal build 8fc1e250: TIMING
MET, WNS +0.179 ns, WHS +0.008 ns, 18461 LUTs, 21572 FFs; `make test`
green (31 HDL, 228 C, 52 relay checks).

Update: merged foundation f75b3e4 (net_tx/DHCP timing). Normal build c73c7b23: TIMING MET, WNS +0.200 ns, WHS +0.011 ns, 18510 LUTs, 21970 FFs; `make test` green. Bitstream for the pin-3 check: `build/bits/supervisor-c73c7b23.bit` (agent worktree).

## 2026-11-27 hardware (lead): J5 pin 3 / JTAGEN test

Build c73c7b23 on the board, the owner's MK-I keyboard on the physical
keyboard strip. `dutctl set IP kbd-jtag N` then `dutctl jtag-idcode IP
--kbd`: mode 1 (JTAGEN high) -> 0x012ba043; **mode 3 (JTAGEN driven low)
-> 0x012ba043**; mode 1 and mode 0 (auto) again -> 0x012ba043. So the CPLD's
JTAG port is enabled regardless of J5 pin 3: the configured CPLD has
JTAG_PORT=ENABLE (the default), and pin 3 doesn't gate JTAG, whether or not
it goes to JTAGENB. Flashing over remote JTAG doesn't depend on pin 3. The
type-3 firmware keeps the same setting (strategy unchanged). hwtest 63/0
on this build; c73c7b23 known-good.
