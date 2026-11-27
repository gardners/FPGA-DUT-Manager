# Things the lead needs from the owner

Kept by the lead session; deal with them as you have time. Newest at the top
of each section. Tick or delete an item when it is done (or tell the lead).

## Blocking design work

| Since | Item | Blocks | Issue |
|---|---|---|---|
| 2026-11-27 | **KVM front fans**: 2 x 120 mm do not fit beside the 227 mm display board and the 197 mm input board on a 425 mm deck. Default now **2 x 92 mm**; alternatives 1 x 120 mm, or narrower boards | KVM front panel cut-outs, fan count | 0051 |
| 2026-11-27 | **M.E.G.A. e.V. logo SVG** -> `hardware/mega-kvm-case/logos/mega-ev.svg` (the MEGA65 logo from `assets/mega65.svg` is used already) | fan plate / KVM front etch | 0051 |
| 2026-11-27 | **MEGA65 details the drawings don't give**: tallest part above the PCB; floppy mounting-hole offset from the bezel and spacer height; official expansion mounting holes; Cart64out stand-off height to line up with the cart port. (Board outline + 6 holes taken from `pcbs/mega65r6/DIM-TE0765-06.PDF`, cross-checked with mega65-rugged-case) | shelf deck holes and heights | 0051 |
| 2026-11-27 | **Rails and rack**: width each slide takes per side (sets the deck width, now 425 mm); inner-member length; rack depth between posts | shelf width, batten length | 0051 |
| 2026-11-27 | **Real parts for cut-outs**: rocker switch, banana sockets, RJ45 coupler; your laser's kerf in 6 mm ply | panel holes | 0051 |
| 2026-11-27 | **Fan-plate clearance style**: notch mode (the other three shelves' battens cut 92 mm short at the front) or set-back mode (those shelves set back 92 mm on their rails) | shelf deck | 0051 |
| 2026-11-27 | **Measure the bought 16x2 LCD module**: bezel size and height, viewing-area position, mounting holes | front-panel window and panel cut-out | 0050 |
| 2026-11-27 | **Review the routed front panel** (`make pcb-routing` now downloads Freerouting and routes; result in `hardware/mega-kvm-front/out/`) | front-panel PCB ready for fab | 0050 |
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
| 2026-11-27 | Plug a **USB JTAG adaptor** (TE0790 or FT2232H) onto a powered DUT to test `dutctl jtag-discover --scan` and the openFPGALoader commands; `--power-cycle --yes` needs your go-ahead at run time | 0053 |
| 2026-11-27 | A **DUT on an octopus port** for `dutctl jtag-speed` on the DUT path | 0054 |
| 2026-11-27 | **Keyboard JTAG error floor**: `jtag-speed --kbd` sees isolated 1s read as 0 at about 6e-5 at every TCK (worse at 7.8 MHz; clean at 20.8 MHz). Looks like signal integrity, not timing. A scope on TDI/TDO of the keyboard cable (at half period 8) would tell; matters for CPLD flashing | 0046, 0054 |
| 2026-11-27 | Cable tests to a real DUT: VIO sense, JTAG IDCODE/XVC with Vivado, UART, DUT keyboard emulation, m65 (mimas-a7-jtag branch) | 0045, 0011 |
| 2026-11-27 | A real MEGA65 as HDMI-with-audio source: passthrough, EDID, screenshot | 0037, 0042 |
| 2026-11-27 | Measure a MEGA65's 12 V current (idle and busy, with floppy) | 0047 sizing |
| 2026-11-27 | Before PCB fab: measure a real Mimas A7 (outline, holes, connector positions); confirm the LTC4417 GN pinout (the full datasheet could not be downloaded here) | 0045, 0047 |
