#!/usr/bin/env bash
# Hardware smoke test of a running supervisor board (issue 0020).
#   scripts/hwtest.sh [--quick] [--wait S]
# Runs against whatever bitstream is running on the board on this host's
# network segment; it never loads a bitstream (use scripts/hwcheck.sh BIT
# for load + quick check). The two endpoints are found from their heartbeats.
#
# Every check prints one line: PASS / FAIL / SKIP / WARN / INFO, then a
# summary. Exit 0 when nothing FAILed, 1 otherwise, 2 when no board answers.
#
# Management sets are restored at exit (also on failure / Ctrl-C). Keys
# whose value the heartbeat does not report are written with their power-up
# defaults (hdl/src/net/net_pkg.vhd default_cfg, net_rx bcfg_r) and end there.
# mac / ip / dhcp / dest-ip / dest-mac / identity are never written.
# Needs: no root; ping; arping is used when it has CAP_NET_RAW.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
D=$repo/sw/dutctl/build/dutctl
quick=0
wait_s=${HWTEST_WAIT:-4}
while (($#)); do
	case $1 in
	--quick) quick=1 ;;
	--wait) wait_s=$2; shift ;;
	-h | --help) sed -n '2,15p' "$0"; exit 0 ;;
	*) echo "usage: $0 [--quick] [--wait S]" >&2; exit 2 ;;
	esac
	shift
done
if [[ ! -x $D ]] || [[ -n $(find "$repo/sw/dutctl/src" "$repo/sw/dutctl/include" -newer "$D" -print -quit) ]]; then
	make -s -C "$repo/sw/dutctl" >/dev/null || { echo "FAIL build dutctl"; exit 2; }
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/hwtest.XXXXXX")

# ------------------------------------------------------------------ reporting
np=0 nf=0 ns=0 nw=0
report() { # STATUS NAME DETAIL...
	local s=$1 n=$2
	shift 2
	printf '%-4s %-30s %s\n' "$s" "$n" "$*"
	case $s in PASS) ((np++)) ;; FAIL) ((nf++)) ;; SKIP) ((ns++)) ;; WARN) ((nw++)) ;; esac
}
# field LINE KEY -> value of KEY=value in a key=value line
field() { awk -v k="$2" '{ for (i = 1; i <= NF; i++) { p = index($i, "="); if (substr($i, 1, p - 1) == k) { print substr($i, p + 1); exit } } }' <<<"$1"; }

