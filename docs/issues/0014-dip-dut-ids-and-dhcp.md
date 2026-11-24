# 0014: DIP-switch DUT IDs, deterministic MACs and DHCP client

Status: In progress
Opened: 2026-11-25

Implement ADR 0011: DIP[3:0]/DIP[7:4] DUT IDs, MAC 02:4D:36:35:00:<id>, DHCP client per endpoint (reuse hardweb dhcp_seq/dhcp_tx), fallback 192.168.65.(16+id) after 10 s, K_DHCP_EN key, id-conflict flag, heartbeat address-source field. Verify DIP switch bit order/polarity on hardware.

## 2026-11-25 progress

Implemented: `dhcp_client` (per endpoint), DHCP reply parsing with option
scan in `net_rx`, 300-byte DISCOVER/REQUEST builder in `net_tx` (options 53,
61, 12 `m65dutNN`, 50/54, 55; broadcast flag), DIP-derived MAC/fallback IP,
DUT ID conflict disabling the P13 half, `K_DHCP_EN`, heartbeat addr_src and
dut_id. System test: DUT0 leases 10.65.0.50 via OFFER/ACK, its fallback
address is then not answered; DUT1 falls back to 192.168.65.17 after the
(shortened) timeout. Remaining: hardware test against a real DHCP server,
DIP bit order/polarity check, lease expiry/NAK unit test.
