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
