#!/usr/bin/env bash
# Locate attached pre-V4 Mimas A7 boards (USB 2a19:1009).
#   --list     list boards with USB serial and UART tty
#   --require  exit non-zero with guidance unless at least one board has its
#              UART tty bound (i.e. the udev rule is installed and the board
#              was reinserted afterwards)
set -euo pipefail
VID=2a19
PID=1009
mode=${1:---list}

found=0
ttyok=0
for dev in /sys/bus/usb/devices/*; do
	[[ -f $dev/idVendor ]] || continue
	[[ $(<"$dev/idVendor") == "$VID" && $(<"$dev/idProduct") == "$PID" ]] || continue
	found=$((found + 1))
	serial=$(cat "$dev/serial" 2>/dev/null || echo '?')
	tty=""
	for t in "$dev"/*:1.0/ttyUSB*; do
		[[ -e $t ]] && tty=/dev/$(basename "$t")
	done
	[[ -n $tty ]] && ttyok=$((ttyok + 1))
	printf 'Mimas A7  usb=%s  serial=%s  uart=%s\n' "$(basename "$dev")" "$serial" "${tty:-<none>}"
done

if [[ $mode == --require ]]; then
	if [[ $found -eq 0 ]]; then
		echo "error: no Mimas A7 (USB $VID:$PID) attached." >&2
		exit 1
	fi
	if [[ $ttyok -eq 0 ]]; then
		cat >&2 <<EOF
error: Mimas A7 found but its USB UART is not bound to a tty.
  Run:  scripts/setup-mimas-udev-rule.sh
  then unplug and reinsert the board, and try again.
EOF
		exit 1
	fi
fi
[[ $found -gt 0 || $mode == --list ]]
