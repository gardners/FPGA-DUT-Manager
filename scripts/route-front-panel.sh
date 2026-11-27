#!/bin/sh
# Autoroute the front-panel PCB (issue 0050) with Freerouting, then rebuild
# the generated board with the result. Normally run through `make
# pcb-routing`, which downloads a pinned Freerouting jar and only routes when
# the board generator changed since the last route.
#
#   scripts/route-front-panel.sh [path/to/freerouting.jar]
#
# The jar can also come from $FREEROUTING_JAR. Steps:
#   1. tools/build_all.sh      board from the current generator, no tracks
#   2. tools/route.py export   board -> route/front.dsn
#   3. freerouting             route/front.dsn -> route/front.ses (batch)
#   4. tools/route.py import   route/front.ses -> tracks.json
#   5. tools/build_all.sh      regenerates the board with tracks.json, DRC
# The board stays generated: delete hardware/mega-kvm-front/tracks.json to
# get an unrouted board back. Check out/drc.rpt afterwards.
set -e
JAR=${1:-$FREEROUTING_JAR}
if [ -z "$JAR" ] || [ ! -f "$JAR" ]; then
    echo "usage: $0 path/to/freerouting.jar  (or set FREEROUTING_JAR)" >&2
    exit 2
fi
JAR=$(readlink -f "$JAR")
PASSES=${PASSES:-40}
THREADS=${THREADS:-4}
cd "$(dirname "$0")/../hardware/mega-kvm-front"
KICAD_PY=${KICAD_PY:-"flatpak run --command=python3 org.kicad.KiCad"}

# Old tracks may not match a changed placement: route from a clean board,
# and put the old tracks back if anything fails.
if [ -f tracks.json ]; then
    mv tracks.json tracks.json.prev
    trap 'if [ ! -f tracks.json ] && [ -f tracks.json.prev ]; then mv tracks.json.prev tracks.json; fi' EXIT
fi
tools/build_all.sh
$KICAD_PY tools/route.py export 2>&1 | grep -v -i gtk-warning
rm -f route/front.ses
# Freerouting 2.x: headless, no analytics/telemetry, no API server.
java -jar "$JAR" --gui.enabled=false \
    --usage_and_diagnostic_data.disable_analytics=true \
    --api_server.enabled=false \
    -de route/front.dsn -do route/front.ses -mp "$PASSES" -mt "$THREADS" \
    > route/freerouting.log 2>&1 || { tail -20 route/freerouting.log >&2; exit 1; }
grep -i -E "unrouted|incomplete" route/freerouting.log | tail -1 || true
[ -s route/front.ses ] || { echo "freerouting wrote no route/front.ses" >&2; exit 1; }
$KICAD_PY tools/route.py import 2>&1 | grep -v -i gtk-warning
[ -s tracks.json ] || { echo "SES import wrote no tracks.json" >&2; exit 1; }
rm -f tracks.json.prev
tools/build_all.sh
echo "--- DRC summary (hardware/mega-kvm-front/out/drc.rpt) ---"
grep -i -E "violations|unconnected" out/drc.rpt || true
