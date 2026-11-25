# 0021: Raster and audio packet formats

Status: Done (format defined; implementation in 0023/0024)
Opened: 2026-11-25

Define ADR 0005 section 8 (raster: frame/line numbers, geometry, sync positions, flags, encoding, UART fast-path history; audio later) before implementing capture and the host receiver.

## 2026-11-25

Defined in ADR 0005 section 8 (raster packet, 48-byte header + RGB888) and
the heartbeat video block (bytes 108..131). Audio deferred (section 9).

## 2026-11-25 open ambiguities (found by the dutctl-video sub-agent)

To resolve in ADR 0005 section 8 before/while implementing capture (0023):
1. v_active is not in the raster header but the completeness rule uses it:
   add it to the header (or derive from the heartbeat).
2. "Matching active_count": define as equal on every active line of a frame.
3. Vertical blanking before line 0 has no line number: define whether it is
   numbered as the tail of the previous frame, and whether `frame`
   increments at line 0 or at VSYNC.
4. Flag b4 "first line of frame": line 0 vs first line after VSYNC.
5. Flag b0 "VSYNC at first pixel": relative to first active pixel or to the
   start of the line incl. blanking.
6. RLE24: state that active_count is the decoded pixel count and that the
   common-header length = 40 + payload_bytes.
7. Flag b5 "lines dropped": set only on the next packet, or until frame end.
8. State explicitly that uart_rx_history is zero padded at the start.
9. Maximum datagram size: a 720 px line is 2208 bytes (> "about 2.2 kB");
   state the max and supported widths (dutctl uses 3120 for 1024 px).
10. Heartbeat length once capture exists (always 124?) and whether its
    h_total/v_total are the same measurement as in raster packets.
Status: Reopened (format defined, details above pending).
