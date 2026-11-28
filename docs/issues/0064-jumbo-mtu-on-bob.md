# 0064: Permanent jumbo frames on bob's eno2

Status: done for eno2 (owner ran the script, 2026-11-28); eno2.1650 still 1500, see below (refreshed 2026-11-28; was: script ready, owner to run (owner, 2026-11-28). Related: 0063)
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

## 2026-11-28 lead: raster passes; script v2 for all VLANs

With eno2 at 9000, hwtest on known-good 6f2fdc94 is **69/0** (raster
capture dut1: 2 complete 720x480 frames), the first clean run.

Owner: "Give me an updated script to set all the VLANs to mtu 9000 on
boot." v1's VLAN step did nothing (NM VLANs stayed MTU auto: the netplan
lookup did not find the NM-made definitions). **v2**: eno2 via netplan as
before; each NM VLAN on eno2 via `nmcli connection modify <uuid>
802-3-ethernet.mtu 9000` (NM persists it); a dispatcher hook
/etc/NetworkManager/dispatcher.d/50-jumbo-eno2 that raises eno2 and any
eno2.* to 9000 when they come up (never lowers); live `ip link`, no
bouncing. Dry run on bob found all five VLANs (1650, 3101-3104).
