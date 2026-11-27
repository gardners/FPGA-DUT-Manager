# Things the lead needs from the owner

Kept by the lead session; deal with them as you have time. Newest at the top
of each section. Tick or delete an item when it is done (or tell the lead).

## Blocking design work

| Since | Item | Blocks | Issue |
|---|---|---|---|
| 2026-11-27 | **MEGA65 PCB and case drawings** (or photos with a ruler): board outline, mounting bosses, floppy drive bosses, official expansion bosses, tall-part heights near the edges | shelf deck holes; whether board + floppy fit side by side in ~375 mm | 0051 |
| 2026-11-27 | **Logo SVGs**: MEGA65 and M.E.G.A. e.V. (official vector artwork) | etch layers on the KVM front panel and fan plates | 0051 |
| 2026-11-27 | **Measure the bought 16x2 LCD module**: bezel size and height, viewing-area position, mounting holes | front-panel window and panel cut-out | 0050 |
| 2026-11-27 | **Run the autorouter**: `scripts/route-front-panel.sh path/to/freerouting.jar`, then commit `hardware/mega-kvm-front/tracks.json` (or tell the lead to) | front-panel PCB ready for fab | 0050 |
| 2026-11-27 | **Install Lattice Diamond**, then in `~/Projects/mega65/mega65-keyboard-cpld` on branch `type3` run `./build.sh` and report fit/timing | keyboard type 3 firmware; then flash via remote JTAG and test (short cable, then 3 m) | 0046 |

## Decisions with a default (veto if you disagree)

| Since | Default taken | Issue |
|---|---|---|
| 2026-11-27 | Keep the LTC4417 + FET input selector rather than relays (relays lose more power at every realistic load, arc at 20 A DC, and drop all boards on changeover) | 0047 |
| 2026-11-27 | Fan protection: pad-free eFuse per header if cheap and JLC-stocked, otherwise a 0.5 A PTC | 0052 |
| 2026-11-27 | The keyboard CPLD `type3` branch stays local (not pushed) until you say where it should go | 0046 |

## Bench / hardware checks only the owner can do

| Since | Item | Issue |
|---|---|---|
| 2026-11-27 | Cable tests to a real DUT: VIO sense, JTAG IDCODE/XVC with Vivado, UART, DUT keyboard emulation, m65 (mimas-a7-jtag branch) | 0045, 0011 |
| 2026-11-27 | A real MEGA65 as HDMI-with-audio source: passthrough, EDID, screenshot | 0037, 0042 |
| 2026-11-27 | Measure a MEGA65's 12 V current (idle and busy, with floppy) | 0047 sizing |
| 2026-11-27 | Before PCB fab: measure a real Mimas A7 (outline, holes, connector positions); confirm the LTC4417 GN pinout (the full datasheet could not be downloaded here) | 0045, 0047 |
