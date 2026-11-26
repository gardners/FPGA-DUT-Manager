PY ?= python3

.PHONY: all clean nopng

# Regenerate every SVG/PNG/DXF/KiCad file and the fit report in out/
all:
	$(PY) build.py

# Same without the PNG renders (no inkscape needed)
nopng:
	$(PY) build.py --no-png

clean:
	rm -rf out
