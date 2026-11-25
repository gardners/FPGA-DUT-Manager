#!/usr/bin/env bash
# Analyse all simulation sources with nvc and run every testbench
# (hdl/tb/tb_*.vhd) or only the ones named on the command line.
#   scripts/run-hdl-tests.sh                 # all
#   scripts/run-hdl-tests.sh tb_uart_rx ...  # selected
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
NVC=${NVC:-$REPO/tools/prefix/bin/nvc}
WORK=$REPO/build/nvc
mkdir -p "$WORK"
cd "$WORK"

# Ordered source list: lines are paths relative to the repo; '#' comments.
mapfile -t SRCS < <(grep -vE '^\s*(#|$)' "$REPO/hdl/sim_files.txt" | sed "s|^|$REPO/|")
TBS=("$@")
if [[ ${#TBS[@]} -eq 0 ]]; then
	mapfile -t TBS < <(cd "$REPO/hdl/tb" && ls tb_*.vhd | sed 's/\.vhd$//')
fi

NVC_OPTS=(--std=2008 -L "$WORK" --work=work:"$WORK/work")
"$NVC" "${NVC_OPTS[@]}" -a --relaxed "${SRCS[@]}" "$REPO"/hdl/tb/tb_*.vhd
pass=0; fail=0; failed=()
for tb in "${TBS[@]}"; do
	tb=${tb%.vhd}
	echo "=== $tb"
	# optional scenario hook: generates inputs before and checks outputs after
	hook=$REPO/tests/scenarios/$tb.py
	if [[ -f $hook ]]; then
		python3 -I "$hook" gen "$WORK/${tb}_in.txt"
	fi
	gens=()
	[[ -f $hook ]] && gens=(-gVEC_IN="${tb}_in.txt" -gCAP_OUT="${tb}_out.txt")
	if "$NVC" -H 256m "${NVC_OPTS[@]}" -e "$tb" "${gens[@]}" -r --exit-severity=error \
		> "$WORK/$tb.log" 2>&1 &&
		{ [[ ! -f $hook ]] || python3 -I "$hook" check "$WORK/${tb}_out.txt" >> "$WORK/$tb.log" 2>&1; }; then
		grep -E 'PASSED|Note|captured' "$WORK/$tb.log" | tail -4
		pass=$((pass + 1))
	else
		tail -30 "$WORK/$tb.log"
		fail=$((fail + 1)); failed+=("$tb")
	fi
done
echo "HDL tests: $pass passed, $fail failed ${failed[*]:-}"
[[ $fail -eq 0 ]]
