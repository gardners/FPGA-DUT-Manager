# 0014: DIP-switch DUT IDs, deterministic MACs and DHCP client

Status: In progress
Opened: 2026-11-25

Implement ADR 0011: DIP[3:0]/DIP[7:4] DUT IDs, MAC 02:4D:36:35:00:<id>, DHCP client per endpoint (reuse hardweb dhcp_seq/dhcp_tx), fallback 192.168.65.(16+id) after 10 s, K_DHCP_EN key, id-conflict flag, heartbeat address-source field. Verify DIP switch bit order/polarity on hardware.
