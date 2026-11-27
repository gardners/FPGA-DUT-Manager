# 0062: Supervisor host traffic on VLAN 1650

Status: open (owner decision relayed by the hardweb session, 2026-11-27).
Related: 0060 (relay already on VLAN 1650), hardweb 0169/0174.

## Request

The supervisors' lab traffic (heartbeats, UART snapshots at 1 kHz, about
12 Mb/s of broadcast) reaches every LAN port, including the HewnWeb K325T's
100 Mb ingest. The owner chose to move it onto VLAN 1650 (option b): bob
gets an interface `eno2.1650` = 10.231.50.1/24 with a DHCP server (dnsmasq,
pool 10.231.50.100-199, no gateway or DNS) from hardweb
`scripts/lab_vlans.sh up`. Static addresses in 10.231.50.0/24 must avoid .1
and .100-199.

## Plan (lead)

* A board-wide key for the host VLAN (VID for heartbeats, MGMT, UART, JTAG,
  raster, DHCP, ARP, ICMP); **0 = untagged (default)**, so nothing changes
  until the owner confirms bob's interface is up. Keys are volatile, so a
  reload is the way back if a wrong setting cuts the board off.
* Then a bench default: switch the host VLAN to 1650 (DHCP on the VLAN),
  and update duts.conf and scripts for the new addresses.
