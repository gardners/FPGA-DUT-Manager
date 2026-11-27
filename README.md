# FPGA-DUT-Manager

Networked supervisors for a remote hardware test farm of **MEGA65** (and later
HewnWeb) boards. Each supervisor is a pre-V4 Numato **Mimas A7** (Artix-7
XC7A50T) that sits between a Linux host on the lab network and two
devices under test (DUTs), and gives the host everything a developer at the
bench would have: JTAG, serial console, keyboard, video, status and power.

The aim is remote, independent control of real hardware for development,
interactive use and automated regression testing, with as little FPGA
logic, extra hardware and cabling as possible. Policy lives in host
software; the FPGA stays a lean UDP frame processor (no soft CPU, no DDR3,
no retransmission logic).

## What it is meant to do

Per DUT, over gigabit Ethernet with its own MAC/IP (DHCP):

* **JTAG**: program and debug the DUT from Vivado or `m65` via a Xilinx
  Virtual Cable (XVC) endpoint, proxied by `dutctl` onto a JTAG-over-UDP
  engine in the FPGA.
* **UART**: the DUT's serial console as UDP streams, with history snapshots
  so nothing is lost when the host reconnects.
* **Keyboard**: the supervisor presents a MEGA65 MK-I keyboard to each DUT;
  the host sets the full key matrix (including holding keys through a cold
  power-on). A real MK-I or MK-II keyboard on the master supervisor can take
  over the selected DUT.
* **Video**: raw RGB888 capture of the DUT's HDMI output (27 MHz modes) sent
  as line packets, reassembled on the host; audio later.
* **Status and power**: heartbeats with complete state snapshots (target
  power sensing, keyboard ownership, UART/JTAG counters, LEDs); per-DUT 12 V
  power through an Arduino-driven relay board.
* **Local console**: an HDMI monitor on the supervisor shows an 80x25 text
  screen pushed by the host, or the selected DUT's video; front-panel
  buttons, seven-segment display and LEDs show identity and state.
* **Scaling**: two supervisors / four DUTs now, up to four / eight, linked
  by simple ribbon cables for shared monitor, keyboard and selection; every
  supervisor also talks to the host directly, so a chain fault never takes
  away remote JTAG or UART.

The full requirements are in [`docs/design-brief-v0.5.md`](docs/design-brief-v0.5.md);
decisions are in [`docs/adrs/`](docs/adrs/0000-index.md), open work in
[`docs/issues/`](docs/issues/).

## Progress (2026-11-25)

**Working on hardware** (Vivado bitstreams; known-good images in `bits/`,
`scripts/hwtest.sh` smoke test 63/0):

* Gigabit Ethernet with a self-calibrating RGMII RX phase, ARP, ICMP,
  per-DUT DHCP; DUT IDs `0x0n` / `0x1m` from the DIP switches; device DNA.
* Heartbeats with link, video and DDR3 blocks; every management key
  (accepts valid, rejects invalid values with the right status).
* HDMI console at 720x480p60 with three screens (editable / no video /
  select), written over UDP (`dutctl text --screen`). HDMI OUT sends HDMI
  with AVI and SPD InfoFrames ("MEGA65 / MEGA KVM Mnn").
* **HDMI IN**: 27 MHz input (Digilent dvi2rgb, made HDMI-aware so guard
  bands and data islands such as audio never reach the picture), our own
  EDID, live passthrough to HDMI OUT, and raster capture: `dutctl video`
  reassembles complete, pixel-exact frames (verified on an HDMI loopback,
  jumbo frames). `dutctl -S` saves a PNG screenshot (issue 0042), checked
  with a real source (a HewnWeb board) on HDMI IN.
* **DDR3** (256 MiB, Xilinx MIG): calibrates and passes its start-up
  self-test. It is used only as a thumbnail store; nothing else depends on
  it.
* **Live thumbnails**: every video source keeps a 320x200 (or 160x100)
  copy in DDR3. Boards exchange them as raw Ethernet frames on request
  (RAW888/RLE24), and the KVM select screen shows them as a 2x2 or 4x3
  mosaic with the selection digit in each corner. A machine with no
  video shows colour bars, an empty slot a frown.
* Physical MK-I keyboard: KVM hotkey (both SHIFTs 1 s + MEGA, or a quick
  LSHIFT/MEGA train, then 1-9, 0) and power-LED status colours.
