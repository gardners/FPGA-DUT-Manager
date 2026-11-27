# QMTECH XC7K325T bring-up (DUT1)

Issue 0057; pin map and sources in `docs/hardware/qmtech-k325t.md`.

| File | What |
|---|---|
| `hdl/k325t_bringup.vhd` | bring-up design (7-seg counter, LEDs, J11 UART, VGA) |
| `hdl/tb_k325t_bringup.vhd` | nvc testbench (UART text, echo, digit one-hot) |
| `k325t_bringup.xdc` | pins (all header pins LVCMOS33, unused pins no pull) |
| `build.tcl` | non-project Vivado build for xc7k325tffg676-1 |
| `xvc-split.py` | optional XVC proxy that splits shifts to <= 7904 bits; only needed with a dutctl older than issue 0059 (`SPLIT=1 ./k325t.sh load`) |
| `hdl/k325t_sdprobe.vhd` | microSD probe: J11 pin test, SD SPI init on all 24 J11 pin assignments and on the DB slot J9, CID/CSD decode |
| `hdl/tb_k325t_sdprobe.vhd` | nvc testbench with an SPI-mode SD card model |
| `k325t_sdprobe.xdc`, `build_sdprobe.tcl` | probe pins; `-tclargs OUTDIR up\|down\|none` = the weak pull on J11 (`k325t_sdprobe_<pull>.bit`) |
| `k325t.sh` | `on` / `load [BIT]` / `stat` / `off` (SRAM only, parks the TAP before power-off) |

```sh
# build (about 3 minutes; the K325T needs the licensed Vivado, present on the build box)
mkdir -p build && (cd build && source /opt/Xilinx/Vivado/2023.2/settings64.sh &&
  vivado -mode batch -nojournal -log vivado.log -source ../build.tcl -tclargs $PWD)
# simulate
nvc --std=2008 -a hdl/k325t_bringup.vhd hdl/tb_k325t_bringup.vhd -e tb_k325t_bringup -r
# run
./k325t.sh on && ./k325t.sh load     # ~1.5 s at 10.4 MHz TCK
./k325t.sh off                       # TMS/TDI parked low, then relay 5 off
```

`dutctl xvc` splits every XVC shift into JTAG_REQs that fit one unfragmented
packet (MTU 1500: 5792 bits; `DUTCTL_MTU=9000` for a jumbo path: 7904, the
supervisor maximum), issue 0059. `SPLIT=1` puts `xvc-split.py` in front as a
fallback.

What the design shows:

* 7-segment: seconds since configuration as `SS.S` (00.0-99.9, wraps);
  daughter-board SW1 held = pause, SW2 = clear.
* Daughter-board LEDs D1-D5: uptime seconds in binary, D5 = bit 0.
* Core LED2 blinks at 1 Hz; core LED3 toggles on every byte received on J11-10.
* UART on J11 pin 4 (TX) / pin 10 (RX), 2 Mbaud 8N1: a banner after
  configuration, then `K325T SS.S up 0xNNNN` once a second; received bytes
  are echoed.
* VGA 640x480 at 59.5 Hz: white, yellow, cyan, green, magenta, red, blue,
  black bars, a 32-step grey ramp in the bottom 80 lines, and a 48x48 square
  in inverted colours bouncing across the bars.

## microSD probe

```sh
mkdir -p build && (cd build && source /opt/Xilinx/Vivado/2023.2/settings64.sh &&
  vivado -mode batch -nojournal -log vivado.log -source ../build_sdprobe.tcl -tclargs $PWD up)
nvc --std=2008 -a hdl/k325t_sdprobe.vhd hdl/tb_k325t_sdprobe.vhd -e tb_k325t_sdprobe -r
./k325t.sh load build/k325t_sdprobe_up.bit
(sleep 1; printf a; sleep 8) | dutctl uart 203.28.176.87    # p / j / d / a
```

After configuration the probe runs the pin test. It then runs the J11 and
J9 SD probes, unless a J11 pin looks tied to a rail (then send `j` to
force them). DB SW1 = run everything again. 7-segment display: alternates
the J11 result (`P16` = card at assignment 16, `noC` = no answer) with the
J9 result (`d.C1` = card, `d.C0` = none). LEDs D1-D5 show the J11
assignment in binary. Core LED3 is lit while J9's card-detect reads low.
Results so far: docs/hardware/qmtech-k325t.md, "microSD".
