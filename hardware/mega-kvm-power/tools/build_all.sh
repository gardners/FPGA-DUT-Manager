#!/bin/sh
# Regenerate the power board (one board since 0047 owner round 12) and its
# outputs: schematic (Python generator) -> ERC -> board (pcbnew Python) -> DRC
# (with schematic parity) -> schematic PDF, BOM and CPL CSVs, 3D renders (PNG).
#
# The separate input boards (mega-kvm-power-inputs, -inputs-lm74700) are
# legacy and no longer built; LEGACY=1 tools/build_all.sh rebuilds them too.
# KiCad 10 runs as a flatpak; override KICAD_CLI / KICAD_PY if it is native.
set -e
cd "$(dirname "$0")/.."
KICAD_CLI=${KICAD_CLI:-"flatpak run --command=kicad-cli org.kicad.KiCad"}
KICAD_PY=${KICAD_PY:-"flatpak run --command=python3 org.kicad.KiCad"}
mkdir -p out

BOARDS=main
python3 tools/gen_footprints.py
python3 tools/gen_main.py
if [ -n "$LEGACY" ]; then
    python3 tools/gen_inputs.py
    python3 tools/gen_inputs_lm74700.py
    BOARDS="main inputs"
fi
$KICAD_PY tools/pcb_build.py $BOARDS 2>&1 | grep -v -i 'gtk-warning' || true

for b in $BOARDS; do
    p=mega-kvm-power-$b
    $KICAD_CLI sch erc --severity-all -o out/$b-erc.rpt $p/$p.kicad_sch >/dev/null
    $KICAD_CLI pcb drc --schematic-parity --severity-all -o out/$b-drc.rpt $p/$p.kicad_pcb >/dev/null || true
    $KICAD_CLI sch export pdf -o out/$p-schematic.pdf $p/$p.kicad_sch >/dev/null
    $KICAD_CLI sch export bom -o out/$p-bom.csv \
        --fields 'Reference,Value,Footprint,LCSC,MPN,${QUANTITY},${DNP}' \
        --labels 'Refs,Value,Footprint,LCSC,MPN,Qty,DNP' \
        --group-by 'Value,Footprint,LCSC,${DNP}' --ref-range-delimiter '' $p/$p.kicad_sch >/dev/null
    # CPL (pick and place) for JLC: board coordinates in mm, DNP excluded.
    # Placement only: the board is unrouted, so this is for review/costing.
    $KICAD_CLI pcb export pos --format csv --units mm --side both --exclude-dnp \
        -o out/$p-cpl.csv $p/$p.kicad_pcb >/dev/null
    $KICAD_CLI pcb render --side top --width 1600 --height 1000 -o out/$p-top.png $p/$p.kicad_pcb >/dev/null 2>&1 || true
    $KICAD_CLI pcb render --side bottom --width 1600 --height 1000 -o out/$p-bottom.png $p/$p.kicad_pcb >/dev/null 2>&1 || true
    echo "$b: $(grep 'ERC messages' out/$b-erc.rpt)"
    grep -E '^\*\* Found' out/$b-drc.rpt | sed "s/^/$b: /"
done

if [ -n "$LEGACY" ]; then
    p=mega-kvm-power-inputs-lm74700
    $KICAD_CLI sch erc --severity-all -o out/inputs-lm74700-erc.rpt $p/$p.kicad_sch >/dev/null
    $KICAD_CLI sch export pdf -o out/$p-schematic.pdf $p/$p.kicad_sch >/dev/null
    echo "inputs-lm74700: $(grep 'ERC messages' out/inputs-lm74700-erc.rpt)"
fi
