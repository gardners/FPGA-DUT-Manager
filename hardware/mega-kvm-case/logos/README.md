# Logos etched by the case generator

| File | Source |
|---|---|
| `mega65.svg` | `assets/mega65.svg` (owner); the generator keeps only the dark pill (`#3b3b3b`). |
| `mega-ev.svg` | M.E.G.A. e.V. (Museum of Electronic Games & Art) logo, rebuilt as vectors by `tools/make_mega_ev_logo.py` from `src/mlogo.png`. |
| `src/mlogo.png` | https://www.m-e-g-a.org/wp-content/uploads/2012/06/mlogo.png, downloaded 2026-11-27 (owner round 13). 4093 bytes, a real PNG (200 x 52 px, 8-bit palette with transparency). |

`mega-ev.svg` is not a pixel trace: the 25 x 5 block grid is read from the
PNG and drawn as ideal squares (5.75 px on an 8 px pitch), and the line
"MUSEUM OF ELECTRONIC GAMES & ART" is set in the generator's own stroke font
at the original size, stroked 1 px and converted to unioned filled outlines
by Inkscape. Colours (black / maroon `#680040`) follow the original; the case
generator etches every fill black. Regenerate with
`python3 -I tools/make_mega_ev_logo.py` (Pillow + Inkscape).

These logos are the property of their respective owners; see `assets/COPYRIGHT.md`.
