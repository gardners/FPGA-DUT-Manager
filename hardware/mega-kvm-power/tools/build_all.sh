#!/bin/sh
# Regenerate both power-board projects and their outputs:
#   schematics (Python generators) -> ERC -> boards (pcbnew Python) -> DRC
#   (with schematic parity) -> schematic PDFs, 3D board renders (PNG), BOM CSV.
# KiCad 10 runs as a flatpak; override KICAD_CLI / KICAD_PY if it is native.
set -e
cd "$(dirname "$0")/.."
KICAD_CLI=${KICAD_CLI:-"flatpak run --command=kicad-cli org.kicad.KiCad"}
KICAD_PY=${KICAD_PY:-"flatpak run --command=python3 org.kicad.KiCad"}
mkdir -p out

python3 tools/gen_footprints.py
python3 tools/gen_main.py
python3 tools/gen_inputs.py
python3 tools/gen_inputs_lm74700.py
$KICAD_PY tools/pcb_build.py main inputs 2>&1 | grep -v -i 'gtk-warning' || true

for b in main inputs; do
    p=mega-kvm-power-$b
    $KICAD_CLI sch erc --severity-all -o out/$b-erc.rpt $p/$p.kicad_sch >/dev/null
    $KICAD_CLI pcb drc --schematic-parity --severity-all -o out/$b-drc.rpt $p/$p.kicad_pcb >/dev/null || true
    $KICAD_CLI sch export pdf -o out/$p-schematic.pdf $p/$p.kicad_sch >/dev/null
    $KICAD_CLI sch export bom -o out/$p-bom.csv \
        --fields 'Reference,Value,Footprint,LCSC,MPN,${QUANTITY},${DNP}' \
        --labels 'Refs,Value,Footprint,LCSC,MPN,Qty,DNP' \
        --group-by 'Value,Footprint,LCSC,${DNP}' --ref-range-delimiter '' $p/$p.kicad_sch >/dev/null
    # CPL (pick and place) for JLC: board coordinates in mm, DNP excluded.
    # Placement only: the boards are unrouted, so this is for review/costing.
    $KICAD_CLI pcb export pos --format csv --units mm --side both --exclude-dnp \
        -o out/$p-cpl.csv $p/$p.kicad_pcb >/dev/null
    $KICAD_CLI pcb render --side top --width 1600 --height 900 -o out/$p-top.png $p/$p.kicad_pcb >/dev/null 2>&1 || true
    $KICAD_CLI pcb render --side bottom --width 1600 --height 900 -o out/$p-bottom.png $p/$p.kicad_pcb >/dev/null 2>&1 || true
    echo "$b: $(grep 'ERC messages' out/$b-erc.rpt)"
    grep -E '^\*\* Found' out/$b-drc.rpt | sed "s/^/$b: /"
done

# fallback input board (JLC-stocked LM74700 variant): schematic only
p=mega-kvm-power-inputs-lm74700
$KICAD_CLI sch erc --severity-all -o out/inputs-lm74700-erc.rpt $p/$p.kicad_sch >/dev/null
$KICAD_CLI sch export pdf -o out/$p-schematic.pdf $p/$p.kicad_sch >/dev/null
$KICAD_CLI sch export bom -o out/$p-bom.csv \
    --fields 'Reference,Value,Footprint,LCSC,MPN,${QUANTITY},${DNP}' \
    --labels 'Refs,Value,Footprint,LCSC,MPN,Qty,DNP' \
    --group-by 'Value,Footprint,LCSC,${DNP}' --ref-range-delimiter '' $p/$p.kicad_sch >/dev/null
echo "inputs-lm74700: $(grep 'ERC messages' out/inputs-lm74700-erc.rpt)"
