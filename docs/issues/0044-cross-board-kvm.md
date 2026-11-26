# 0044: Keyboard and video for machines on another board

Status: Open (owner decided 2026-11-26: Ethernet, no frame buffer)
Opened: 2026-11-26 (from the owner's question "will chaining a 2nd board work now?")

## What works with two boards today

* Each board runs independently on the LAN: its own DIP-switch DUT IDs, DHCP,
  heartbeat, management, JTAG/XVC, UART, raster capture to the host and
  `dutctl` (discovery, video, screenshot, hwtest).
* Thumbnail relay (0038): the board whose select screen is up broadcasts a
  request; other boards unicast their thumbnails to it. So the select screen
  *should* show the other board's machines live. This has not been tried on
  two boards yet.

## What doesn't work

* Picking a machine on another board (hotkey digit, front-panel buttons, or a
  management target >= 2) does nothing. `supervisor_core` only accepts this
  board's two machines ("phase 1 has no chain").
* There's no path for the master's keyboard to reach a remote DUT, or for a
  remote DUT's picture to reach the master's HDMI OUT.
* The ribbon chain (ADR 0007, issue 0011) isn't implemented, and its pin plan
  no longer fits: the keyboard harnesses took rows 10-20 (ADR 0008
  amendment 4).

## Two ways to get there

**A. Over Ethernet (recommended).** Needs no new cables or pins.
* Keyboard: the master sends the keyboard snapshot (and the selection epoch)
  to the remote board in a small unicast raw frame about every 1 ms. The
  remote board feeds it to its kbd_mk1_device like a local keyboard. LED
  status comes back the same way.
* Video: the remote board streams the selected machine's full-rate rasters
  (the 0023 raster capture, RGB888 or RLE24, ~500 Mb/s raw for 720x480@60)
  unicast to the master. The master writes them into a DDR3 frame buffer
  (2 x 1.4 MB, double-buffered) and HDMI OUT scans out from DDR3. That adds
  up to one frame of latency, and the output is frame-locked to the
  master's clock (frame drop or repeat; GenLock 0039 later).
* Costs: one remote stream at a time fits a gigabit link (the switch must be
  gigabit and not shared with heavy traffic). This makes DDR3 part of the KVM
  path, which CLAUDE.md currently limits to thumbnails, so the owner needs to
  agree. Audio isn't carried, as with raster capture today.

**B. Ribbon chain (ADR 0007).** Lowest latency and no DDR3, but it needs 16
new header pins per direction, with clock-capable pins for the forwarded
clock. Only P13 rows 10-13 are free in the clock-capable region, and issue
0043 wants those for a second HDMI receiver. It also needs new cables.

## Plan (if A)

1. Two-board smoke test of what exists: thumbnails on the select screen,
   with no bulk frames on the switch's other ports (0038 step 4).
2. Make selection global: machine numbers beyond this board map to another
   board's (board, DUT); learn them from thumbnail and heartbeat traffic.
3. Remote keyboard frames, then remote video into a DDR3 frame buffer and
   HDMI OUT from DDR3. Add a hwtest with two boards.

## 2026-11-26 owner decision

Over **Ethernet**, with **no frame buffer**. The master starts streaming
the remote board's pixels to HDMI OUT using that board's relayed H and V
sync, so there is essentially no added delay. DDR3 stays thumbnail-only, as
CLAUDE.md says. Keyboard: snapshot every 1 ms, plus one immediately on any
key-state change.

Design notes (lead):
* **Video.** The remote board's raster capture sends one line per frame,
  unicast to the master: ~2.2 kB at 1 Gb/s = ~18 us on the wire, in a
  31.7 us line period at 480p. The master keeps a small line FIFO (2-4 lines
  of RGB888 = ~3 BRAM36) to absorb switch and queueing jitter (~0.1 ms total
  delay). HDMI OUT timing follows the stream: a frame starts when the remote
  frame's first line arrives; line and frame numbers in the raster header
  give the relayed sync.
* **Clock drift.** The remote source's pixel clock and the master's local
  27 MHz differ by up to ~100 ppm, or ~45 pixels per frame. Keep the FIFO
  centred by changing the last line of vertical blanking by a few pixels per
  frame (sinks tolerate this better than jitter on every line). Re-sync
  completely if the FIFO under- or overflows (one torn frame, logged in a
  counter). A source whose mode differs from the master's console mode
  switches HDMI OUT to that mode (same as passthrough 0032).
* **Bandwidth.** 720x480@60 RGB888 ~500 Mb/s (RLE24 often much less). One
  remote stream at a time: gigabit switch required. Keep it unicast (no
  raster bulk to broadcast, as with thumbnails).
* **Keyboard.** A raw frame (thumbnail-relay EtherType, new subtype) from
  the master to the remote board: selection epoch, target DUT, full key
  bitmap. Sent every 1 ms and at once on a change; stale epochs dropped. The
  remote board's kbd_arbiter treats it like a local physical keyboard. LED
  status comes back in the same frame type. With no frames for ~100 ms, the
  remote keyboard is released (all keys up).
* Audio could ride in the raster packets later.
