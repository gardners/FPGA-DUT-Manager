# 0019: Timing closure (Vivado)

Status: In progress
Opened: 2026-11-25

First Vivado build: clk_sys WNS -5.233 ns (2537 endpoints; worst: net_tx widx -> mem_data, 20 logic levels through the hdr/pf byte mux and DHCP byte function), rgmii_rxc WHS -2.007 ns on the 5 IDDR inputs (BUFG insertion delay vs IDELAY), text RAMs mapped to LUTRAM. Plan (owner agreed): net_tx emits a byte per cycle from a loaded shift register (no wide muxes), net_rx parse split into registered stages, RGMII RX clock via MMCM (+90 deg, delay compensated) instead of BUFG+IDELAY, RGMII TX generated clock + output delays, ram_style block for text memories. Done when timing_verdict.txt says MET.
