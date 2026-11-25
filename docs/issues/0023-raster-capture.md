# 0023: Raster capture path and raster-first TX scheduling

Status: Done (2026-11-25)
Opened: 2026-11-25

Pixel-domain async FIFO into a 16 KiB raster packet ring in clk_sys with complete-packet commit and overflow drop counting; raster packets have absolute priority at frame boundaries; capture enable per DUT (off by default). System test reconstructs a frame from captured packets.

## Progress 2026-11-25 (branch feature/raster-capture)

Owner/lead decision: host NIC eno2 runs MTU 9000, so raster format v1 stays
exactly as ADR 0005 s8 (one datagram per active line, jumbo); no splitting.
`MAX_LINE_PX` (raster_capture generic, default 1024 = ADR maximum) caps the
pixels stored per line / per datagram.

Built:

* `hdl/src/video/raster_pkg.vhd`, `hdl/src/video/raster_capture.vhd`:
  pixel-clock side learns sync polarities, numbers lines per ADR v1 (line 0
  = first DE line after a VSYNC, frame increments there; capture starts at
  the first line 0 after enable), measures hs_start/hs_end from the first
  active pixel, writes whole active lines into an 8192-pixel x 24-bit
  dual-clock BRAM ring (24 KiB) and commits a descriptor per line into a
  16-entry LUTRAM FIFO (Gray write pointer). A line is accepted only if the
  ring has room for MAX_LINE_PX and the FIFO has room, otherwise dropped
  whole; the count rides on the next committed line (flag b5, only there).
  Read pointers return to pclk by a held-bus req/ack handshake. Blanking
  lines are not sent.
* `net_tx`: K_RAST (type 0x60, port 6504, from the video-target DUT to its
  telemetry destination). Captured only when the video target is one of this
  board's DUTs, capture_en is set for it and it has an address; queued lines
  are discarded otherwise. Raster wins every frame boundary, except that a
  raster frame never follows a raster frame while other traffic waits (a
  source above ~1 Gb/s would otherwise starve heartbeats/ARP/JTAG; at 480p
  the raster uses ~57 % of the link and this never triggers). Header from a
  shift register (incl. uart_rx_seq + latest 16 RX bytes: uart_bridge got a
  `hist_latch` input that re-latches only the history pointers), pixels
  streamed from the ring as 24-bit words shifted out R, G, B. TX slots 2 ->
  4 KiB (8 KiB TX RAM, 13-bit MAC addresses). Heartbeat video block now
  carries frames_captured (line-0 packets sent) and raster_lines_dropped
  (board-wide); caps b4 set.
* Tests: `tb_raster_capture` (numbering, flags, hs positions, every pixel,
  overflow/drop accounting, disable/re-enable); `tb_supervisor_core` drives a
  720x8 (858x12) 27 MHz source, the scenario enables capture (key 0x0040),
  decodes every raster packet with `netproto.decode_raster`, checks fields,
  flags and UART history, rebuilds 7 complete frames and compares them byte
  for byte with the source. `make test` passes.
* Vivado (a7cf874): TIMING MET, WNS 0.166 ns. The fairness guard pushed
  WNS to +0.008 ns (ip_eff /= 0 compares in front of the selection chain);
  registering ep_ok / cap_on fixed it. Final (5cdf452): TIMING MET, WNS
  0.190 ns, WHS 0.024 ns (worst path now in net_rx); 9479 LUTs (was 8724),
  12286 FFs, 20.5 BRAM tiles (was 13.5: +6 RAMB36 pixel ring, +1 TX RAM).

To test on hardware: HDMI loopback (own 480p60 console into HDMI IN),
`dutctl video` with capture enabled on the video target; check heartbeat
raster_lines_dropped stays 0 and frames are complete.

## 2026-11-25 hardware (lead): capture works end to end

Merged into feature/foundation (1bd43fc). On the HDMI loopback (our 480p60
console -> HDMI IN): `dutctl video 203.28.176.87 --enable` received
complete 720x480 frames (480 lines, no duplicates) as jumbo datagrams
through the switch (host eno2 MTU 9000); text written with `dutctl text`
came back exactly (VGA red = (170,0,0)). Known-good 1bd43fca.

Safety item: telemetry defaults to broadcast, so enabling capture without
first setting dest-ip/dest-mac floods ~570 Mb/s of broadcast onto the
segment. To do: the FPGA must not send raster to a broadcast destination,
and scripts/hwtest.sh must set a unicast destination before its raster
check.

## 2026-11-25 closed

Raster capture merged; complete pixel-exact frames on the loopback; no raster to broadcast.