* Seven-segment status; SPI flash programming (`make flash`).
* **Relay controller** (Arduino Uno, `make relay-flash`): `dutctl relay
  /dev/ttyACM0 POWER 0 1 ON`, `STATUS`, `CYCLE`, `ALL OFF`; relays switch
  on the bench (ADR 0009).

**Implemented, waiting for hardware to test:** JTAG/XVC and UART to a
powered MEGA65, MK-I keyboard emulation towards DUTs, MK-II keyboard host,
passthrough and EDID with a real HDMI source, the thumbnail relay between
two boards, the monitor showing the SPD name.

**Not started:** supervisor chain link (0011), audio, status screen (0017),
reading the monitor's EDID (0037 part 2), GenLock (0039, future), DUT
adapter board (0008), 100 Mb/s Ethernet (0018, low priority).

## Quick start

```
make deps                 # list/install Debian/Ubuntu packages
make test                 # HDL (nvc), dutctl and relay firmware unit tests
make bitstream            # Vivado build -> build/vivado/supervisor.bit
make jtagload             # load it (or: make jtagload-good for bits/known-good.bit)
make dutctl
sw/dutctl/build/dutctl listen -t 5
sw/dutctl/build/dutctl text <ip> "Hello"
sw/dutctl/build/dutctl -S 2              # screenshot of machine 1 (console digit 2)
make relay-flash PORT=/dev/ttyACM0   # relay controller (arduino-cli)
```

### `dutctl` commands

Run `dutctl` without arguments for the list, or a command without arguments
for its options.

| Command | What |
|---|---|
| `listen [-t S] [--kv]` | decode heartbeats |
| `set IP NAME VALUE`, `mgmt IP KEY [HEX]` | management keys (named / raw) |
| `kbd IP [KEY ...]` | hold MEGA65 keys on a DUT |
| `uart IP` | interactive UART bridge |
| `jtag-idcode IP [DUT]\|NAME`, `xvc IP [DUT]\|NAME` | JTAG over UDP, XVC server for Vivado / openFPGALoader; a configured USB-JTAG DUT prints (or `--exec`s) the openFPGALoader command. Shifts are split into requests that fit one unfragmented packet: global `--mtu N` / `$DUTCTL_MTU` (default 1500 = 5792 bits per request; >= 2028 = 7904, the supervisor maximum; issue 0059) |
| `jtag-speed IP [DUT]\|NAME [--kbd] [--save]` | maximum safe octopus TCK (issue 0054) |
| `duts`, `jtag-discover` | per-DUT configuration, USB JTAG adaptor discovery (issue 0053) |
| `relay TTY COMMAND...` | Arduino relay controller (DUT power) |
| `text IP ...` | write the HDMI console text screens |
| `video IP [--enable]` | raw raster capture to PPM frames |
| `thumbs IFACE` | thumbnail relay pictures (raw Ethernet) |
| `screenshot [TARGET] [-o FILE]` (alias `-S`) | one complete frame as PNG/PPM |

**Screenshots** (issue 0042):
`dutctl screenshot [TARGET] [-o FILE.png|.ppm] [--screen auto|editable|novideo|select] [--timeout S]`,
or `dutctl -S ...` as in m65. TARGET is an endpoint IP or a console digit
(1-9, 0 = machine 0-9, as on the select screen); without one, the only
machine that can be captured right now is used (if several can, they are
listed). Only a board's video target DUT can be captured; the video target
is not changed. The command points that DUT's telemetry at this host
(unicast, found from the route to the board), enables capture, waits for
one complete frame (10 s default), then restores capture enable to its
previous state, the telemetry destination to broadcast (the default; the
protocol cannot read the old value) and, if `--screen` forced one, the auto
console screen, also on errors and Ctrl-C. The default file is
`mega65-screenshot-NNNNNN.png`, the lowest free number in the current
directory (never overwritten). PNGs are uncompressed (stored deflate), about
1 MB at 720x480.

**Per-DUT JTAG setup** (issue 0053): `~/.config/dutctl/duts.conf` (or
`$DUTCTL_CONF`, or the global `--conf FILE`) has one `[name]` section per
DUT; `dutctl duts --help` lists the keys:

