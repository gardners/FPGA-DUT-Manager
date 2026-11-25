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
