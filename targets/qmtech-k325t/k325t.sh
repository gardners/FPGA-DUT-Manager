#!/bin/bash
# QMTECH K325T (supervisor DUT1) helper, issue 0057. SRAM loads only; this
# script never touches the SPI flash.
#
#   k325t.sh on               relay 5 on (the board boots its SPI-flash image)
#   k325t.sh load [BIT]       load BIT (default build/k325t_bringup.bit) to SRAM over XVC
#   k325t.sh stat             read the configuration status register
#   k325t.sh off              park TMS/TDI low (TAP in Run-Test/Idle), then relay 5 off
#
# Env: DUTCTL, OFL (openFPGALoader), IP (203.28.176.87), DUT (1), RELAY_TTY
# (/dev/ttyACM0), RELAY_CH (5), HALF (6 = 10.4 MHz, from dutctl jtag-speed),
# PORT (2557, dutctl xvc), DUTCTL_MTU (path MTU, dutctl default 1500).
# dutctl xvc splits shifts itself (issue 0059); SPLIT=1 puts the old
# xvc-split.py proxy in front (SPLIT_PORT 2558, fallback for a dutctl
# older than issue 0059).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
main=$(git -C "$repo" worktree list --porcelain | awk '/^worktree /{print $2; exit}')
DUTCTL=${DUTCTL:-$main/sw/dutctl/build/dutctl}
OFL=${OFL:-$main/tools/prefix/bin/openFPGALoader}
IP=${IP:-203.28.176.87}
DUT=${DUT:-1}
RELAY_TTY=${RELAY_TTY:-/dev/ttyACM0}
RELAY_CH=${RELAY_CH:-5}
HALF=${HALF:-6}
PORT=${PORT:-2557}
SPLIT=${SPLIT:-0}
SPLIT_PORT=${SPLIT_PORT:-2558}
# the port openFPGALoader talks to
if [ "$SPLIT" = 1 ]; then XPORT=$SPLIT_PORT; else XPORT=$PORT; fi

pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

start_xvc() {
  "$DUTCTL" xvc "$IP" "$DUT" --port "$PORT" --half "$HALF" >/dev/null 2>&1 &
  pids+=($!)
  if [ "$SPLIT" = 1 ]; then
    python3 -I "$here/xvc-split.py" --listen "$SPLIT_PORT" --upstream "$PORT" >/dev/null 2>&1 &
    pids+=($!)
  fi
  for _ in $(seq 50); do
    (exec 3<>/dev/tcp/127.0.0.1/"$XPORT") 2>/dev/null && return 0
    sleep 0.1
  done
  echo "xvc proxy did not start" >&2; exit 1
}

# One XVC shift of a single TCK with TMS=0, TDI=0: from Test-Logic-Reset or
# Run-Test/Idle the TAP ends in Run-Test/Idle and the supervisor keeps
# driving TMS/TDI low (issue 0056), so nothing back-feeds the board's 3V3.
park() {
  python3 -I - "$XPORT" <<'EOF'
import socket, struct, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])))
s.sendall(b"shift:" + struct.pack("<I", 1) + b"\0" + b"\0")
assert len(s.recv(1)) == 1
print("TAP parked: TMS=0 TDI=0")
EOF
}

case "${1:-}" in
  on)   "$DUTCTL" relay "$RELAY_TTY" POWER "$RELAY_CH" ON; sleep 1
        "$DUTCTL" jtag-idcode "$IP" "$DUT" ;;
  load) bit=${2:-$here/build/k325t_bringup.bit}
        start_xvc
        t0=$(date +%s.%N)
        "$OFL" -c xvc-client --ip 127.0.0.1 --port "$XPORT" --freq 10000000 "$bit" 2>&1 \
          | tr '\r' '\n' | grep -v '%'
        echo "load time $(echo "$(date +%s.%N) - $t0" | bc) s"
        "$OFL" -c xvc-client --ip 127.0.0.1 --port "$XPORT" --read-register STAT 2>&1 \
          | grep -E "raw value|^Done|CRC Error"
        park ;;
  stat) start_xvc
        "$OFL" -c xvc-client --ip 127.0.0.1 --port "$XPORT" --read-register STAT 2>&1 \
          | grep -v -E "^(freq|a0|detected)"
        park ;;
  off)  start_xvc; park; cleanup; pids=()
        "$DUTCTL" relay "$RELAY_TTY" POWER "$RELAY_CH" OFF ;;
  *)    sed -n '2,15p' "$0"; exit 2 ;;
esac
