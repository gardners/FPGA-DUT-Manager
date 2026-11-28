#!/bin/sh
# JLCPCB fabrication package for the front-panel board (issue 0050).
# Reads the committed KiCad sources only (never writes them) and writes
# out/fab/:
#   drc.rpt, erc.rpt, drc-refilled.rpt (info)
#                                   checks on the current files (fails on any
#                                    DRC violation, unconnected pad, parity
#                                    issue or ERC error)
#   gerbers/ + mega-kvm-front-gerbers.zip
#                                    Gerbers (JLC's KiCad settings: Protel
#                                    extensions, no X2/netlist attributes,
#                                    mask subtracted from silk, 4.6 mm;
#                                    pours as saved and DRC-checked, not
#                                    refilled) + Excellon PTH/NPTH (mm,
#                                    decimal, absolute origin, alternate oval
#                                    mode); drill-map/ holds Gerber drill
#                                    maps for review (not in the zip)
#   mega-kvm-front-bom-jlc.csv, mega-kvm-front-cpl-jlc.csv
#                                    SMT parts that JLC places (recommended)
#   mega-kvm-front-bom-jlc-with-tht.csv, mega-kvm-front-cpl-jlc-with-tht.csv
#                                    the same plus the THT parts, for the
#                                    optional JLC through-hole assembly
#   mega-kvm-front-handfit.csv       parts not placed by JLC (default order)
#   fab-summary.txt                  board size, layers, holes, part counts
# KiCad 10 runs as a flatpak; override KICAD_CLI if it is native.
set -e
cd "$(dirname "$0")/.."
KICAD_CLI=${KICAD_CLI:-"flatpak run --command=kicad-cli org.kicad.KiCad"}
P=mega-kvm-front
F=out/fab
quiet() { "$@" 2>&1 | grep -v -i -e 'gtk-warning' -e '^$' || true; }

# README.md in out/fab is hand-written: only remove generated files
rm -rf $F/gerbers $F/drill-map $F/tmp $F/*.csv $F/*.rpt $F/*.zip $F/fab-summary.txt
mkdir -p $F/gerbers $F/tmp

# --- checks: ERC and DRC (with schematic parity) on the current sources
$KICAD_CLI sch erc --severity-all --exit-code-violations -o $F/erc.rpt $P.kicad_sch >/dev/null 2>&1 || true
$KICAD_CLI pcb drc --schematic-parity --severity-all \
    -o $F/drc.rpt $P.kicad_pcb >/dev/null 2>&1 || true
# Informational: DRC after a KiCad refill of the pours (what the GUI shows
# after pressing B). The Gerbers use the fills saved by tools/pcb_build.py,
# which drc.rpt checks; see README.md for the known difference.
$KICAD_CLI pcb drc --severity-all --refill-zones \
    -o $F/drc-refilled.rpt $P.kicad_pcb >/dev/null 2>&1 || true
echo "ERC: $(grep 'ERC messages' $F/erc.rpt)"
grep -E '^\*\* Found' $F/drc.rpt | sed 's/^/DRC: /'
grep -E '^\*\* Found [0-9]+ DRC' $F/drc-refilled.rpt | sed 's/^/DRC after refill (info): /'
if grep -E '^\*\* Found [1-9]' $F/drc.rpt >/dev/null; then
    echo "pcb-fab: DRC reports problems, see $F/drc.rpt" >&2; exit 1
fi
if ! grep -E 'ERC messages: [0-9]+ +Errors 0 ' $F/erc.rpt >/dev/null; then
    echo "pcb-fab: ERC reports errors, see $F/erc.rpt" >&2; exit 1
fi

# --- Gerbers and drill
LAYERS=F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts
quiet $KICAD_CLI pcb export gerbers -o $F/gerbers/ -l $LAYERS \
    --no-x2 --no-netlist --subtract-soldermask --precision 6 \
    $P.kicad_pcb
quiet $KICAD_CLI pcb export drill -o $F/gerbers/ --format excellon \
    --drill-origin absolute --excellon-units mm --excellon-zeros-format decimal \
    --excellon-oval-format alternate --excellon-separate-th \
    --generate-map --map-format gerberx2 $P.kicad_pcb
rm -f $F/gerbers/*.gbrjob
# Drill maps are for people, not for JLC's parser: keep them out of the zip
mkdir -p $F/drill-map && mv $F/gerbers/*-drl_map.gbr $F/drill-map/
(cd $F/gerbers && rm -f ../$P-gerbers.zip && zip -q -X ../$P-gerbers.zip *)

# --- BOM / CPL inputs: per-reference BOM, all and SMD-only placement
$KICAD_CLI sch export bom -o $F/tmp/bom-refs.csv \
    --fields 'Reference,Value,Footprint,LCSC,MPN,JLC,${DNP}' \
    --labels 'Reference,Value,Footprint,LCSC,MPN,JLC,DNP' \
    --group-by '' $P.kicad_sch >/dev/null 2>&1
$KICAD_CLI pcb export pos --format csv --units mm --side both --exclude-dnp \
    -o $F/tmp/pos-all.csv $P.kicad_pcb >/dev/null 2>&1
$KICAD_CLI pcb export pos --format csv --units mm --side both --exclude-dnp --smd-only \
    -o $F/tmp/pos-smd.csv $P.kicad_pcb >/dev/null 2>&1

python3 tools/jlc_fab.py $F $P
rm -rf $F/tmp
echo "pcb-fab: wrote $F"
