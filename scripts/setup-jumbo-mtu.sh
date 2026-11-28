#!/usr/bin/env bash
# Make jumbo frames on the bench NIC permanent (netplan + NetworkManager).
#
#   sudo scripts/setup-jumbo-mtu.sh [--dry-run] [--mtu N] [--iface eno2]
#                                   [--vlan 1650]... [--other-vlans keep|jumbo]
#
# What it sets, and why:
#   * eno2 MTU 9000. Raster lines (ADR 0005 section 8: a 720-px RGB888 line
#     is 2240 bytes on the wire) and relayed thumbnails to the host (~8100
#     bytes) are jumbo; the supervisor's host traffic is untagged on eno2
#     (key 0x0046 = 0). The igc NIC allows up to 9216; 9000 is the usual
#     interoperable value and leaves room for the 802.1Q tag.
#   * eno2.1650 MTU 9000 (board-to-board relay VLAN, issue 0060/0063), so
#     `dutctl thumbs eno2.1650` and large pings on the VLAN work.
#   * The other VLANs on eno2 (eno2.3101..3104 today) are pinned at 1500:
#     a Linux VLAN inherits its parent's MTU when it is created, so without
#     a pin they would silently become 9000 at the next boot, and their far
#     ends are not ours. `--other-vlans jumbo` makes them 9000 as well.
#
# How: `netplan set --origin-hint 60-jumbo-mtu` writes the overrides into
# /etc/netplan/60-jumbo-mtu.yaml (netplan merges it with the existing eno2
# and NM-written VLAN definitions; no other file is edited). Then `netplan
# generate` + `nmcli connection reload` make NetworkManager pick it up, and
# the MTU is changed live with `ip link`, so no connection is bounced
# (no DHCP renew, no drop for sessions using the bench). Undo with
#   sudo rm /etc/netplan/60-jumbo-mtu.yaml && sudo netplan generate &&
#   sudo nmcli connection reload   (MTUs go back to 1500 at the next boot).
#
# The switch must pass jumbo frames (bench switch does: raster capture
# passed before bob's reboot on 2026-11-28).
set -euo pipefail

mtu=9000 iface=eno2 other=keep dry=0
vlans=()
while (($#)); do
	case $1 in
	--dry-run) dry=1 ;;
	--mtu) mtu=$2; shift ;;
	--iface) iface=$2; shift ;;
	--vlan) vlans+=("$2"); shift ;;
	--other-vlans) other=$2; shift ;;
	-h | --help) sed -n '2,32p' "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
((${#vlans[@]})) || vlans=(1650)
[[ $other == keep || $other == jumbo ]] || { echo "--other-vlans keep|jumbo" >&2; exit 2; }
((dry)) || [[ $EUID == 0 ]] || { echo "run with sudo (or --dry-run)" >&2; exit 1; }

maxmtu=$(ip -d link show "$iface" | grep -o 'maxmtu [0-9]*' | awk '{print $2}')
((mtu <= maxmtu)) || { echo "$iface: maxmtu $maxmtu < $mtu" >&2; exit 1; }

# netplan IDs: eno2 itself and every VLAN whose link is eno2 (NM-created
# VLANs are stored as NM-<uuid> IDs, so look them up rather than guess).
# Prints "ID KIND VLAN_ID IFNAME" lines.
# (NETPLAN_YAML=file replaces `netplan get all`, for testing the parser)
defs=$( { if [[ -n ${NETPLAN_YAML:-} ]]; then cat "$NETPLAN_YAML"; else netplan get all 2>/dev/null; fi; } | python3 -I -c '
import sys, yaml
iface = sys.argv[1]
n = (yaml.safe_load(sys.stdin) or {}).get("network", {})
eth = n.get("ethernets", {}) or {}
for k, v in eth.items():
    v = v or {}
    name = v.get("set-name") or (v.get("match") or {}).get("name") or k
    nm = ((v.get("networkmanager") or {}).get("passthrough") or {}).get("connection.interface-name")
    if iface in (k, name, nm):
        print(k, "ethernets", "-", iface)
for k, v in (n.get("vlans", {}) or {}).items():
    v = v or {}
    nm = (v.get("networkmanager") or {}).get("passthrough") or {}
    link = v.get("link")
    ifname = nm.get("connection.interface-name") or k
    if link == iface or ifname.startswith(iface + "."):
        print(k, "vlans", v.get("id", "?"), ifname)
' "$iface")
[[ -n $defs ]] || { echo "no netplan definition found for $iface (need root to read /etc/netplan?)" >&2; exit 1; }
grep -q ' ethernets ' <<<"$defs" || { echo "no netplan ethernets entry for $iface:"$'\n'"$defs" >&2; exit 1; }

plan=()
while read -r id kind vid ifname; do
	if [[ $kind == ethernets ]]; then want=$mtu
	elif printf '%s\n' "${vlans[@]}" | grep -qx "$vid"; then want=$mtu
	elif [[ $other == jumbo ]]; then want=$mtu
	else want=1500; fi
	plan+=("$kind.$id.mtu=$want $ifname $want")
done <<<"$defs"

echo "plan (netplan key, interface, MTU):"
printf '  %s\n' "${plan[@]}"
((dry)) && exit 0

for p in "${plan[@]}"; do
	netplan set --origin-hint 60-jumbo-mtu "${p%% *}"
done
chmod 600 /etc/netplan/60-jumbo-mtu.yaml
netplan generate
nmcli connection reload
# live: parent first when growing, VLANs after
for p in "${plan[@]}"; do
	read -r _ ifname want <<<"$p"
	if [[ $ifname == "$iface" ]]; then ip link set dev "$ifname" mtu "$want"; fi
done
for p in "${plan[@]}"; do
	read -r _ ifname want <<<"$p"
	if [[ $ifname != "$iface" ]] && ip link show "$ifname" >/dev/null 2>&1; then
		ip link set dev "$ifname" mtu "$want"
	fi
done

echo; echo "/etc/netplan/60-jumbo-mtu.yaml:"; cat /etc/netplan/60-jumbo-mtu.yaml
echo; echo "now:"
for p in "${plan[@]}"; do
	read -r _ ifname _ <<<"$p"
	ip -br link show "$ifname" 2>/dev/null | awk '{print "  " $1}' | tr '\n' ' '
	ip -o link show "$ifname" 2>/dev/null | grep -o 'mtu [0-9]*' || echo "  $ifname absent"
done
echo "check after the next reboot: ip link show $iface | grep mtu"
