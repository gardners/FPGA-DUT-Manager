# MEGA-KVM shield + keyboard sub-board: regenerate schematics/boards from
# scripts/design.py and scripts/geometry.py, run ERC/DRC, export into out/
# and kbd-sub/out/.
KICAD_CLI ?= flatpak run --command=kicad-cli org.kicad.KiCad
KICAD_PY  ?= flatpak run --command=python3 org.kicad.KiCad
PRJ = mega-kvm-shield
KBD = kbd-sub/mega-kvm-kbdsub

.PHONY: all sch pcb erc drc export clean
all: sch pcb erc drc export

sch:
	cd scripts && python3 gen_fp.py && python3 gen_sch.py

pcb: sch
	cd scripts && $(KICAD_PY) gen_pcb.py && $(KICAD_PY) gen_kbd_pcb.py

erc:
	$(KICAD_CLI) sch erc --severity-all -o out/erc.rpt $(PRJ).kicad_sch | grep Found || true
	$(KICAD_CLI) sch erc --severity-all -o kbd-sub/out/erc.rpt $(KBD).kicad_sch | grep Found || true

drc:
	$(KICAD_CLI) pcb drc --severity-all -o out/drc.rpt $(PRJ).kicad_pcb | grep Found || true
	$(KICAD_CLI) pcb drc --severity-all -o kbd-sub/out/drc.rpt $(KBD).kicad_pcb | grep Found || true

export:
	$(KICAD_CLI) sch export pdf -o out/$(PRJ)-schematic.pdf $(PRJ).kicad_sch
	$(KICAD_CLI) sch export pdf -o kbd-sub/out/mega-kvm-kbdsub-schematic.pdf $(KBD).kicad_sch
	$(KICAD_CLI) pcb export svg --mode-single --fit-page-to-board --exclude-drawing-sheet \
	  -l Edge.Cuts,F.SilkS,F.Fab,F.Cu,B.Fab,User.Drawings -o out/$(PRJ)-top.svg $(PRJ).kicad_pcb
	$(KICAD_CLI) pcb render --side top --quality basic -w 1600 -h 2400 -o out/$(PRJ)-top.png $(PRJ).kicad_pcb
	$(KICAD_CLI) pcb render --side bottom --quality basic -w 1600 -h 2400 -o out/$(PRJ)-bottom.png $(PRJ).kicad_pcb
	$(KICAD_CLI) pcb render --side top --rotate '-50,0,-30' --quality basic -w 2400 -h 1600 -o out/$(PRJ)-3d.png $(PRJ).kicad_pcb
	$(KICAD_CLI) pcb render --side top --quality basic -w 1200 -h 1600 -o kbd-sub/out/mega-kvm-kbdsub-top.png $(KBD).kicad_pcb
	$(KICAD_CLI) pcb render --side top --rotate '-50,0,-30' --quality basic -w 1600 -h 1200 -o kbd-sub/out/mega-kvm-kbdsub-3d.png $(KBD).kicad_pcb

clean:
	rm -f out/*.rpt out/*.pdf out/*.svg out/*.png kbd-sub/out/*.rpt kbd-sub/out/*.pdf kbd-sub/out/*.png
