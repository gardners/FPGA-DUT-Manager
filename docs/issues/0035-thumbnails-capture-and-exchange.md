# 0035: Quarter-resolution thumbnails: local capture and exchange between boards

Status: Open
Opened: 2026-11-25 (owner request)

Keep the most recent quarter-resolution frame (360x240 from 720x480,
2x2 decimated, RGB565) of every video source in the DDR3 frame store
(0034; layout in `mem_pkg.vhd`, double-buffered per machine number 0..31),
and exchange them between FPGA boards so the console board can show all
machines (0036).

* Local: decimate the HDMI IN pixel stream (pixel-clock side, CDC to
  clk_sys), write it into the buffer of the machine the capture belongs to,
  and flip to the new buffer only when a whole frame has been written.
* Network: a new thumbnail datagram kind (ADR 0005 plus the usual
  protocol-change files): one line per datagram (720 bytes of pixels plus a
  header with version, machine number, frame, row, source-present flag), so
  it fits a standard 1500 MTU. It is sent at a limited rate (default about
  4 frames/s) to a thumbnail destination set by a management key
  (default off). The destination must be unicast; never broadcast or
  multicast, as with raster. With no video source, the board sends a
  small "machine present, no source" datagram about once a second, so
  peers still learn the machine exists.
* Receive: received thumbnail lines are written into the sender's machine
  buffer. Per-machine status goes to the display (0036): seen (any datagram
  in the last 3 s), fresh (a complete frame in the last 2 s) and the
  current buffer.
* Host: `dutctl thumbs` receives the same datagrams and writes PPM files,
  giving cheap screenshots of every machine.

## 2026-11-25: design changes (owner + lead) and implementation (branch feature/thumbnails)

Design changes adopted during the work (coordinator messages):
* Content: centre 640x400 of the active picture (x offset (h_active-640)/2,
  y offset (v_active-400)/2 = 40 at 480p, 88 at 576p), 2x2-box averaged to
  320x200 (or 4x4 to 160x100 when the relay asks for 1/4 scale, 0038),
  every `div`-th frame (2 = 30 Hz). Stored RGB888 as xRGB32 (mem_pkg
  baf5ebf: 4 pixels per word, 128-word rows, 512 KiB buffers).
* The network part moved to issue 0038 (raw Ethernet relay). This issue is
  local capture, frame store and per-machine status.

Implemented:
* `hdl/src/video/thumb_capture.vhd`: pixel-clock box filter (horizontal
  sums + a BRAM line buffer of vertical partial sums, 12 bits per channel),
  crop offsets measured from the previous line/frame (y offset adopted only
  when two frames have the same line count), dual-clock FIFO
  (`common/async_fifo_bram.vhd`) of START / WORD(row, word, 4 pixels) / END
  (rows, ok); a tile row is produced only if the FIFO has room for all of
  it, else the frame is marked bad. clk_sys writer: at START the frame goes
  to `not cur(machine)` (its own copy of the buffer it just completed, since
  START follows END before thumb_status updates), or is skipped if thumb_tx
  is reading that buffer; at END of a good frame `done` flips the buffer.
* `hdl/src/video/thumb_status.vhd`: per machine 0..31, 100 ms ticks.
* supervisor_core: capture enabled while the video target is one of this
  board's DUTs and its video decodes; machine = m0/m1 of that DUT.
* Tests: `tb_thumb_capture` (every pixel vs. the box average at both
  scales, divisor, lock, disable, memory stalls), system test
  `tb_supervisor_core` (pictures relayed to the host equal the box-filtered
  testbench picture).

Status ports for the mosaic (0036), clk_sys, bit m = machine m
(`supervisor_core` ports `thumb_seen/thumb_fresh/thumb_cur/thumb_quarter`,
wired in `mimas_a7_top` to the mosaic's `seen/fresh/cur_buf/scale`):
* `thumb_seen(m)`: a local machine of this board, or a relay frame (lines
  or "present, no source") for m in the last 3 s. The top ORs in
  `con_slots`.
* `thumb_fresh(m)`: a complete picture of m stored in the last 2 s.
* `thumb_cur(m)`: buffer (thumb_addr `buf`) holding m's latest complete
  picture; the other one is being written. A reader may see one torn
  frame if a new picture completes while it reads the old buffer and the
  next one starts into it.
* `thumb_quarter(m)`: '1' = that picture is 160x100 (40 words of rows
  0..99), '0' = 320x200 (80 words of rows 0..199). Pictures from sources
  with fewer than 400 lines have fewer rows; the rest of the buffer is
  stale.
* Frame-store ports: DDR3 arbiter ports 2 (capture writer), 3 (relay
  receive writer), 4 (relay sender reader).
