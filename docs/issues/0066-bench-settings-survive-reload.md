# 0066: Bench settings that survive a supervisor reload

Status: proposal, waiting on owner (owner asked "which settings? be
specific", 2026-11-28).

## Settings the bench depends on today

All MGMT keys are volatile (RAM in the FPGA): a JTAG load, reconfiguration
from flash or brown-out returns them to the build defaults. Of the keys
the bench uses, only one differs from its default:

| Board | Key | Name | Bench value | Default | Why |
|---|---|---|---|---|---|
| supervisor B0 (DNA 00124c296998c854, .86/.87) | 0x0044 | hdmi-owner | **1** (DUT0 owns HDMI IN) | 0 (both DUTs share it) | DUT1 (K325T) has no HDMI cable: with 1 its slot shows the relayed HWVS picture instead of DUT0's input |

Already right by default (listed so they are not "fixed" twice): 0x0043
relay VLAN 1650, 0x0045 relay-view 1, 0x0046 host-vlan 0, 0x0047
vlan-base 10.231.50.16. Telemetry destinations (0x0003/0x0004) and capture
(0x0040) are set and restored by hwtest/dutctl per run and must stay
default.

## Proposal

`duts.conf` gets board sections keyed by DNA (stable across DHCP):

    [board 00124c296998c854]
    set = hdmi-owner 1

`dutctl apply [--conf F]` sends them to every board heard. A user systemd
unit `dutctl keeper` listens to heartbeats and re-applies when a board's
boot id changes (heartbeat `boot` field), so nobody has to remember. No
HDL change; build defaults stay the vendor-neutral ones.
