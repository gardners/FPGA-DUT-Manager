# Architecture Decision Records

Format: each ADR has Status (Proposed / Accepted / Superseded), Context, Decision,
Consequences. "Proposed" ADRs are being implemented on the assumption they will
be accepted (owner instruction 2026-11-25); refine rather than block.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-toolchain-and-build.md) | Open-source toolchain in `tools/`, Vivado-portable VHDL | Accepted |
| [0002](0002-hw-sw-boundary-and-phasing.md) | FPGA as router/UDP frame processor; phased delivery | Accepted |
| [0003](0003-board-baseline-mimas-a7-pre-v4.md) | Board baseline: pre-V4 Mimas A7 facts | Accepted |
| [0004](0004-clocking-and-ethernet.md) | Clocking and RGMII Ethernet | Proposed |
| [0005](0005-wire-protocol-v1.md) | UDP wire protocol v1 (ICD) | Proposed |
| [0006](0006-keyboard-mk1-presentation.md) | Keyboard: always present MK-I; MK-I + MK-II physical | Accepted |
| [0007](0007-chain-link.md) | Supervisor chain link: decoded video, 16 lanes, two 2x5 ribbons | Proposed |
| [0008](0008-connector-allocation.md) | Header P12/P13 allocation and cable families | Proposed |
| [0009](0009-power-relay-controller.md) | Relay controller protocol (Arduino, later Mimas GPIO) | Proposed |
| [0010](0010-jtag-over-udp.md) | JTAG engine and host XVC proxy | Proposed |
| [0011](0011-dut-identity-dip-and-dhcp.md) | DUT ID from DIP switches, deterministic MACs, DHCP | Accepted |
| [0012](0012-text-fallback-display.md) | 80x25 text fallback / server-driven display | Proposed |
| [0013](0013-ddr3-frame-store.md) | DDR3 frame store: MIG 7-series behind mem_pkg, self-test, heartbeat status | Proposed |
| [0014](0014-keyboard-type3-async.md) | Keyboard type 3 (async 2 Mb/s UART, auto-baud CPLD at 24.18 MHz) and keyboard CPLD JTAG | Proposed |
