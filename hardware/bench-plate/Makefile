PY ?= python3

.PHONY: all nopng clean

# Regenerate out/*.svg, the preview PNGs and out/layout.md
all:
	$(PY) build.py

# Same without the PNG previews (no inkscape needed)
nopng:
	$(PY) build.py --no-png

clean:
	rm -rf out
