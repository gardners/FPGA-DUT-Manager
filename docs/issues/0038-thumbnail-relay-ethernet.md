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
