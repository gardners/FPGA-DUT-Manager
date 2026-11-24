# 0010: m65: support Mimas A7 FT2232H (2a19:1009) for JTAG

Status: Open
Opened: 2026-11-25

Owner request: patch ../mega65-tools so m65/fpgajtag recognises the Mimas: VID/PID 2a19:1009, JTAG on FTDI interface B, DBUS6 OE_N low (init 0x08, dir 0x4B), UART on interface A for serial pairing. Work in a separate git worktree/branch — the owner has uncommitted WIP in fpgajtag.c, fpga.h, fpgajtag.h, m65.c.

## 2026-11-25 progress

Patched on local branch `mimas-a7-jtag` in a separate worktree
`~/Projects/mega65/mega65-tools-mimas` (commit a5becdd, based on HEAD 44c63d2;
the owner's uncommitted WIP in `~/Projects/mega65/mega65-tools` is untouched).
`bin/m65 -j` in that worktree finds the board: IDCODE 0362c093, selects
/dev/ttyUSB0 (channel A UART). Not pushed. Remaining: test bitstream load via
m65; USB serial string shows as "undefined" in m65's listing (cosmetic).
Owner: build with `make bin/m65` in the worktree and install as usual.
