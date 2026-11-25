# 0024: dutctl video receiver

Status: Open
Opened: 2026-11-25

Receive raster packets, assemble frames, detect missing/duplicate lines, write PPM screenshots; Python reference encoder/decoder for raster packets and C unit tests on shared vectors.

## Progress 2026-11-25 (partial, session wrapped up early)

Done:
* `tests/netproto.py`: `T_RASTER`, `PORT_RASTER`, `RF_*` flag constants,
  `encode_raster` / `decode_raster` (ADR 0005 section 8, 48-byte header),
  `rle24_encode` / `rle24_decode`; `decode_heartbeat` returns the video block
  fields when the payload is >= 124 bytes (100-byte heartbeats still accepted);
  `encode_heartbeat` emits the block when `video_flags` is in the dict.
* `tests/gen_proto_vectors.py`: `heartbeat_video` (124-byte payload),
  `raster_active` (720 px, pixel x = (x&0xFF, (x>>8)^line, 3x&0xFF), 2208 bytes),
  `raster_blank` (VSYNC + dropped flags), `raster_rle` (320 px RLE24, 12 bytes).
* `sw/dutctl`: `DP_T_RASTER`, `dp_raster_t`, `dp_decode_raster`,
  `dp_raster_pixels` (raw + RLE24), heartbeat `has_video` + video fields,
  `DP_RASTER_MAX_PACKET` (48 + 3*1024). Vector tests in `tests/test_main.c`
  (`make -C sw/dutctl test`: 112 checks, 0 failures, ASan/UBSan).

Not done yet:
* Frame assembler (`src/rasterframe.c`, `include/rasterframe.h`) and its tests
  (complete, missing, duplicate, out-of-order, frame jump/wrap, lost first lines).
* `dutctl capture IP on|off` and `dutctl video IP [--frames N] [--out PREFIX]
  [--require-complete]` (bind 6504, SO_RCVBUF ~8 MB, PPM P6 output).
* Not tested against real FPGA output (capture path not yet available).

ADR 0005 section 8 ambiguities for the lead to settle:
1. `v_active` is not in the raster header, yet the receiver rule says "lines
   0 .. v_active-1". The receiver must infer it (count of b3 lines before the first
   blanking line, or the heartbeat video block). Suggest adding it to the header.
2. "matching active_count": matching what (first line, heartbeat `h_active`, or
   equal on all lines)?
3. Blanking before line 0 (vertical back porch) has no number: is it the tail of the
   previous frame (lines up to v_total-1)? "Frame start" (when `frame` increments:
   line 0 or VSYNC) is not defined.
4. b4 "first line of frame": always line 0 (first active line), or the first line
   after VSYNC (possibly a blanking line)?
5. b0 "VSYNC asserted at this line's first pixel": first active pixel (the origin
   used for hs_start) or the start of the line including blanking?
6. RLE24: `active_count` is assumed to be the decoded pixel count, and the common
   header `length` = 40 + payload_bytes exactly. Neither is stated.
7. b5 "lines were dropped before this one": only on the first packet after a drop,
   or sticky until the frame ends?
8. `uart_rx_history` with fewer than 16 bytes received: zero padded at the start
   (assumed, as in the UART snapshot), not stated outright.
9. Size: an active 720 px line is 2208 bytes, but `DP_MAX_PACKET` is 2200 and the ADR
   says "about 2.2 kB". 1024 px gives 3120 bytes. The ADR should state the maximum
   datagram size and supported widths.
10. Heartbeat video block: is the payload always 124 once the bitstream has capture,
    even with no source (fields zero)? Are h_total/v_total there the same
    measurement as in raster packets?

## 2026-11-25 frame assembler + dutctl video

* Raster format v1 (ADR 0005 s8) in Python/C codecs; unknown versions rejected.
* `rasterframe.[ch]`: emits a frame when lines 0..v_active-1 are all in
  (complete unless widths differ) or when a newer frame starts (incomplete);
  late packets of older frames (wrap-aware) and duplicates counted; missing
  lines black; PPM writer. Unit tests: out-of-order, missing, duplicate,
  dropped flag, late, width mismatch, frame-number wrap, flush (141 checks).
* `dutctl video IP [--frames N] [--out PREFIX] [--enable] [--require-complete]
  [--timeout S]` (UDP 6504, 8 MB receive buffer). Loopback-tested with a
  Python sender (complete / incomplete frames, PPM contents).
* Still to do: test against real FPGA capture (0022/0023).
