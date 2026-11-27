#!/bin/sh
# Quick iteration helper: regenerate one board's schematic + PCB, run ERC and
# DRC (with schematic parity) and summarise. Usage: tools/check_board.sh main|inputs
set -e
cd "$(dirname "$0")/.."
KICAD_CLI=${KICAD_CLI:-"flatpak run --command=kicad-cli org.kicad.KiCad"}
KICAD_PY=${KICAD_PY:-"flatpak run --command=python3 org.kicad.KiCad"}
b=$1
p=mega-kvm-power-$b
mkdir -p out
python3 tools/gen_footprints.py >/dev/null
python3 tools/gen_$b.py >/dev/null
$KICAD_PY tools/pcb_build.py $b 2>&1 | grep -v -i 'gtk-warning' || true
$KICAD_CLI sch erc --severity-all -o out/$b-erc.rpt $p/$p.kicad_sch >/dev/null
$KICAD_CLI pcb drc --schematic-parity --severity-all -o out/$b-drc.rpt $p/$p.kicad_pcb >/dev/null || true
grep 'ERC messages' out/$b-erc.rpt
grep -E '^\*\* Found' out/$b-drc.rpt
grep -E '^\[' out/$b-drc.rpt | grep -v unconnected_items | sort | uniq -c || true
