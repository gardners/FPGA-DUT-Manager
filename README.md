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

**Working on hardware** (Vivado bitstream, JTAG-loaded into SRAM):

* Gigabit Ethernet (RTL8211E, RGMII), ARP, ICMP echo, per-DUT DHCP clients
  with deterministic MACs; DUT IDs from the DIP switches (`0x0n` / `0x1m`).
* Heartbeats and management writes (`dutctl listen`, `dutctl set`).
* HDMI 80x25 text console at 720x480p60, written over UDP (`dutctl text`).
* Seven-segment status (`dHCP` while waiting for leases, then the DUT IDs).
* Command-line Vivado build in a few minutes (`make bitstream`), JTAG load
  (`make jtagload`), hardware-verified images kept in `bits/`.

**Implemented and passing simulation, not yet tried on hardware:**

* UART bridge with snapshots; JTAG engine plus `dutctl xvc` proxy.
* MK-I keyboard emulation towards DUTs (checked against mega65-core's own
  host decoder); physical keyboard host for MK-I and MK-II with
  auto-detection; keyboard ownership arbiter.
* Relay controller firmware (Arduino) and its `dutctl relay` client.
* `dutctl` raster/RLE24 codec and heartbeat video block (frame assembly and
  `dutctl capture`/`video` still to do).

**In progress / next:**

* Self-calibrating RGMII RX phase (issue 0028). Timing closure (0019) is
  done: internal paths meet timing; the RX sample phase was calibrated by a
  hardware scan (~3 ns eye).
* Hardware smoke-test script (0020), HDMI capture and raster transport
  (0022-0024), physical keyboard wiring trial (0009), m65 support for the
  Mimas JTAG adaptor (0010, patch ready).

**Not started:** supervisor chain link (0011), audio, EDID/HPD control,
FPGA DNA board identity (0007), DUT adapter board (0008), 100 Mb/s Ethernet
(0018, low priority).

## Quick start

```
make deps                 # list/install Debian/Ubuntu packages
make test                 # HDL (nvc), dutctl and relay firmware unit tests
make bitstream            # Vivado build -> build/vivado/supervisor.bit
make jtagload             # load it (or: make jtagload-good for bits/known-good.bit)
make dutctl
sw/dutctl/build/dutctl listen -t 5
sw/dutctl/build/dutctl text <ip> "Hello"
```

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
| `firmware/relay-controller/` | Arduino sketch for the Jaycar XC4418 relay board |
| `tests/netproto.py` | reference encoder/decoder for the wire protocol |
| `vivado/`, `scripts/` | Vivado build script, toolchain and board helper scripts |
| `docs/` | design brief, ADRs, issues |
| `bits/` | index of hardware-verified bitstreams |

## Licence

LGPL-2.1-or-later (see file headers). Imported code under `third_party/`
keeps its own licence and provenance.
