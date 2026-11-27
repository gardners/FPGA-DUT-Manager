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

### 2026-11-27 implemented (sub-agent, branch feature/host-vlan)

Status: implemented and simulated; not yet tried on hardware. Default is
**0 = untagged**: nothing changes until the key is set. ADR 0005 section 1
(host VLAN), section 3e (heartbeat network block) and the key table carry
the details.

**Key 0x0046 host VLAN** (u16, board-wide, volatile; > 4094 bad value;
`dutctl set IP host-vlan N`).

Design choices:

1. **TX: one place.** `eth_mac_tx` inserts the 802.1Q tag (TPID 0x8100,
   PCP 0, DEI 0, VID) after the source MAC; `net_tx` hands each frame's VID
   to the MAC with `mac_start`, the slot always holds the untagged frame.
   This covers every TX path (net_tx is the only one): heartbeats, UART
   snapshots, raster, DHCP, thumbnail relay frames to the key 0x0041
   forced MAC -> host VLAN; ARP/ICMP replies, MGMT acks, JTAG responses ->
   the VLAN their request came on; relay requests and frames to a
   requester -> key 0x0043 (the relay tag moved from net_tx's header into
   the MAC too; same bytes on the wire). Tagged frames are padded to 64
   bytes + FCS (untagged part 60), so a switch that strips the tag never
   makes a runt (the relay request grew from 60 to 64 bytes).
2. **RX: strip in the MAC.** `eth_mac_rx` stores a tagged frame without
   its tag (all net_rx offsets, the DHCP option scan and the UART/JTAG copy
   offsets stay the untagged ones) and reports tagged + VID per slot. The
   line-rate taps parse the GMII stream themselves: `text_rx_tap` now skips
   the tag the way `thumb_rx_tap` does and follows the host VLAN;
   `thumb_rx_tap` is unchanged (key 0x0043). `rx_frame_observer` and the
   phase hunter only look at RX_CTL length and the MAC's good-FCS strobe,
   so tagged frames count as good frames as before.
3. **What is accepted.** Key 0: untagged only (as before). Key V:
   frames tagged V get everything; **untagged frames still get ARP, ICMP
   echo and MGMT (port 6500, incl. broadcast SET_IDENTITY)**, answered
   untagged, so a host on the untagged LAN can always set the key back
   without a reload; DHCP replies, keyboard, UART, JTAG and text are
   dropped untagged (an untagged DHCP server can never hand out a lease on
   the wrong subnet). Other VIDs and priority tags (VID 0) are dropped.
   Drops count in heartbeat bytes 198..199.
4. **Run-time change.** The new VID applies from the next frame built.
   1..2 ms later every DHCP endpoint starts over (lease dropped, DISCOVER on
   the new VLAN); until the new lease the endpoint is silent (DHCP
   fallback is off in the bitstream). The ack of the change goes back on
   the VLAN of the request and still from the old address. Static
   addresses are kept. Re-setting the current value changes nothing (no
   DHCP restart). A heartbeat/snapshot whose endpoint loses its address
   while being built is now dropped instead of leaving from 0.0.0.0.
5. **Heartbeat network block** (bytes 196..199, payload 192): host_vlan,
   host_vlan_drops. `dutctl listen` prints `host-vlan N (vlan drops M)`.
6. dutctl: `set ... host-vlan`; `dutctl thumbs` works on the VLAN
   interface (`dutctl thumbs eno2.1650 --force BOARD_IP`: the kernel strips
   the tag; `--vlan` only for a relay VLAN other than the interface's).
   No other dutctl tool uses raw sockets.
7. hwtest: key 0x0046 bad values (0x0fff, 0xffff), bad lengths, and only
   the *current* value as the valid one (0 on an untagged bench), so it
   never moves its own traffic; INFO line with the network block.

Tests: `tb_host_vlan` (new, + `tests/scenarios/tb_host_vlan.py`): key 0 ->
1650 -> 0 through supervisor_core: bad value/length; tagged frames dropped
with key 0; ack of the switch untagged and from the old lease; DHCP
DISCOVER/REQUEST tagged on the VLAN for both endpoints (an untagged OFFER
ignored), new lease 10.231.50.150; heartbeats, snapshots, DHCP tagged
while the key is set and untagged after; tagged ARP/ICMP/MGMT/JTAG ->
tagged replies, untagged ARP/ICMP/MGMT -> untagged replies; VID 1651 and
untagged KBD/TEXT/JTAG dropped; tagged KBD and UART work (kbd_udp,
"HI" looped back); text_rx_tap writes "AB" (untagged, key 0) and "CD"
(tagged, key 1650) only; drop counter 8; switch back with a tagged
request (ack tagged); every tagged frame >= 68 bytes on the wire.
tb_supervisor_core unchanged and green (relay tag now from the MAC).
netproto selftest (network block, tag), C vectors `heartbeat_net`,
`mgmt_host_vlan`.

**Switch-over (lead), step by step.**

Prerequisites: bob's `eno2.1650` = 10.231.50.1/24 with dnsmasq (pool
.100-.199) up (hardweb `scripts/lab_vlans.sh up`); the switch between bob
and the Mimas passes VLAN 1650 tagged (an unmanaged switch does; a managed
one needs 1650 tagged on both ports). Load the bitstream as usual;
`scripts/hwtest.sh` green on the untagged LAN first (it checks key 0x0046
with the current value 0 and the bad values).