# ---------------------------------------------------------- restore on exit
declare -A restore=()   # "ip key" -> hex value (first registration = original)
restore_order=()
want_restore() { # IP KEY HEX
	local k="$1 $2"
	[[ -n ${restore[$k]+x} ]] && return
	restore[$k]=$3
	restore_order+=("$k")
}
cleanup() {
	local i k bad=0
	for ((i = ${#restore_order[@]} - 1; i >= 0; i--)); do
		k=${restore_order[i]}
		# shellcheck disable=SC2086
		timeout 5 "$D" mgmt $k "${restore[$k]}" --timeout-ms 2000 2>/dev/null | grep -q 'status=[04]' || {
			echo "WARN restore $k ${restore[$k]} not acknowledged" >&2
			bad=1
		}
	done
	((${#restore_order[@]})) && ((bad == 0)) && echo "     (restored ${#restore_order[@]} management settings)"
	rm -rf "$tmp"
}
trap cleanup EXIT
trap 'echo "interrupted"; exit 1' INT TERM

# ---------------------------------------------------------------- heartbeats
# listen S [N] -> key=value heartbeat lines in $tmp/hb
listen() { timeout $(( ${1%.*} + 3 )) "$D" listen --kv -t "$1" ${2:+-n $2} >"$tmp/hb" 2>/dev/null; }
# last heartbeat line of endpoint DUT (0/1) from $tmp/hb
last_hb() { awk -v d="$1" '{ for (i = 1; i <= NF; i++) if ($i == "dut=" d) l = $0 } END { print l }' "$tmp/hb"; }
declare -A ip=() hb=()
boot=""
discover() { # S: fills ip[0..1], hb[0..1]; returns 1 if no endpoint answered
	listen "$1"
	local d l
	for d in 0 1; do
		l=$(last_hb $d)
		hb[$d]=$l
		ip[$d]=${l:+$(field "$l" ip)}
	done
	[[ -n ${hb[0]} || -n ${hb[1]} ]]
}
# fresh DUT: newest heartbeat of endpoint DUT in $REPLY; retries once
# (another session may reload the board at any time).
fresh() {
	local d=$1 tries
	for tries in 1 2; do
		listen 0.5
		REPLY=$(last_hb "$d")
		[[ -n $REPLY ]] && break
		echo "     (no heartbeat from dut$d; rediscovering)"
		discover 10 || true
	done
	if [[ -n $REPLY && -n $boot && $(field "$REPLY" boot) != "$boot" ]]; then
		report WARN board-reloaded "boot id $boot -> $(field "$REPLY" boot) during the run; later results refer to the new configuration"
		boot=$(field "$REPLY" boot)
		ip[$d]=$(field "$REPLY" ip)
	fi
	[[ -n $REPLY ]]
}

if ! discover "$wait_s" && ! discover 15; then
	report FAIL discovery "no heartbeats on UDP 6501 (board off, or not on this host's segment?)"
	exit 2
fi
boot=$(field "${hb[0]:-${hb[1]}}" boot)
eps=()
for d in 0 1; do
	if [[ -n ${ip[$d]} ]]; then
		eps+=("$d")
		report PASS "discovery dut$d" "${ip[$d]} (addr_src $(field "${hb[$d]}" addr_src): 1 dhcp, 2 fallback, 3 static)"
	else
		report FAIL "discovery dut$d" "no heartbeat"
	fi
done

# --------------------------------------------------------- heartbeat fields
for d in "${eps[@]}"; do
	l=${hb[$d]}
	build=$(field "$l" build) dna=$(field "$l" dna) id=$(field "$l" dut_id) plen=$(field "$l" plen)
	if [[ $build != 00000000 ]]; then
		c=$(git -C "$repo" rev-parse -q --verify "${build}^{commit}" 2>/dev/null | cut -c1-12)
		report PASS "hb dut$d build id" "$build${c:+ (commit $c)}"
	else report FAIL "hb dut$d build id" "zero"; fi
	[[ $dna =~ ^0*$ ]] && report FAIL "hb dut$d DNA" zero || report PASS "hb dut$d DNA" "$dna"
	if ((id >> 4 == d)); then report PASS "hb dut$d dut_id" "$(printf 0x%02x "$id") (0x0n P12 / 0x1m P13)"
	else report FAIL "hb dut$d dut_id" "$(printf 0x%02x "$id"), expected 0x${d}n"; fi
	if (($(field "$l" has_link))) && (($(field "$l" link_flags) & 1)); then
		report PASS "hb dut$d link block" "link_flags $(field "$l" link_flags) rx phase $(field "$l" rx_phase_pos) eye $(field "$l" rx_eye_width) hunts $(field "$l" rx_hunts) bad frames $(field "$l" rx_bad_frames) rx_link_flags $(field "$l" rx_link_flags)"
	else report FAIL "hb dut$d link block" "has_link $(field "$l" has_link) link_flags $(field "$l" link_flags) (payload $plen)"; fi
	(($(field "$l" has_video))) && report PASS "hb dut$d video block" "payload $plen" ||
		report FAIL "hb dut$d video block" "absent (payload $plen)"
done
if ((${#eps[@]} == 2)); then
	same=1
	for f in boot build dna; do [[ $(field "${hb[0]}" $f) == "$(field "${hb[1]}" $f)" ]] || same=0; done
	((same)) && report PASS "hb endpoints agree" "same boot/build/dna" || report FAIL "hb endpoints agree" "boot/build/dna differ"
fi
l=${hb[${eps[0]}]}
caps=$(field "$l" caps)
report INFO capabilities "$(printf 0x%x "$caps"): uart $((caps & 1)) jtag $((caps >> 1 & 1)) kbd-dev $((caps >> 2 & 1)) phys-kbd $((caps >> 3 & 1)) capture $((caps >> 4 & 1)) chain $((caps >> 5 & 1)) audio $((caps >> 6 & 1))"

# video (HDMI out looped back into HDMI in: 720x480 of 858x525, 27 MHz)
for d in "${eps[@]}"; do
	l=${hb[$d]}
	(($(field "$l" has_video))) || { report FAIL "video dut$d" "no video block"; continue; }
	vf=$(field "$l" video_flags) ha=$(field "$l" h_active) va=$(field "$l" v_active)
	ht=$(field "$l" h_total) vt=$(field "$l" v_total) pc=$(field "$l" pixel_clock_hz)
	desc="flags $vf ${ha}x$va of ${ht}x$vt $(awk -v p="$pc" 'BEGIN { printf "%.3f MHz", p / 1e6 }') tmds errors $(field "$l" tmds_decode_errors)"
	if ((vf & 3)) && ((vf & 2)) && ((ha == 720 && va == 480 && ht == 858 && vt == 525 && pc > 26730000 && pc < 27270000)); then
		report PASS "video dut$d" "locked $desc"
	else
		report FAIL "video dut$d" "expected locked 720x480 of 858x525 ~27 MHz: $desc"
	fi
done

# ---------------------------------------------------------- ping and ARP
pings=$((quick ? 5 : 20))
for d in "${eps[@]}"; do
	r=$(timeout 20 ping -c $pings -i 0.2 -W 1 -q "${ip[$d]}" 2>/dev/null | grep -o '[0-9]* received' | cut -d' ' -f1)
	((${r:-0} == pings)) && report PASS "ping dut$d" "${r}/$pings" || report FAIL "ping dut$d" "${r:-0}/$pings"
	want=$(printf '02:4d:36:35:00:%02x' "$(field "${hb[$d]}" dut_id)")
	mac=""
	if a=$(timeout 6 arping -c 2 -w 4 "${ip[$d]}" 2>/dev/null); then
		mac=$(grep -oiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' <<<"$a" | head -1)
		how=arping
	else
		mac=$(ip neigh show "${ip[$d]}" 2>/dev/null | grep -oiE 'lladdr ([0-9a-f]{2}:){5}[0-9a-f]{2}' | cut -d' ' -f2)
		how="neighbour table after ping"
	fi
	if [[ ${mac,,} == "$want" ]]; then report PASS "arp dut$d" "$mac ($how)"
	elif [[ -n $mac ]]; then report FAIL "arp dut$d" "$mac, expected $want ($how)"
	else report FAIL "arp dut$d" "no ARP entry ($how)"; fi
done

# ---------------------------------------------------- heartbeat period
# rate D... -> "period_ms received sent" per endpoint from $tmp/hb
rate() {
	awk -v d="$1" '{ dd = ""; for (i = 1; i <= NF; i++) { split($i, a, "="); v[a[1]] = a[2] }
		if (v["dut"] != d) next
		if (!n++) { t0 = v["t"]; s0 = v["seq"] } t1 = v["t"]; s1 = v["seq"] }
		END { if (n < 2 || s1 == s0) { print "0 " n+0 " 0"; exit }
		      printf "%.2f %d %d\n", (t1 - t0) * 1000 / (s1 - s0), n, s1 - s0 + 1 }' "$tmp/hb"
}
check_period() { # EXPECTED_MS SECS LABEL
	listen "$2"
	local d p n s
	for d in "${eps[@]}"; do
		read -r p n s < <(rate "$d")
		if awk -v p="$p" -v e="$1" 'BEGIN { exit !(p > e * 0.9 && p < e * 1.1) }' && ((n * 100 >= s * 98)); then
			report PASS "hb period dut$d $3" "${p} ms (want $1), received $n of $s"
		else
			report FAIL "hb period dut$d $3" "${p} ms (want $1), received $n of $s"
		fi
	done
}
mgmt() { timeout 5 "$D" mgmt "$@" --timeout-ms 1500 2>/dev/null; }
listen 2
declare -A orig_period=()
for d in "${eps[@]}"; do
	read -r p n s < <(rate "$d")
	orig_period[$d]=$(awk -v p="$p" 'BEGIN { r = int(p + 0.5); print (r >= 1 && r <= 1000) ? r : 20 }')
done
check_period "${orig_period[${eps[0]}]}" 2 "(as found)"
if ((!quick)); then
	for d in "${eps[@]}"; do
		want_restore "${ip[$d]}" 0x0050 "$(printf %04x "${orig_period[$d]}")"
		mgmt "${ip[$d]}" 0x0050 0032 | grep -q status=0 || report FAIL "hb period dut$d set 50" "not accepted"
	done
	check_period 50 3 "(set 50)"
	for d in "${eps[@]}"; do mgmt "${ip[$d]}" 0x0050 "$(printf %04x "${orig_period[$d]}")" >/dev/null; done
	check_period "${orig_period[${eps[0]}]}" 2 "(restored)"
fi

# ------------------------------------------------------------- management
gen=""
# expect IP KEY HEX WANT_STATUS -> sets $mres ("" ok, else problem text)
expect() {
	local out st g
	out=$(mgmt "$1" "$2" "$3")
	if [[ $out != *status=* ]]; then mres+=" ${3:-<empty>}: no ack;"; return; fi
	st=$(field "$out" status) g=$(field "$out" cfg_gen)
	if ((st != $4)); then
		mres+=" ${3:-<empty>}: status $st (${stname[st]:-?}), want $4 (${stname[$4]});"
	elif [[ -n $gen ]] && { ((st == 0 && g <= gen)) || ((st != 0 && g != gen)); }; then
		mres+=" ${3:-<empty>}: cfg_gen $gen -> $g;"
	fi
	gen=$g
}
stname=(ok bad-key bad-length bad-value duplicate)
# key NAME KEY SCOPE RESTORE_HEX "VALID..." "BAD_VALUE..." "BAD_LENGTH..."
#   SCOPE ep = per endpoint (all endpoints), board = once (first endpoint)
keytest() {
	local name=$1 key=$2 scope=$3 rest=$4 valid=$5 badv=$6 badl=$7 d v targets
	[[ $scope == ep ]] && targets=("${eps[@]}") || targets=("${eps[0]}")
	for d in "${targets[@]}"; do
		mres=""
		local g0=$gen
		want_restore "${ip[$d]}" "$key" "$rest"
		for v in $valid; do expect "${ip[$d]}" "$key" "$v" 0; done
		for v in $badv; do expect "${ip[$d]}" "$key" "$v" 3; done
		for v in $badl; do expect "${ip[$d]}" "$key" "$v" 2; done
		expect "${ip[$d]}" "$key" "$rest" 0
		local what="ok[${valid// /,}${badv:+] bad-value[${badv// /,}}${badl:+] bad-length[${badl// /,}}] gen $g0->$gen"
		[[ -z $mres ]] && report PASS "mgmt dut$d $name" "$what" || report FAIL "mgmt dut$d $name" "${mres%;}"
	done
}
l=${hb[${eps[0]}]}
gen=$(field "$l" cfg_gen)
sel=$(field "$l" selected) pol=$(field "$l" kbd_policy)
kt=$(printf %02x $((sel & 15))) vt=$(printf %02x $((sel >> 4)))
[[ $kt == 0f ]] && kt=ff
[[ $vt == 0f ]] && vt=ff
#        name          key    scope rest     valid             bad-value  bad-length
keytest baud           0x0010 ep    04189375 "04189375"        ""         "041893 0418937500"
keytest uart-fast      0x0011 ep    00       "00"              ""         "0000"
keytest uart-snap      0x0012 ep    01       "01"              ""         "0101"
keytest uart-period-us 0x0013 ep    03e8     "07d0 0064"       "0063 0000" "03 03e800"
keytest kbd-policy     0x0020 ep    "$(printf %02x "$pol")" "01 00" "02 ff" "0000"
keytest kbd-override   0x0021 ep    00       "00"              "04"       "0000"
keytest kbd-target     0x0030 board "$kt"    "$kt"             ""         "0000"
keytest video-target   0x0031 board "$vt"    "$vt"             ""         "0000"
keytest coupled        0x0032 board 01       "01"              ""         "0101"
keytest kbd-leds       0x0033 board 00       "01 02 00"        "03"       "0000"
keytest kbd-led-rgb    0x0034 board 000000000000000000000000 "000000000000000000000000" "" "0000000000000000000000 00000000000000000000000000"
keytest console-screen 0x0035 board 00       "01 02 03 00"     "04"       "0000"
keytest capture        0x0040 ep    00       "00"              ""         "0000"
keytest hb-period-ms   0x0050 ep    "$(printf %04x "${orig_period[${eps[0]}]}")" "$(printf %04x "${orig_period[${eps[0]}]}")" "0000" "14 001400"
keytest out-policy     0x0060 ep    00       "00"              "03"       "0000"
for k in 0x0000 0x0007 0x0041 0x7fff 0xffff; do
	mres=""
	expect "${ip[${eps[0]}]}" $k 00 1
	[[ -z $mres ]] && report PASS "mgmt bad key $k" "bad-key" || report FAIL "mgmt bad key $k" "${mres%;}"
done
# duplicate cmd_id: acked as duplicate, not re-applied
c=$((RANDOM + 1))
a=$(mgmt "${ip[${eps[0]}]}" 0x0021 00 --cmd-id $c) b=$(mgmt "${ip[${eps[0]}]}" 0x0021 00 --cmd-id $c)
if [[ $(field "$a" status) == 0 && $(field "$b" status) == 4 && $(field "$a" cfg_gen) == "$(field "$b" cfg_gen)" ]]; then
	report PASS "mgmt duplicate cmd_id" "second ack status 4, cfg_gen unchanged $(field "$b" cfg_gen)"
else report FAIL "mgmt duplicate cmd_id" "first [$a] second [$b]"; fi
# wrong dut index: dropped (no ack) and counted in rx_rejects
if ((${#eps[@]} == 2)); then
	fresh 0 && r0=$(field "$REPLY" rx_rejects)
	o=$(timeout 5 "$D" mgmt "${ip[0]}" 0x0021 00 --dut 1 --timeout-ms 600 2>/dev/null)
	fresh 0 && r1=$(field "$REPLY" rx_rejects)
	if [[ $o == noack ]] && ((${r1:-0} > ${r0:-0})); then report PASS "mgmt wrong dut index" "dropped, rx_rejects $r0 -> $r1"
	else report FAIL "mgmt wrong dut index" "reply [$o] rx_rejects $r0 -> $r1"; fi
fi

# --------------------------------------------------------- console screens
d=${eps[0]}
want_restore "${ip[$d]}" 0x0035 00
cs_ok=1 cs_txt=""
vid_present=$(( $(field "${hb[$d]}" video_flags) & 1 ))
for pair in "01 0" "02 1" "03 2" "00 $((vid_present ? 0 : 1))"; do
	read -r v want <<<"$pair"
	mgmt "${ip[$d]}" 0x0035 "$v" | grep -q status=0 || { cs_ok=0; cs_txt+=" set $v refused;"; continue; }
	got=""
	for try in 1 2 3; do
		fresh "$d" && got=$(field "$REPLY" console_screen)
		[[ $got == "$want" ]] && break
	done
	cs_txt+=" $v->$got"
	[[ $got == "$want" ]] || { cs_ok=0; cs_txt+="(want $want)"; }
done
((cs_ok)) && report PASS console-screen "set->shown:$cs_txt (0 editable, 1 no video, 2 select)" ||
	report FAIL console-screen "set->shown:$cs_txt"

# -------------------------------------------------------- physical keyboard
pt=$(field "${hb[$d]}" phys_type)
case $pt in 0) ptn=none ;; 1) ptn=MK-I ;; 2) ptn=MK-II ;; *) ptn=? ;; esac
report INFO "physical keyboard" "type $pt ($ptn), change count $(field "${hb[$d]}" phys_change), owner $(field "${hb[$d]}" kbd_owner)"
((pt != 0 && !(caps & 8))) && report WARN "caps phys-kbd bit" "keyboard type $pt reported but capability b3 (phys kbd host) is clear"
want_restore "${ip[$d]}" 0x0033 00
kl=""
for v in 00 01 02 00; do kl+=" $v:$(field "$(mgmt "${ip[$d]}" 0x0033 $v)" status)"; done
[[ $kl == " 00:0 01:0 02:0 00:0" ]] && report PASS "kbd-leds modes" "status$kl (restored 0)" || report FAIL "kbd-leds modes" "status$kl"

# ------------------------------------------------------------------ JTAG
for d in "${eps[@]}"; do
	fresh "$d" || { report FAIL "jtag dut$d" "heartbeats lost"; continue; }
	tf=$(field "$REPLY" target_flags) js=$(field "$REPLY" jtag_status)
	powered=$(( (tf & 8) && (tf & 3) ))
	o=$(timeout 15 "$D" jtag-idcode "${ip[$d]}" 2>&1)
	rc=$?
	if ((!powered)); then
		if ((rc != 0)) && [[ $o == *"not powered"* ]] && ((js & 8)); then
			report PASS "jtag dut$d refuses" "DUT unpowered (target_flags $tf, jtag_status $js): '$o'"
		else
			report FAIL "jtag dut$d refuses" "DUT unpowered (target_flags $tf, jtag_status $js) but rc $rc: '$o'"
		fi
	else
		idc=$(grep -o '0x[0-9a-f]\{8\}' <<<"$o")
		if ((rc == 0)) && [[ -n $idc ]] && (((idc & 0xfff) == 0x093)); then
			report PASS "jtag dut$d IDCODE" "$idc (Xilinx; MEGA65 R6 = 0x13631093 / A200T 0x13636093)"
		elif ((rc == 0)) && [[ -n $idc ]]; then
			report WARN "jtag dut$d IDCODE" "$idc (not a Xilinx ID)"
		else
			report FAIL "jtag dut$d IDCODE" "DUT powered (target_flags $tf) but rc $rc: '$o'"
		fi
	fi
done

# ------------------------------------------------------------------ UART
for d in "${eps[@]}"; do
	tf=$(field "${hb[$d]}" target_flags)
	if (((tf & 8) && (tf & 3))) && ((!quick)); then
		sleep 6 | timeout -s INT 5 "$D" uart "${ip[$d]}" >"$tmp/uart$d" 2>/dev/null
		nb=$(wc -c <"$tmp/uart$d")
		report INFO "uart dut$d" "$nb bytes in 4 s$( ((nb)) && printf ': %q' "$(head -c 60 "$tmp/uart$d")")"
	elif ((quick)); then
		report SKIP "uart dut$d" "--quick"
	else
		report SKIP "uart dut$d" "DUT unpowered (target_flags $tf)"
	fi
done

# ------------------------------------------------------- raster capture
if ((caps & 16)) && ((!quick)); then
	# Only the video target's lines are captured, and the FPGA never sends
	# raster to a broadcast destination: point that DUT's telemetry at this
	# host (restored to broadcast, the default, at exit).
	d=$(( (vt_sel = $(field "$(last_hb ${eps[0]})" selected) >> 4) & 1 ))
	src=$(ip -o route get "${ip[$d]}" | awk '{ for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1) }')
	dev=$(ip -o route get "${ip[$d]}" | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1) }')
	mac=$(tr -d : < "/sys/class/net/$dev/address")
	ipx=$(printf '%02x' ${src//./ })
	want_restore "${ip[$d]}" 0x0040 00
	want_restore "${ip[$d]}" 0x0003 ffffffff
	want_restore "${ip[$d]}" 0x0004 ffffffffffff
	mgmt "${ip[$d]}" 0x0004 "$mac" >/dev/null
	mgmt "${ip[$d]}" 0x0003 "$ipx" >/dev/null
	if o=$(timeout 25 "$D" video "${ip[$d]}" --enable --frames 2 --timeout 15 --require-complete --out "$tmp/frame$d" 2>&1); then
		report PASS "raster dut$d (video target)" "$(tr '\n' ' ' <<<"$o")"
	else report FAIL "raster dut$d (video target)" "$(tr '\n' ' ' <<<"$o")"; fi
	mgmt "${ip[$d]}" 0x0040 00 >/dev/null
	mgmt "${ip[$d]}" 0x0003 ffffffff >/dev/null
	mgmt "${ip[$d]}" 0x0004 ffffffffffff >/dev/null
else
	report SKIP "raster capture" "$( ((quick)) && echo --quick || echo 'capability b4 (hdmi capture) not set')"
fi

# --------------------------------------------------------------- summary
echo "---- $np passed, $nf failed, $nw warnings, $ns skipped (board ${ip[0]:-?} / ${ip[1]:-?}, boot $boot)"
exit $((nf ? 1 : 0))
