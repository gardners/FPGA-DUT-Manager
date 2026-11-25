# 0007: Stable board identity

Status: Done (2026-11-25)
Opened: 2026-11-25

Use DNA_PORT 57-bit device DNA as board ID if openXC7 supports DNA_PORT; else DIP switches. DIP[3:0] also sets default node number for default IPs (ADR 0005).

## 2026-11-25

Vivado is the default flow, so DNA_PORT is used: `platform/xc7/dna_xc7.vhd`
reads the 57-bit DNA once after configuration (DNA_PORT clocked at
clk_sys/16; bit 56 first), behavioural model + tb_dna_xc7. Heartbeat
`board_dna` now carries it (was a DIP placeholder). MACs stay DIP-derived
(ADR 0011); DNA identifies the supervisor board and gates broadcast
SET_IDENTITY. Hardware check: two boards must report different DNAs.

## 2026-11-25 closed

DNA_PORT reader (dna_xc7) in known-good builds; heartbeat board_dna = 00124c296998c854 on the build-box board.
