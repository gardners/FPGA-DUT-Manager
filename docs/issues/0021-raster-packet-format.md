# 0021: Raster and audio packet formats

Status: Done (format defined; implementation in 0023/0024)
Opened: 2026-11-25

Define ADR 0005 section 8 (raster: frame/line numbers, geometry, sync positions, flags, encoding, UART fast-path history; audio later) before implementing capture and the host receiver.

## 2026-11-25

Defined in ADR 0005 section 8 (raster packet, 48-byte header + RGB888) and
the heartbeat video block (bytes 108..131). Audio deferred (section 9).
