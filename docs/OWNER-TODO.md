# Things the lead needs from the owner

Kept by the lead session; deal with them as you have time. Newest at the top
of each section. Tick or delete an item when it is done (or tell the lead).

## Blocking design work

| Since | Item | Blocks | Issue |
|---|---|---|---|
| 2026-11-27 | **MEGA65 details the drawings don't give**: floppy mounting-hole offset from the bezel and spacer height; official expansion mounting holes; Cart64out stand-off height to line up with the cart port. (Tallest part: the IEC socket, owner round 13) | shelf deck holes and heights | 0051 |
| 2026-11-27 | **Rails and rack** (measure later; standard slide thickness assumed meanwhile): width each slide takes per side; inner-member length; rack depth between posts | shelf width, batten length | 0051 |
| 2026-11-27 | **Real parts for cut-outs**: rocker switch, banana sockets, RJ45 coupler; your laser's kerf in 6 mm ply | panel holes | 0051 |
| 2026-11-27 | **Review the routed front panel**: routed and DRC clean (`make pcb-routing`; renders in `hardware/mega-kvm-front/out/`) | front-panel PCB ready for fab | 0050 |
| 2026-11-27 | **Lattice Diamond** is installed (/opt/lattice/diamond/3.14); waiting on the free academic licence key. Then in `~/Projects/mega65/mega65-keyboard-cpld` on branch `type3` run `./build.sh` and report fit/timing | keyboard type 3 firmware; then flash via remote JTAG and test (short cable, then 3 m) | 0046 |

## Decisions with a default (veto if you disagree)

| Since | Default taken | Issue |
|---|---|---|
| 2026-11-27 | **6 V outlet (K325T, 0055)**: VBUS -> eFuse -> TPS565201 buck (5 A, TSOT-23-6, 17 V part, protected by the eFuse/OVLO in front of it) -> 6.0 V -> eFuse (4.66 A limit, 6.9 V OVLO) -> **Molex Micro-Fit 3.0 2x2** (43045-0400; pins 1-2 GND, 3-4 +6 V) "DUT 6V ONLY (K325T)". Off until the host sets TCA9535 U11 P1.5 (now fitted by default); fault on P1.6, power-good on P1.7. About 5.85 V at the plug at 4 A: say if you want the buck at 6.1 V instead. 9th rear lead hole added. Lead: 20 AWG on the standard crimps (2 A per contact, two contacts per pole) - say the plug size and length you want | 0055 |
| 2026-11-27 | **5 V outputs (0055)**: Molex pin 4 -> 10 A fuse -> 3 x TPS259470L eFuses (3 A each, off above 5.9 V) -> JST VH 2-pin "5V ONLY" (J61-J63). Per channel 5-7 a 3-pin jumper JP5-7 picks 12 V (1-2) or 5 V (2-3); no shunt = both off. Defaults: fit the three shunts on 1-2 at assembly; **fit the TCA9535 (U11)**, now the only way the host sees 5 V present, which output is selected and the fault lines; 8 rear lead holes stay (one lead per channel; say if both 12 V and 5 V leads of a channel should stay plugged in, then 3 more). Expect 0.2-0.4 V drop at 3 A per output (PSU 5 V lead, fuse, eFuse): say if the 5 V boards are fussy | 0055 |
| 2026-11-27 | **Current sensing on the 8 DUT rails** (study only, not on the board): the TPS259470 ILM pin is already a current monitor (0.121 V/A). Proposed: 2 x ADS1115 (MSOP-10, about $2.5 per board), about ±6 % at load, ±10-15 % at 0.3 A before a one-point calibration. Say yes to add it | 0047/0052 |
| 2026-11-27 | LCD = **Jaycar QP5521** 16x2 + **XC3706** I2C backpack (0x27; header GND VCC SDA SCL matches J2). Module outline/holes/bezel are typical 1602A values: measure when it arrives. MEGA65 IEC socket assumed 21.1 mm tall (SDS-60J class): 9.5 mm under the next deck; MEGA65 sits wholly between the battens. Rails assumed 12.7 mm per side (deck 424.6 mm). Set-back shelves 92 mm. The KVM deck keeps a front notch for its 120 mm fans | 0050/0051 |
| 2026-11-27 | KVM front panel with 2 x 120 mm fans: master rocker at the far left, then the two fans; the right-hand column holds the 140 x 66 mm display board, the MEGA-KVM etch, the MEGA65 logo and the M.E.G.A. e.V. logo (logos about 21 mm tall). The fans reach about 21 mm below the deck top through a notch in the deck front | 0050/0051 |
| 2026-11-27 | Keep the LTC4417 + FET input selector rather than relays (relays lose more power at every realistic load, arc at 20 A DC, and drop all boards on changeover) | 0047 |
| 2026-11-27 | Fan protection: **Infineon BSP452** (SOT-223, current-limited high-side switch, ~$1.26 each, ~$10 more per board than PTCs). A shorted fan lead is cut in microseconds instead of dragging the always-on group (and both Mimas) into its 5 A limit. PTC footprints stay available as the fallback | 0052 |
| 2026-11-27 | Fan control: 4 x EMC2302 (MSOP-10, 2 fans each) behind a TCA9548A I2C switch, one 26 kHz PWM + tach per fan; fans run at 100 % until the host sets them; 2 x TMP75 (main board, input-board FETs) | 0052 |
| 2026-11-27 | One power board (230 x 138.5 mm) with the inputs on its front edge, plugged from the open top; one TMP75 at 0x48. 25 A input fuse with the 24 A PCB-mount banana sockets (owner round 13: fine) | 0047 |
| 2026-11-27 | The keyboard CPLD `type3` branch stays local (not pushed) until you say where it should go | 0046 |

