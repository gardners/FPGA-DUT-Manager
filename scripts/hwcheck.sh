#!/usr/bin/env bash
# Quick hardware check of a supervisor bitstream (issue 0020, first cut).
#   scripts/hwcheck.sh [BITFILE]      (default: none = test what is running)
# Loads BITFILE over JTAG (if given), waits for both endpoints to obtain an
# address (heartbeats), then pings each endpoint and does a management write
# round trip. Prints one summary line; exit 0 when everything passed.
# Needs: the board on this host's segment, powered from its DC jack.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dutctl=$repo/sw/dutctl/build/dutctl
bit=${1:-}
wait_s=${HWCHECK_WAIT:-25}
[[ -x $dutctl ]] || make -s -C "$repo" dutctl >/dev/null

if [[ -n $bit ]]; then
	if ! make -s -C "$repo" jtagload BIT="$(realpath "$bit")" 2>&1 | grep -q 'done 1'; then
		echo "FAIL load $bit"
		exit 2
	fi
fi

# collect heartbeats: "[DUT n src] IP dutK ..."
hb=$(timeout $((wait_s + 5)) "$dutctl" listen -t "$wait_s" 2>/dev/null)
declare -A ip cnt
while read -r d i; do
	[[ -n $d ]] || continue
	ip[$d]=$i
	cnt[$d]=$(( ${cnt[$d]:-0} + 1 ))
done < <(awk '/^\[DUT/ { for (k = 1; k <= NF; k++) if ($k ~ /^dut[01]$/) print $k, $(k-1) }' <<<"$hb")

ok=1
line="${bit:+$(basename "$bit") }"
for d in dut0 dut1; do
	if [[ -z ${ip[$d]:-} ]]; then
		line+="$d: no heartbeat; "
		ok=0
		continue
	fi
	p=$(ping -c 20 -i 0.2 -W 1 -q "${ip[$d]}" 2>/dev/null | grep -o '[0-9]* received' | cut -d' ' -f1)
	m=FAIL
	"$dutctl" set "${ip[$d]}" hb-period-ms 20 >/dev/null 2>&1 && m=ok
	[[ ${p:-0} -eq 20 && $m == ok ]] || ok=0
	line+="$d ${ip[$d]} hb=${cnt[$d]} ping=${p:-0}/20 mgmt=$m; "
done
if (( ok )); then echo "PASS $line"; exit 0; else echo "FAIL $line"; exit 1; fi
