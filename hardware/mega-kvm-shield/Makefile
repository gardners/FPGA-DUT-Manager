# MEGA-KVM shield: regenerate schematic/board from scripts/design.py,
# run ERC/DRC and export documentation into out/.
KICAD_CLI ?= flatpak run --command=kicad-cli org.kicad.KiCad
KICAD_PY  ?= flatpak run --command=python3 org.kicad.KiCad
PRJ = mega-kvm-shield

.PHONY: all sch pcb erc drc export clean
all: sch pcb erc drc export

sch:
	cd scripts && python3 gen_sch.py

pcb: sch
	cd scripts && $(KICAD_PY) gen_pcb.py

erc:
	$(KICAD_CLI) sch erc --severity-all --exit-code-violations -o out/erc.rpt $(PRJ).kicad_sch || true
	@grep -E "^\*\* ERC messages|^\*\* Found" out/erc.rpt || true

drc:
	$(KICAD_CLI) pcb drc --severity-all -o out/drc.rpt $(PRJ).kicad_pcb || true
	@grep -E "^\*\* Found" out/drc.rpt || true

export:
	$(KICAD_CLI) sch export pdf -o out/$(PRJ)-schematic.pdf $(PRJ).kicad_sch
	$(KICAD_CLI) pcb export svg --mode-single --fit-page-to-board --exclude-drawing-sheet \
	  -l Edge.Cuts,F.SilkS,F.Fab,F.Cu,B.Fab,User.Drawings -o out/$(PRJ)-top.svg $(PRJ).kicad_pcb
	$(KICAD_CLI) pcb render --side top --quality basic -w 2400 -h 1600 -o out/$(PRJ)-top.png $(PRJ).kicad_pcb
	$(KICAD_CLI) pcb render --side bottom --quality basic -w 2400 -h 1600 -o out/$(PRJ)-bottom.png $(PRJ).kicad_pcb
	$(KICAD_CLI) pcb render --side top --rotate '-50,0,-30' --quality basic -w 2400 -h 1600 -o out/$(PRJ)-3d.png $(PRJ).kicad_pcb

clean:
	rm -f out/*.rpt out/*.pdf out/*.svg out/*.png
