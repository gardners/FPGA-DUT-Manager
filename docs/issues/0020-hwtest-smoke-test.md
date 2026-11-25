# 0020: Hardware smoke test script

Status: Open
Opened: 2026-11-25

scripts/hwtest.sh using dutctl against a running board (heartbeats, ping/ARP, text screen, management read-back, UART loopback with a jumper, JTAG refusal when unpowered). The dev laptop is on NATed Wi-Fi (192.168.188.x) and cannot see the board's 203.28.176.x broadcasts; needs a host on that segment or unicast telemetry (dest-ip) to a routable host.
