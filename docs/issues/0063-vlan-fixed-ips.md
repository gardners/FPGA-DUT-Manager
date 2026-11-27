# 0063: Fixed private IPs on the inter-board VLAN (1650), no DHCP

Status: open (owner, 2026-11-28). Related: 0060 (relay on VLAN 1650), 0062
(host VLAN; superseded for the bench, see below).

## Owner (2026-11-28)

"DHCP to talk to the connected host should be non-VLANd, and it's the comms
between the Mimas boards that should be on the VLAN, and not require DHCP.
You can come up with a scheme of fixed private IPs for the VLAN between the
boards and from the sources."

So: host traffic (DHCP, heartbeats, MGMT, UART, JTAG/XVC, screenshots)
stays untagged with DHCP, as before 0062 (key 0x0046 host-vlan stays in
the bitstream, default 0, and the bench uses 0). Board-to-board and source
traffic goes on VLAN 1650 with fixed addresses derived from board and
machine numbers.

## Scheme (lead; owner may overrule)

Subnet **10.231.50.0/24** on VID 1650 (bob is already 10.231.50.1 on
eno2.1650). No DHCP on the VLAN; no gateway.

| Address | Use |
|---|---|
| 10.231.50.1 | bob (lab host, optional monitor) |
| .2 - .15 | reserved: other lab hosts, switch management |
| **.16 + B** (.16 - .31) | **supervisor Mimas board B** (B = DIP[7:4], 0..15): one address per board, used for all its inter-board traffic |
| **.32 + M** (.32 - .63) | **machine M** (0..31, the KVM machine number = 2·B + slot today): the address a source board (e.g. a HewnWeb board without HDMI) uses on the VLAN. K325T = machine 1 -> **10.231.50.33** |
| .64 - .99 | spare |
| .100 - .199 | left free (was the dnsmasq pool; not needed by us) |
| .200 - .254 | spare |

* MACs on the VLAN stay as they are: a supervisor uses its board MAC
  (02:4d:36:35:00:<id> of endpoint 0, as the relay already does); sources
  use their own.
* A supervisor answers ARP and ICMP echo for its .16 + B address on the
  VLAN (tagged), so bob can ping it on eno2.1650; future inter-board UDP
  (e.g. cross-board KVM, 0044) uses these addresses. The relay itself is
  layer 2 (EtherType 0x88B5) and needs no IP.
* The subnet base is a board-wide key (default 10.231.50.0/24), so the lab
  can move it without a rebuild.