```ini
[m65-r6]
ip = 192.168.1.50        # supervisor endpoint (octopus JTAG)
dut = 0                  # endpoint index (optional)
jtag = octopus           # or usb
tck_half = 12            # from dutctl jtag-speed --save
kbd_tck_half = 20        # keyboard CPLD, jtag-speed --kbd --save
relay = /dev/ttyACM0 3   # power path (relay controller tty, channel)

[nexys]
jtag = usb
usb_vid = 0403
usb_pid = 6010
usb_serial = 251633000123
ftdi_channel = 0
tty = /dev/ttyUSB5       # the adaptor's UART to the DUT (TE0790)
```

The JTAG commands take a DUT name instead of `IP [DUT]`. For `jtag = octopus`
they use the configured `tck_half` (`xvc`: as the fastest TCK that XVC
`settck` may select); for `jtag = usb` they print the openFPGALoader line
(`--detect` / `--xvc --port N`, chosen by `--ftdi-serial`) plus m65's
`-f SERIAL -l TTY`, or run it with `--exec`. `dutctl duts` lists the DUTs.
The writer edits the file in place, so comments survive.

`dutctl jtag-discover` lists USB JTAG adaptors from sysfs (FTDI
0403:6010/6011/6014/6001, TE0790, Digilent; the Mimas boards 2a19:1009 are
excluded) with their serials and ttys. `--scan` reads each chain with
openFPGALoader `--detect` (FTDI channel 0 by default; libftdi detaches that
channel's ttyUSB; FT232R only with `--all`; adaptors carrying a configured
relay tty are never touched). `--power-cycle --yes` switches each DUT with a
`relay =` power path off, waits (`--wait S`, default 3), rescans, sees whose
chain disappeared, switches the DUT back on, proposes the mapping and
writes it after confirmation (or with `--write`). Without openFPGALoader
there is no chain scan: map by hand or unplug adaptors one at a time.
Adaptors without a USB serial are recorded by port (`usb_path`) and
addressed by bus/device number; replugging can renumber them.

**JTAG speed probe** (issue 0054): `dutctl jtag-speed IP|NAME [--kbd]
[--reps N] [--save]` sweeps the TCK half period from 50 (1.25 MHz) down to
2 (31.25 MHz). Each of the N probes per step (default 200) is one shift:
Test-Logic-Reset and the IDCODE window (compared with the slow reading),
then all IRs to BYPASS and a 2048-bit random, 512 all-0 and 512 all-1 DR
pattern checked after the chain's length. Only IDCODE and BYPASS are used,
so it is safe on a running DUT. The fastest step reached without a failure
is f_max; the recommendation is f_max / 2 (the next swept step at least
twice as slow), which `--save` writes as `tck_half` (`kbd_tck_half` with
`--kbd`). `-v` shows the wrong bits; `--tolerate N` lets a step pass with N
failing probes (for a link with a speed-independent error floor);
`--from` / `--to` limit the sweep.

Hardware notes: power the Mimas from its DC jack (USB power alone is not
enough for the full design); install the udev rule with
`scripts/setup-mimas-udev-rule.sh` (stable `/dev/mimas-<serial>`, and keeps
ModemManager off the JTAG channel); follow the warnings in
`docs/cabling/dut-cable.md` (JTAG and keyboard strips run in opposite
directions next to the 3.3 V rows 9/15/21); never run a full-width cable on the
headers (rows 1-2 carry raw VIN, P13 rows 34-39 are FPGA configuration
pins). An open-source flow (`FLOW=openxc7`: GHDL/yosys/nextpnr-xilinx) is
kept available but Vivado is the default.

## Repository layout

| Path | What |
|---|---|
| `hdl/src/` | VHDL-2008 supervisor (vendor-neutral except `platform/xc7/`) |
| `hdl/tb/`, `tests/scenarios/` | nvc testbenches and Python scenario checks |
| `boards/mimas_a7/` | pin and timing constraints |
| `sw/dutctl/` | Linux CLI in C: protocol codec, UART merge, XVC proxy, relay client |
| `firmware/relay-controller/` | Arduino Uno sketch for the 8-channel relay board (`make relay-fw`, `make relay-flash`) |
| `tests/netproto.py` | reference encoder/decoder for the wire protocol |
| `vivado/`, `scripts/` | Vivado build script, toolchain and board helper scripts |
| `docs/` | design brief, ADRs, issues |
| `bits/` | index of hardware-verified bitstreams |

## Licence

LGPL-2.1-or-later (see file headers). Imported code under `third_party/`
keeps its own licence and provenance.
