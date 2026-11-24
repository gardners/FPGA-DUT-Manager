# 0004: RGMII RX skew implementation under openXC7

Status: Open
Opened: 2026-11-25

ADR 0004 prefers IDELAYE2 fixed delay on RXD/RX_CTL (RXDLY strap off). Check nextpnr-himbaechel xilinx support for IDELAYE2/IDELAYCTRL; else use MMCM +90° on RXC. Validate with ping + iperf-style UDP flood and FCS error counters.
