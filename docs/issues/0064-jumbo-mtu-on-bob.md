# 0064: Permanent jumbo frames on bob's eno2

Status: script ready, owner to run (owner, 2026-11-28). Related: 0063
(hwtest raster FAIL), ADR 0005 sections 8 and 10.

## Owner (2026-11-28)

"Give me a script for permanently enabling jumbo frames on eno2. Jumbo
frames are good for efficiency."

## Why

bob's eno2 came back at MTU 1500 after a reboot. Raster lines (2240 bytes
on the wire for 720 px RGB888) and relayed thumbnails to the host (up to
~8100 bytes) are jumbo by design, so hwtest's raster capture fails.

## Script

`sudo scripts/setup-jumbo-mtu.sh` (`--dry-run` first shows the plan):

* eno2 -> MTU 9000 (igc allows 9216), eno2.1650 -> 9000.
* eno2.3101..3104 pinned at 1500 (a VLAN inherits its parent's MTU when it
  is created, so they would otherwise become 9000 at the next boot; their
  far ends are not ours). `--other-vlans jumbo` makes them 9000 too.
* Written with `netplan set --origin-hint 60-jumbo-mtu` into
  /etc/netplan/60-jumbo-mtu.yaml only; `netplan generate`, `nmcli
  connection reload`, then `ip link set ... mtu` live: no connection is
  bounced, no DHCP renew.

Parser dry-run tested against a synthetic netplan tree (non-root cannot
read /etc/netplan). Not run on bob yet (needs sudo).

## 2026-11-28 owner ran it

eno2 now MTU 9000 (/etc/netplan/60-jumbo-mtu.yaml, 96 bytes). eno2.1650
and eno2.3101 are still 1500: the VLAN override did not apply (the script
did not find the NM-made VLAN definitions, or their ID differs). Host
raster traffic is untagged on eno2, so the raster capture is unaffected;
eno2.1650 at 1500 only limits sniffing relay frames there.
