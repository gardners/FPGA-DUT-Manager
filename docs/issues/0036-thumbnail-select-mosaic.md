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
