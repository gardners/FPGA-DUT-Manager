# 0018: 100 Mb/s Ethernet support (low priority)

Status: Open — not a priority (owner 2026-11-25: assume gigabit; 100M only
for the "MEGA65 as server" corner case)
Opened: 2026-11-25

The pre-V4 Mimas RTL8211E negotiates 10/100/1000. Gigabit is assumed. If 100M
is ever needed:

* RX: detect speed (RXC frequency count or RGMII in-band status), assemble
  SDR nibbles at 25 MHz into bytes with a byte-enable into `eth_mac_rx`.
* TX: 25 MHz TXC and nibble output; MAC TX with byte strobes.
* Refuse 10M: do not advertise 10BASE-T (MDIO write to reg 4), report
  `link_not_1000` / speed in heartbeat.
* Video at 100M: still try with RLE24 (ADR/brief section 9); enlarge the
  raster TX ring if BRAM allows; later use DDR3 to hold a whole frame and
  send it out slowly frame-at-a-time.
