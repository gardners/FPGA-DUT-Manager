# 0039: GenLock: synchronise sources' frames for buffer-free compositing

Status: Deferred (future note; owner 2026-11-25)
Opened: 2026-11-25

Goal: help video sources (MEGA65s, HewnWeb boards) align their frame timing
to a reference, so that a later compositor can mix live streams in real
time without frame buffers. Nothing to implement yet; this records the
idea and the options.

Possible carriers:
* Ethernet: a "magic" raw frame (e.g. the 0x88B5 EtherType of 0038 with a
  genlock subtype) carrying the reference frame/line phase and rate: frame
  number, the line and pixel at a timestamp, and the pixel-clock ratio.
  Precision could come from timestamping at the MAC (IEEE 1588/PTP-style)
  or simply from sending at a fixed point in the reference frame, so the
  arrival marks the phase, with jitter of a few microseconds. That is
  enough for coarse lock: line or frame alignment plus slow clock trimming.
* HDMI reverse direction (sink to source), if anything fits:
  - CEC: very slow (about 400 bit/s), so usable for set-up messages, not
    timing.
  - DDC/SCDC: the source polls the sink, so it is not a timing signal.
  - HEAC (HDMI Ethernet and Audio Return Channel): uncommon in sources.
  - HPD: could in principle carry a pulse, but sources react to it by
    re-reading the EDID.
  None is a standard genlock; Ethernet looks the most practical.
* The source side then needs a way to slip or trim its video timing: a
  fractional MMCM/PLL adjustment, or adding or removing blanking
  lines/pixels. For the MEGA65 that is a mega65-core change.
