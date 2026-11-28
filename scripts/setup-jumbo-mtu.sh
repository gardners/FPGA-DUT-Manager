#!/usr/bin/env bash
# Jumbo frames (MTU 9000) on bob's eno2 and all its VLANs, kept across boots.
#
#   sudo scripts/setup-jumbo-mtu.sh [--dry-run] [--mtu N] [--iface eno2]
#
# Version 2 (2026-11-28, issue 0064). Version 1 set eno2 through netplan but
# its VLAN step did nothing: the VLANs are NetworkManager-made connections
# that the netplan lookup did not find, so they stayed at MTU "auto" (1500).
# The owner wants every VLAN at 9000, so this version:
#
#   1. eno2: `netplan set --origin-hint 60-jumbo-mtu ethernets.eno2.mtu=N`
#      (as before; /etc/netplan/60-jumbo-mtu.yaml), netplan generate,
#      nmcli connection reload.
#   2. Every NM VLAN connection whose parent is eno2 (eno2.1650,
#      eno2.3101..3104 today): `nmcli connection modify <con>
#      802-3-ethernet.mtu N`. NM stores that itself (with the netplan
#      integration it writes its own 90-NM-*.yaml), so it holds at boot.
#   3. A NetworkManager dispatcher hook, /etc/NetworkManager/dispatcher.d/
#      50-jumbo-eno2, as a safety net: whenever eno2 or an eno2.* VLAN comes
#      up (boot, reconnect, a VLAN added later), it raises the MTU to N if it
#      is lower (parent first). It never lowers anything.
#   4. Applies the MTU live with `ip link` (parent first): no connection is
#      bounced, no DHCP renew, sessions on the bench keep running.
#
# Consequence: large UDP from bob to a host that only takes 1500 on any of
# these networks is dropped (TCP negotiates its segment size and is fine).
# The bench switch passes jumbo frames.
#
# Undo: sudo rm /etc/NetworkManager/dispatcher.d/50-jumbo-eno2
#       /etc/netplan/60-jumbo-mtu.yaml; for each VLAN
#       `sudo nmcli connection modify <con> 802-3-ethernet.mtu 0` (0 = auto);
#       sudo netplan generate; sudo nmcli connection reload; reboot.
set -euo pipefail

mtu=9000 iface=eno2 dry=0
while (($#)); do
	case $1 in
	--dry-run) dry=1 ;;
	--mtu) mtu=$2; shift ;;
	--iface) iface=$2; shift ;;
	-h | --help) sed -n '2,32p' "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
((dry)) || [[ $EUID == 0 ]] || { echo "run with sudo (or --dry-run)" >&2; exit 1; }
run() { if ((dry)); then echo "  would run: $*"; else "$@"; fi; }

maxmtu=$(ip -d link show "$iface" | grep -o 'maxmtu [0-9]*' | awk '{print $2}')
((mtu <= maxmtu)) || { echo "$iface: maxmtu $maxmtu < $mtu" >&2; exit 1; }

# NM VLAN connections on $iface, as "uuid ifname"
vlans=()
while IFS=: read -r uuid type name; do
	[[ $type == vlan ]] || continue
	[[ $(nmcli -g vlan.parent connection show "$uuid") == "$iface" ]] || continue
	dev=$(nmcli -g connection.interface-name connection show "$uuid")
	vlans+=("$uuid ${dev:-$name}")
done < <(nmcli -t -f UUID,TYPE,NAME connection show)

echo "$iface: live MTU $(cat /sys/class/net/$iface/mtu) -> $mtu"
for v in "${vlans[@]}"; do
	read -r uuid dev <<<"$v"
	echo "VLAN $dev: NM mtu $(nmcli -g 802-3-ethernet.mtu connection show "$uuid"), live $(cat /sys/class/net/$dev/mtu 2>/dev/null || echo down) -> $mtu"
done
((${#vlans[@]})) || echo "(no NM VLAN connections on $iface)"

echo "1. $iface via netplan"
run netplan set --origin-hint 60-jumbo-mtu "ethernets.$iface.mtu=$mtu"
((dry)) || chmod 600 /etc/netplan/60-jumbo-mtu.yaml
run netplan generate
run nmcli connection reload

echo "2. VLAN connections via NetworkManager"
for v in "${vlans[@]}"; do
	read -r uuid dev <<<"$v"
	run nmcli connection modify "$uuid" 802-3-ethernet.mtu "$mtu"
done

hook=/etc/NetworkManager/dispatcher.d/50-jumbo-eno2
echo "3. dispatcher hook $hook"
body=$(cat <<EOF
#!/bin/sh
# Installed by FPGA-DUT-Manager scripts/setup-jumbo-mtu.sh (issue 0064):
# raise $iface and its VLANs to MTU $mtu when they come up; never lowers.
case "\$1" in $iface|$iface.*) ;; *) exit 0 ;; esac
case "\$2" in up|pre-up|dhcp4-change|connectivity-change) ;; *) exit 0 ;; esac
raise() {
	[ -e "/sys/class/net/\$1/mtu" ] || return 0
	[ "\$(cat "/sys/class/net/\$1/mtu")" -lt $mtu ] && ip link set dev "\$1" mtu $mtu
	return 0
}
raise $iface
[ "\$1" = $iface ] || raise "\$1"
exit 0
EOF
)
if ((dry)); then
	echo "  would write $hook:"; sed 's/^/    | /' <<<"$body"
else
	printf '%s\n' "$body" > "$hook"; chmod 755 "$hook"; chown root:root "$hook"
fi

echo "4. live (parent first)"
run ip link set dev "$iface" mtu "$mtu"
for v in "${vlans[@]}"; do
	read -r uuid dev <<<"$v"
	if [[ -e /sys/class/net/$dev ]]; then run ip link set dev "$dev" mtu "$mtu"; fi
done

((dry)) && exit 0
echo; echo "now:"
printf '  %-12s mtu %s\n' "$iface" "$(cat /sys/class/net/$iface/mtu)"
for v in "${vlans[@]}"; do
	read -r uuid dev <<<"$v"
	printf '  %-12s mtu %s (NM %s)\n' "$dev" "$(cat /sys/class/net/$dev/mtu 2>/dev/null || echo down)" \
		"$(nmcli -g 802-3-ethernet.mtu connection show "$uuid")"
done
echo "check after the next reboot: ip -br link | grep $iface; ip link show $iface.1650 | grep mtu"
