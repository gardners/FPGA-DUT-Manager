#!/bin/sh
# Autoroute the front-panel PCB (issue 0050) with Freerouting, then rebuild
# the generated board with the result.
#
#   scripts/route-front-panel.sh [path/to/freerouting.jar]
#
# The jar can also come from $FREEROUTING_JAR. Get it from
# https://github.com/freerouting/freerouting/releases (1.9.x or 2.x; needs
# Java 17+ for 2.x). Steps:
#   1. tools/route.py export   board (tracks stripped) -> route/front.dsn
#   2. freerouting             route/front.dsn -> route/front.ses (batch mode)
#   3. tools/route.py import   route/front.ses -> tracks.json
#   4. tools/build_all.sh      regenerates the board with tracks.json, DRC
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
cd "$(dirname "$0")/../hardware/mega-kvm-front"
KICAD_PY=${KICAD_PY:-"flatpak run --command=python3 org.kicad.KiCad"}

$KICAD_PY tools/route.py export
rm -f route/front.ses
java -jar "$JAR" -de route/front.dsn -do route/front.ses -mp "$PASSES"
[ -s route/front.ses ] || { echo "freerouting wrote no route/front.ses" >&2; exit 1; }
$KICAD_PY tools/route.py import
tools/build_all.sh
echo "--- DRC summary (out/drc.rpt) ---"
grep -i -E "violations|unconnected" out/drc.rpt || true
