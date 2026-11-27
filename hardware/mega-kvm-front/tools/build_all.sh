#!/bin/sh
# Regenerate the front-panel board (issue 0050) and its outputs:
#   schematic (gen_front.py) -> ERC -> board (pcbnew Python; tracks from
#   tracks.json if present) -> DRC with schematic parity -> schematic PDF,
#   renders, JLC BOM + CPL, panel-holes.json (case generator input).
# KiCad 10 runs as a flatpak; override KICAD_CLI / KICAD_PY if it is native.
set -e
cd "$(dirname "$0")/.."
KICAD_CLI=${KICAD_CLI:-"flatpak run --command=kicad-cli org.kicad.KiCad"}
KICAD_PY=${KICAD_PY:-"flatpak run --command=python3 org.kicad.KiCad"}
P=mega-kvm-front
mkdir -p out

python3 tools/gen_front.py
$KICAD_CLI sch erc --severity-all -o out/erc.rpt $P.kicad_sch >/dev/null
$KICAD_PY tools/pcb_build.py 2>&1 | grep -v -i 'gtk-warning' || true
$KICAD_CLI pcb drc --schematic-parity --severity-all -o out/drc.rpt $P.kicad_pcb >/dev/null || true

$KICAD_CLI sch export pdf -o out/$P-schematic.pdf $P.kicad_sch >/dev/null
$KICAD_CLI sch export bom -o out/$P-bom.csv \
    --fields 'Reference,Value,Footprint,LCSC,MPN,JLC,${QUANTITY},${DNP}' \
    --labels 'Designator,Comment,Footprint,LCSC,MPN,JLC,Qty,DNP' \
    --group-by 'Value,Footprint,LCSC,${DNP}' --ref-range-delimiter '' $P.kicad_sch >/dev/null
$KICAD_CLI pcb export pos --format csv --units mm --side both --exclude-dnp \
    -o out/$P-cpl-raw.csv $P.kicad_pcb >/dev/null
# JLC CPL column names
sed -e '1s/.*/Designator,Val,Package,Mid X,Mid Y,Rotation,Layer/' out/$P-cpl-raw.csv > out/$P-cpl.csv
rm -f out/$P-cpl-raw.csv
$KICAD_CLI pcb render --side top --width 2000 --height 1000 --zoom 1.9 -o out/$P-front.png $P.kicad_pcb >/dev/null 2>&1 || true
$KICAD_CLI pcb render --side bottom --width 2000 --height 1000 --zoom 1.9 -o out/$P-back.png $P.kicad_pcb >/dev/null 2>&1 || true
$KICAD_CLI pcb render --side top --rotate '-45,0,-20' --quality basic --width 2000 --height 1200 --zoom 1.5 \
    -o out/$P-3d.png $P.kicad_pcb >/dev/null 2>&1 || true
$KICAD_CLI pcb export svg --mode-single --fit-page-to-board --exclude-drawing-sheet \
    -l Edge.Cuts,F.SilkS,F.Fab,F.Cu,Dwgs.User -o out/$P-front.svg $P.kicad_pcb >/dev/null

echo "ERC: $(grep 'ERC messages' out/erc.rpt)"
grep -E '^\*\* Found' out/drc.rpt | sed 's/^/DRC: /'
