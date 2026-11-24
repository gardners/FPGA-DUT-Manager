# ADR 0002: FPGA as signal router and UDP frame processor; phased delivery

Status: Accepted (2026-11-25)

## Context

The design brief (docs/design-brief-v0.5.md) deliberately puts all policy,
retries, reassembly, hotkeys, XVC TCP, image/audio analysis and power
sequencing on Linux. The FPGA must stay lean: no soft CPU, no DDR3, no TCP.

## Decision

FPGA responsibilities: RGMII MAC, ARP + IPv4/UDP for two logical endpoints,
fixed-format packet parse/build, raster-first TX scheduling, per-DUT UART
bridges, JTAG shift engines, MK-I keyboard device emulation, physical keyboard
host, chain PHY/control, HDMI capture → UDP, front panel. Everything is driven
by complete-state snapshots so lost packets self-heal.

Host responsibilities: `dutctl` CLI (C) now; a daemon later for XVC↔UDP proxy,
PTY bridges, video/audio reassembly, relay controller ownership, topology/ID
mapping and hotkeys.

Delivery phases (each is a feature branch, merged after hardware confirmation):

1. **Control plane**: Ethernet (both MAC/IP), ARP/ICMP echo, heartbeat,
   management, 2x UART bridge, 2x JTAG engine, 2x MK-I keyboard device,
   front panel basics; `dutctl`; Arduino relay sketch; m65 Mimas JTAG patch.
2. **Capture**: HDMI RX (DVI first) → raster UDP with packet ring and
   raster-first scheduler; host receiver.
3. **Chain + local KVM**: chain PHY, enumeration, video mux, HDMI TX on master,
   physical keyboard host (MK-I/MK-II) and arbitration.
4. **Audio, EDID/HPD, RLE24, optional extras.**

## Consequences

Phase 1 is useful on its own (remote JTAG/UART/keyboard/power for CI).
Phase boundaries are where hardware experiments resolve open questions.
