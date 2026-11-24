# ADR 0003: Board baseline — pre-V4 Mimas A7 facts

Status: Accepted (2026-11-25); items marked *verify* are tracked in issues.

## Facts established

Sources: attached board's USB descriptors; Numato user guide (header tables,
FT2232H usage); Numato openocd `numato_mimasa7.cfg`; vendor XDCs for V2.0 and
V3.0 (copied to `boards/mimas_a7/vendor/`); schematics `MimasA7.pdf` (V2) and
`MimasA7_V3.1_Sch.pdf`; prjxray-db `package_pins.csv`.

* FPGA XC7A50T-1FGG484C (guide). *verify* IDCODE 0x0362C093 via `make detect`.
* USB: FT2232H with Numato VID:PID 2a19:1009 (bcdDevice 7.00, two vendor
  interfaces). **Channel A (USB interface 0) = user UART** (FPGA Y21/Y22 in
  serial mode; full 245-FIFO pins also wired). **Channel B (interface 1) =
  JTAG** through a buffer with active-low OE on DBUS6 (init value 0x0008,
  direction 0x004B). Solder jumpers P3/P8 can switch channel B to SPI flash;
  factory default is JTAG. ftdi_sio does not know the VID:PID:
  `scripts/setup-mimas-udev-rule.sh` installs a rule (done on the owner's PC).
* 100 MHz oscillator on H4 (IO_L12P_T1_MRCC_35). Reset button M2 (active high).
* Ethernet: RTL8211E-VB, RGMII. **TXDLY and RXDLY straps are pulled low** (no
  PHY-internal delays), so the FPGA must supply both RGMII skews (ADR 0004).
  RX clock W19 is MRCC, TX clock pin U20.
* Headers P12 (bank 15) and P13 (bank 16), each 2x40: 20 length-matched pairs,
  P on row A, N on row B at the same row number. **VCC_VADJ is fixed at 3.30 V**
  by the TPS54325 divider (73K2/22K1); not jumper selectable. So LVDS_25 is not
  available on the headers; use LVCMOS33.
* Header rows 1–2 carry **VIN (the raw 5–12 V input)** on both headers; P13
  rows 34–39 carry FPGA **TCK/TDI/TDO/TMS, INIT_B, DONE, PROGRAM_B, M0–2**; P12
  rows 34–39 carry XADC Vp/Vn, VBAT, RESET and the config SPI flash. Rows 9, 15,
  21 carry VADJ. Cables must never span these rows (ADR 0008).
* Clock-capable header pins: P12 GPIO_1 (J20/J21 SRCC), GPIO_4 (J19/H19 MRCC),
  GPIO_6 (K18/K19 MRCC), GPIO_7 (L19/L20 SRCC); P13 GPIO_22 (E19/D19 SRCC),
  GPIO_26 (C18/C19 MRCC), GPIO_27 (D17/C17 MRCC), GPIO_29 (B17/B18 SRCC).
  Rows 22–33 on both headers have **no** clock-capable pins.
* Front panel: 8 LEDs (K17 J17 L14 L15 L16 K16 M15 M16), 4 push buttons
  (P20 P19 P17 N17), 8-way DIP (B21 A21 E22 D22 E21 D21 G21 G22), seven-segment
  display, all signals active low: V2.0 has **3 digits** (enables N3 R1 P1),
  V3.0 has **4 digits** (adds L4). *verify* which revision each board is.
* HDMI IN/OUT through IP4776 buffers; TMDS_33 on bank 35; DDC/HPD/CEC wired
  (pins in vendor XDC).
* V2.0 and V3.0 XDCs are otherwise identical except DisplayPort AUX naming.

## Decision

A single `boards/mimas_a7/mimas_a7.xdc` targets both V2.0 and V3.0; the fourth
seven-segment digit is driven but harmless on V2.0 (L4 unconnected). DIP switch
positions 0–3 are reserved for a manual board-ID / role override (issue 0007).
