# 0036: Live-thumbnail selection screen (mosaic composited with the text console)

Status: Open
Opened: 2026-11-25 (owner request)

The select screen (0029) shows the latest thumbnail (0035) of each
selectable machine instead of plain boxes. Each tile carries its selection
digit (1-9, then 0) in a reverse-video box in the corner, in the
machine's LED colour.

* Composite: the text console stays the top layer. Text pixels of pure
  green (0x00FF00) are transparent and show the thumbnail layer beneath.
  The mosaic is read from DDR3 through a `mem_pkg` port into line buffers
  in the console pixel domain.
* Layouts: 2x2 tiles of 360x240 (full 720x480) when only 4 slots are in
  use; otherwise the thumbnails are shrunk a further 2x (180x120) to
  show 8 or more. The owner asked for "4 or 8". With 10 selectable slots,
  the default is 4x3 tiles of 180x120, of which 10 are used, plus text
  rows.
* A machine that is seen but has had no fresh frame for over 2 s shows
  procedurally generated colour bars. An empty slot keeps the frown.
* If DDR3 is not calibrated, it falls back to the current boxes-only
  select screen.

## 2026-11-25 design changes (lead/owner, recorded here)

* Thumbnails are 320x200 RGB888 (xRGB32, 4 px per 16-byte word, 2 KiB
  rows), cut from the centre 640x400 of the source (mem_pkg baf5ebf).
* Layouts: 2x2 of 320x200 = 640x400 block, 4x3 of 160x100 = 640x300 block,
  both centred on 720x480.
* Issue 0038: the stored scale depends on the number of sources: with more
  than 4 machines the slots already hold 160x100 tiles (rows 0-99, 40
  words), read 1:1 (no decimation). Per-machine `scale` input ('1' =
  quarter); a tile whose stored scale does not match the current layout
  shows colour bars instead of a garbled image.

## 2026-11-25 implemented (simulation + Vivado), branch feature/mosaic

* `hdl/src/video/mosaic_pkg.vhd`: geometry (2x2 block at (40,40), 4x3 at
  (40,90)), tile modes, key colour, corner-box cell functions.
* `hdl/src/video/mosaic_display.vhd`: mem_pkg read port on clk_sys; at x=0
  of line y the pixel side requests line y+1 (toggle + stable line number);
  the reader writes that half's line info (tile modes, layout) and reads 80
  words (2 x 80 or 4 x 40, only for thumbnail tiles) into a 2 x 160 x 128-bit
  line buffer (2 BRAM36); the pixel side latches the line info at x=800 and
  renders with a 4-clock latency. Per-frame state (layout, modes, buffers,
  enable) is latched at the request for line 480, so a frame never tears
  between buffers or layouts. An unfinished fetch is abandoned when the
  next request arrives (late responses dropped). Machine k: fresh and scale
  matches -> thumbnail (cur_buf(k)); else seen(k) or slots(k) -> 75% colour
  bars; else frown (8x scaled 0x7F glyph, grey on dark grey). Layout 2x2
  when no machine 4..9 is in use. Machines 10/11 tiles are black.
* `text_display`: new ports mos_on/mos_quad/mos_r/g/b. Live select screen
  (mos_on and screen 2): a 3-cell reverse-video box (digit or frown) in the
  LED colour in the first text cell fully inside each tile's top-left
  corner; all other cells have key-green background (screen-2 palette
  entry 8, was an unused grey); RAM text only on rows 1 (title), 23 (hint),
  24 (footer) in 4x3, none in 2x2 (the 640x400 block covers the whole
  400-line text area, so "text rows above and below" are not possible with
  TOP=40). Output pixels of exactly 0x00FF00 and pixels outside the text
  area show the mosaic. LED green is now 0x00FE00 so machine 3's box is
  never keyed (tb_text_screens expectation updated).
* Without mos_on (ddr_ok = '0') the boxes-only screen is unchanged.
* Top level: ddr_ok tied '0', seen = con_slots, fresh/cur_buf/scale '0',
  mem port unconnected (MEM_RSP_IDLE). Generic `MOSAIC_DEMO=1` (bring-up
  without DDR3): ddr_ok '1', machines 0-9 seen, even ones fresh at quarter
  scale, a generated pattern "memory" (R = machine*24 + buf*12, G = 2*row,
  B = column) -> 4x3 with gradient tiles for 0,2,4,6,8 and bars for the odd
  ones.
* `tb_mosaic` (mem_model, latency 20, stalls): 4x3, 2x2 and fallback, whole
  frames captured; every pixel of four thumbnail tiles is checked. Note: the
  text pipeline's RGB/DE come out 5 clk_pix edges after x/y (sampled before
  the edge); tb_text_screens samples after the edge with xd(3), same thing.
* `scripts/run-hdl-tests.sh` passes `-H ${NVC_HEAP:-512m}` (mem_model
  needs more than nvc's 16 MiB default heap).
