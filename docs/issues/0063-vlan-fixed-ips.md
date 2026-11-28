# 0063: Fixed private IPs on the inter-board VLAN (1650), no DHCP

Status: done, on hardware (build 1fa1b802) (refreshed 2026-11-28; was: open (owner, 2026-11-28). Related: 0060 (relay on VLAN 1650), 0062)
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

### 2026-11-28 supervisor VLAN identity implemented (sub-agent, branch feature/vlan-fixed-ip)

Status: implemented and simulated; not tried on hardware. Details in ADR
0005 section 1 ("VLAN identity"), section 3e and the key table.

* **Identity**: vlan_ip = key 0x0047 base + 16 + B (B = DIP[7:4]) on the
  inter-board VLAN (key 0x0043, default 1650), MAC = endpoint 0's
  (02:4d:36:35:00:<DUT0 ID>). The board answers ARP requests for it and
  ICMP echo to it (at endpoint 0's MAC) **only when tagged with the key
  0x0043 VID**, replies tagged with that VID, from vlan_ip; independent of
  DHCP (works before any lease or fallback) and of key 0x0046. Untagged,
  other-VID or wrong-MAC requests for vlan_ip are not answered. Key 0x0043
  = 0 -> identity off (never answered untagged). No DHCP on the VLAN.
* **Key 0x0047** VLAN subnet base: 4 bytes IPv4, /24 implied, default
  10.231.50.0; last octet /= 0 -> bad value (3), length /= 4 -> bad length.
  `dutctl set IP vlan-base 10.231.50.0`. (0x0042 stays unused: hwtest uses
  it as its bad-key probe.)
* **Heartbeat** payload 192 -> 200 (208 bytes on the wire): 200..203
  vlan_ip (0.0.0.0 = off), 204..205 vlan (key 0x0043), 206..207 vlan_hits
  (ARP+ICMP answered for vlan_ip, wrapping). `dutctl listen` prints
  `vlan-ip 10.231.50.16 (vlan 1650, answered N)` or `vlan-ip off`;
  `--kv` has vlan_ip/vlan/vlan_hits.
* HDL: net_rx classifies (S_PRE: tagged with key 0x0043 VID, ARP target /
  IP destination = vlan_ip, destination MAC = endpoint 0's) and takes the
  identity branch before the host-VLAN filter; reply_t.vsrc tells net_tx to
  use vlan_ip as the ARP sender / ICMP source address. A tagged frame the
  identity does not take goes the host path as before (and with key 0x0046
  = 0 counts in host_vlan_drops).
* Tests: `tb_vlan_ident` + `tests/scenarios/tb_vlan_ident.py` (DIP 0x35,
  identity 10.231.50.19): tagged ARP/ping answered before any address;
  untagged, VID 1651, DUT1's MAC and board 4's identity ignored; host-side
  ARP/ping untagged from the fallback address unchanged, tagged ARP for it
  dropped; key 0x0047 bad value/length, new base 192.168.99.0 (identity
  moves, old ignored); key 0x0043 = 0 -> off; then key 0x0043 = key 0x0046
  = 1650: identity and endpoint each answered from their own address on
  1650; heartbeat vlan_ip/vlan per phase, vlan_hits 6, drops 7. netproto
  selftest (layout, vlan_ident()), C vectors `heartbeat_vident`,
  `mgmt_vlan_base`. hwtest: INFO line; `ping vlan identity` via
  `eno2.<vlan>` (HWTEST_VLAN_IF overrides) when it is up, else SKIP, with
  the neighbour MAC checked against DUT0's; keytest for key 0x0047.

**How the lead verifies** (board 0, DIP[7:4] = 0; bob's eno2.1650 =
10.231.50.1/24 up, host-vlan 0):

1. Load the build, `dutctl listen -t 2`: both endpoints on their untagged
   DHCP addresses, `vlan-ip 10.231.50.16 (vlan 1650, answered 0)`.
2. `ping -I eno2.1650 -c 5 10.231.50.16` -> 5/5; `ip neigh show
   10.231.50.16 dev eno2.1650` -> 02:4d:36:35:00:<DUT0 ID>. Optional:
   `sudo tcpdump -e -n -i eno2 vlan 1650 and icmp` shows the replies
   tagged 1650. `dutctl listen` now shows answered >= 6 (ARP + 5 pings).
3. `ping 10.231.50.16` must not get an answer over the untagged LAN (bob
   routes it via eno2.1650 anyway; `arping -I eno2 10.231.50.16` should get
   nothing).
4. `scripts/hwtest.sh` (it pings the identity via eno2.1650 and reports
   PASS, or SKIP without the interface).

Build (Vivado, commit 1fa1b80 = the HDL of this branch; later commits are
C/scripts/docs only; build id 1fa1b802): **TIMING MET, WNS +0.039 ns, WHS
+0.050 ns**; 21078 LUTs (64.7 %), 53.5 BRAM tiles. `make test` green: 38
HDL testbenches (incl. tb_vlan_ident), netproto selftest, 917 dutctl
checks, 52 relay checks. Not loaded on hardware. Bitstream:
build/bits/supervisor-1fa1b802.bit in the feature/vlan-fixed-ip worktree.

### 2026-11-28 lead: on hardware (build 1fa1b802)

`dutctl listen`: vlan-ip 10.231.50.16 (vlan 1650). `ping -I eno2.1650
10.231.50.16` answers (0.2 ms), neighbour 02:4d:36:35:00:00. hwtest 68/1:
PASS "ping vlan identity" 20/20; the FAIL is raster capture, which also
fails on the previous build b413b496 now: bob's eno2 MTU is 1500 after
the reboot and raster packets are larger (host configuration, the owner's
call). Promoted to known-good.