1. Note the current addresses: `dutctl listen -t 2` (DUT0 and DUT1 of the
   board, untagged lab addresses).
2. Watch the VLAN on bob: `sudo tcpdump -e -n -i eno2 vlan 1650` (second
   terminal).
3. Switch: `dutctl set <DUT0 IP> host-vlan 1650` -> `status=0` (the ack
   comes back untagged: the request was untagged). The key is board-wide,
   both endpoints move.
4. Within a few ms tcpdump shows `vlan 1650` DHCP DISCOVER/REQUEST from
   02:4d:36:35:00:<DUT ID> (host names m65dutNN) and dnsmasq's offers; the
   endpoints get 10.231.50.1xx (dnsmasq's lease file or `dutctl listen`).
   On eno2 untagged (`sudo tcpdump -e -n -i eno2 'not vlan and ether src
   02:4d:36:35:00:00'`) the board is now silent.
5. Verify from bob: `dutctl listen -t 3` shows both endpoints with their
   10.231.50.x addresses (heartbeats arrive via eno2.1650; `dutctl listen
   --kv` has `host_vlan=1650`); `ping 10.231.50.x`; then
   `scripts/hwtest.sh` (it finds the board from its heartbeats and talks to
   it over the VLAN; it keeps key 0x0046 at 1650). UART/JTAG/m65 and
   `dutctl thumbs eno2.1650 --force 10.231.50.x` work the same over the
   VLAN addresses. Then update duts.conf / scripts for the new addresses
   (plan item 2).
6. Revert, normal path: `dutctl set 10.231.50.x host-vlan 0` from bob
   (the ack comes back tagged on eno2.1650, then the board DHCPs untagged
   again and returns to its lab address).
7. Revert when the VLAN path is broken but the board still has its VLAN
   address: the board answers untagged ARP/ping/MGMT at that address, so
   from bob `sudo ip route add 10.231.50.x/32 dev eno2` (more specific than
   eno2.1650's /24), `dutctl set 10.231.50.x host-vlan 0`, `sudo ip route
   del 10.231.50.x/32 dev eno2`.
8. Last resort (no lease on the VLAN, e.g. dnsmasq down: the board is then
   silent and has no address to talk to): reload (`make jtagload BIT=...`
   or `make jtagload-good`); keys are volatile, so it comes back untagged.

Build (Vivado, commit b413b49 = the HDL of this branch; later commits are
docs/scripts only; build id b413b496): **TIMING MET, WNS +0.115 ns, WHS
+0.049 ns**; 20803 LUTs (63.8 %), 53.5 BRAM tiles. `make test` green: 37
HDL testbenches (incl. tb_host_vlan), netproto selftest, 909 dutctl checks,
52 relay checks. Not loaded on hardware. Bitstream:
build/vivado/supervisor.bit in the feature/host-vlan worktree.

### 2026-11-27 lead: switched over

Build b413b496 loaded; hwtest 67/0 untagged. `dutctl set 203.28.176.86
host-vlan 1650`: both endpoints took leases from bob's dnsmasq on eno2.1650
within seconds: **DUT0 = 10.231.50.146, DUT1 = 10.231.50.162**. Over the
VLAN: ping 0.2 ms, keyboard CPLD IDCODE, hwtest 67/0. duts.conf
(`k325t`), targets/qmtech-k325t/ and the K325T doc now use 10.231.50.162.
The key is volatile: after a reload the board comes back untagged on
203.28.176.x and needs `dutctl set <ip> host-vlan 1650` (and
`hdmi-owner 1`) again.