## Bench / hardware checks only the owner can do

| Since | Item | Issue |
|---|---|---|
| 2026-11-27 | **K325T board on a bench supply at ~4.5 V** (worst case through the Molex 5 V path at 3 A): does it just draw more current, or misbehave (watch the gigabit link-up, SD card and GPIO load, not only idle)? Also its real current. If it misbehaves, the 5 V outputs become 12 V -> 6 V bucks | 0055 |
| 2026-11-27 | Measure a real Mimas: **PCB thickness** (vendor STEP 1.16 mm, we assumed 1.6: set `MIMAS_PCB` in `hardware/mega-kvm-shield/scripts/geometry.py`); RJ45 depth/height (STEP 21.8 / 14.1 mm; the shield cut-out now clears it); whether the HDMI sockets are flush (STEP) or 1.5 mm proud, and that the plugs mate fully through the rear panel; hole positions with calipers | 0045 |
| 2026-11-27 | Before fab: JLC shows **0 in stock** for LTC4417CGN (C688500) today; re-check or pre-order. (The eFuses are now the stocked auto-retry TPS259470A.) The new LTC4417 soft-start (RS 1 k / CS 22 nF) values need a bench check | 0047 |
| 2026-11-27 | When the power board exists: measure the always-on group's **inrush at master-on** (8 fans at 100 % + 2 Mimas + GS105). If it trips the 5 A limit, raise it via R182 (to 5.5 A) or feed the fan switches from VBUS | 0052 |
| 2026-11-27 | Before fab: check the 0.28 mm MSOP-10 land pattern against Microchip's drawing; EMC2302-1 stock is modest (217) and TCA9548APWR stock unconfirmed | 0052 |
| 2026-11-27 | Plug a **USB JTAG adaptor** (TE0790 or FT2232H) onto a powered DUT to test `dutctl jtag-discover --scan` and the openFPGALoader commands; `--power-cycle --yes` needs your go-ahead at run time | 0053 |
| 2026-11-27 | `dutctl jtag-speed IP 1` on the DUT path (DUT1 IDCODE read OK on 2026-11-27 with an XC7A200T board; the speed sweep not run yet) | 0054 |
| 2026-11-27 | Cable tests to a real DUT: VIO sense, JTAG IDCODE/XVC with Vivado, UART, DUT keyboard emulation, m65 (mimas-a7-jtag branch) | 0045, 0011 |
| 2026-11-27 | A real MEGA65 as HDMI-with-audio source: passthrough, EDID, screenshot | 0037, 0042 |
| 2026-11-27 | Measure a MEGA65's 12 V current (idle and busy, with floppy) | 0047 sizing |

## Resolved

* 2026-11-27 (round 13) M.E.G.A. e.V. logo from m-e-g-a.org; tallest MEGA65 part = IEC socket; fan-plate clearance by setting shelves back on the rails (no cut-outs); LCD = a cheap Jaycar 16x2 module; LTC4417 datasheet supplied (docs/datasheets/, git-ignored).

* 2026-11-27 KVM front fans: owner wants standard 2 x 120 mm PC fans. The
  display board is being re-laid out in two rows (at most ~172 mm wide) so
  they fit (0050, 0051).
* 2026-11-27 Keyboard JTAG error floor: cross-talk from the keyboard scan; pausing the scan during keyboard JTAG (now the default) gives 0 errors up to 20.8 MHz. No scope needed (0054).
