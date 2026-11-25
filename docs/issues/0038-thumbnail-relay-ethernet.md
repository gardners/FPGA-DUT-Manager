# 0038: Relaying thumbnails to the console (master) board over Ethernet

Status: Open
Opened: 2026-11-25 (owner + lead; split out of 0035)

0035 covers making and storing a board's own thumbnail. This issue covers
getting every board's thumbnails to the board whose console is selecting.
The board-to-board connectors stay reserved for full-rate video.

* Raw Ethernet frames (EtherType 0x88B5 local-experimental, version byte
  first), not IP.
* Request-driven: while its console shows the select screen, a board
  broadcasts a small request about every 250 ms. Boards that hear it
  stream their thumbnails for about 1 s, unicast to the requester's MAC.
  Bulk data never goes to a broadcast or multicast MAC.
* The resolution follows the number of connected sources (owner): the
  request carries the scale and rate, chosen by the master from how many
  machines it has seen. Default: 4 or fewer sources at 1/2 scale (320x200
  from the centre 640x400) at 30 Hz. More sources at 1/4 scale (160x100),
  matching the mosaic tile size, so bandwidth stays modest. At 1/2 scale
  that is about 31 Mb/s per source at RGB565; at 1/4 scale about 8 Mb/s.
* Several lines per jumbo frame (4 x 640 B at 1/2 scale).
* "Present, no source" frames about once a second while requested.
* A management key forces streaming to a given MAC. `dutctl thumbs`
  (AF_PACKET, needs CAP_NET_RAW) can also send requests itself, for host
  screenshots.

## 2026-11-25: owner decisions recorded, implementation (branch feature/thumbnails)

Owner decisions (via the coordinator): request/unicast design accepted (the
request is a small broadcast, the bulk stream unicast to the requester's
MAC, never a group MAC); scale follows the number of machines seen (<= 4:
1/2 = 320x200, else 1/4 = 160x100, divisor 2); RGB888 storage; wire
encodings RAW888 and RLE24 (as raster), RLE24 per line only when strictly
smaller; lines packed into frames until the next might not fit within
~8 KiB. Format: ADR 0005 section 10.

Implemented:
* `hdl/src/net/thumb_rx_tap.vhd` (clk_rx, beside the 2 KiB RX slots since
  relay frames are up to ~8 KiB): parses requests (-> requester MAC, scale,
  divisor to clk_sys), lines frames (LINE tags + RUN entries: one per
  RAW888 pixel or RLE24 tuple) and no-source frames, with its own FCS check;
  END good only if FCS, header and every line are complete.
* `hdl/src/net/thumb_rx_writer.vhd`: expands runs into xRGB32 words in the
  sender's hidden buffer; rows count only from good frames; a picture flips
  when its rows reach its height; this board's own machines are ignored.
* `hdl/src/net/thumb_tx.vhd`: policy (requests every 250 ms while the
  console is on the select screen; destination = forced MAC (key 0x0041)
  else the latest requester within 1 s; scale/divisor in effect for the
  local capture: own choice while selecting, else forced, else requested,
  else 1/2 and 2); sends every complete local picture (buffer locked
  against the capture writer), per line RLE24/RAW888, packed up to 8000
  payload bytes per frame; "present, no source" once a second for local
  machines without a picture in the last second. Latest-wins for
  requesters (several simultaneous requesters: the last one gets the
  stream).
* net_tx: relay frames and requests as new kinds below control traffic and
  above telemetry; raster keeps absolute priority. TX slots are now 8 KiB
  (eth_mac_tx LEN_W generic).
* Management key 0x0041 = MAC(6) scale(1) div(1); MAC 0 = off; group MACs
  rejected. Capabilities bit b7 = thumbnails.
* Host: `tests/netproto.py` (codec + the FPGA's packing), C codec
  (`dp_decode_thumb`, `dp_thumb_lines`, `dp_encode_thumb_request`) with
  vectors, `dutctl thumbs IFACE [--request] [--force IP]` (AF_PACKET,
  CAP_NET_RAW; writes PREFIX-mNN.ppm). The host NIC needs an MTU of ~8100
  for 1/2-scale RAW888 frames.
* Tests: `tb_thumb_rx` (+ scenario: RAW888/RLE24, both scales, bad FCS,
  foreign MAC, local machine, no-source, request), `tb_thumb_tx` (+
  scenario: every frame byte-for-byte against `netproto.thumb_packets`,
  budget split, no-source, requests, policy), system test.

## 2026-11-25: merged with foundation (DDR3, mosaic, InfoFrames), timing met

* Merged origin/feature/foundation twice (DDR3 0034 + mosaic 0036, then
  0037/0040). Thumbnail ports are DDR3 arbiter ports 2..4 (MEM_PORTS = 5);
  the mosaic's seen/fresh/cur_buf/scale come from thumb_status.
* Timing closure: mem_arbiter round robin rewritten as two fixed-priority
  encoders (the (last + k) mod N grant was 6 LUT levels at N = 5, into the
  mosaic); capture writer request registered; tap run checks one cycle
  after the push; thumb_tx registers line-buffer output and pixel; line
  size/encoding registered before the packing decision; net_rx/net_tx
  endpoint index replicated.
* Vivado build 6c2c91fd: **TIMING MET, WNS +0.192 ns, WHS +0.009 ns**;
  17822 LUTs (55 %), 32 BRAM tiles (43 %). `make test` green (28 HDL
  testbenches, 174 dutctl checks, 27 relay checks). Not loaded on hardware.

Hardware test plan (lead):
1. Load 6c2c91fd; `scripts/hwtest.sh` must stay green (thumbnails are
   off until requested or forced, raster unchanged). Heartbeat caps =
   0x9F.
2. Local: HDMI source on the video target, console on the select screen
   (key 0x0035 = 3 or hotkey): the mosaic tile of that machine should show
   the live picture (fresh), the other DUT colour bars or frown.
3. Host screenshots: host NIC MTU >= 8100 (`ip link set IF mtu 9000`), then
   `sudo dutctl thumbs IF --force BOARD_IP --pictures 3` -> thumb-mNN.ppm
   (centre 640x400 at 320x200); `--scale 2` -> 160x100. Check `--request`
   too (no key needed; stops ~1 s after the last request).
4. Two boards: the one selecting should show the other board's machines
   fresh within ~0.3 s (requests every 250 ms); watch a switch port
   counter: bulk frames go only to the requester's port.

## 2026-11-25 hardware (lead)

Merged into feature/foundation (fast-forward to cb5ca98). Build 6c2c91fd on the board: hwtest 63/0, capabilities 0x9F. The select screen (key 0x0035 = 3), captured over the HDMI self-loop, shows machine 1's live thumbnail (the select screen itself, recursively), colour bars for machine 0 (no source) and frowns for the empty slots: docs/images/select-screen-live-thumbnail.png. hwtest: bad-key probe moved from 0x0041 (now a real key) to 0x0042; the video check retries when its 1 s pixel-clock window covers a passthrough attempt. Not yet tried: `dutctl thumbs` (needs CAP_NET_RAW, no sudo here), a second board.
