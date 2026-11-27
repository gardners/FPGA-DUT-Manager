# Shield v1 pin plan (Mimas A7 P12/P13)

Status: **v1, gate build passed** (2026-11-27), issue 0049 step 1 / issue
0045. The Vivado gate build (`SHIELD_RX=3`, all four receivers on these
pins) places, routes and meets timing; results at the end. Consumers: the KiCad shield (`feature/shield-pcb`),
`boards/mimas_a7/shield_v1.xdc`, the keyboard type 3 work (0046).

## Summary

* **4 DUTs per board**: DUT0 = on-board HDMI IN (unchanged), DUT1..DUT3 =
  header receivers HDMI1..HDMI3, each with FPGA-served EDID (DDC SCL/SDA).
  DUT0/DUT1 JTAG, UART and keyboard stay on their current pins (the bodge
  harnesses keep working with the normal bitstream). DUT2 and DUT3 get
  JTAG (TCK/TMS/TDI/TDO), UART (to/from) and keyboard (KIO8/9/10).
* Also on the headers: shield I2C (SCL/SDA, both expanders + external I2C
  header), physical keyboard JTAG (TCK/TMS/TDI/TDO; JTAGEN on expander B),
  one neighbour UART (TX/RX).
* Slow lines go to I2C expander B: HPD out and +5V sense per header
  receiver, VIO sense and keyboard 3V3 sense for **all four** DUTs, the
  physical keyboard JTAGEN. That frees the four current sense pins; each
  freed pin is reused only as an **input** in shield mode (so a bodge
  harness on it can never be driven).
* Pin budget: 80 header signals, 25 used by the current design, 55 free + 4
  freed sense pins = 59. Shield needs 24 TMDS + 6 DDC + 18 DUT2/DUT3 + 2 I2C
  + 4 keyboard JTAG + 2 neighbour UART = 56. **3 spares**: P13 B22, P13 A19,
  P12 H17 (input only).
* Clock-capable pairs used for the TMDS clocks (verified against the vendor
  XDC and Vivado's package data): HDMI1 P13 C18/C19 (IO_L13 MRCC, bank 16),
  HDMI2 P13 D17/C17 (IO_L12 MRCC, bank 16), HDMI3 P12 L19/L20 (IO_L14 SRCC,
  bank 15). These are the only free clock-capable pairs left. All data lanes
  are true P/N pairs.

## Rules for the PCB

1. **Column A = P, column B = N** (vendor XDC: GPIO_n_P on the A ball).
   TMDS clock P must stay on the A ball (C18, D17, L19). P/N may be swapped on
   any **data** pair for routing; report which, the FPGA inverts that lane
   (`hdmi_rx_xc7` generic `INVERT`). A swapped clock pair is also harmless
   (180 degrees, the per-lane alignment absorbs it) but keep it on the
   clock-capable pair. Lane-to-pair mapping is fixed by the XDC; ask before
   moving a lane to another pair.
2. TMDS_33 inputs have no internal termination: 50 ohm to 3.3 V (VADJ rows
   9/15/21) per line, close to the receptacle; ESD on the TMDS lines.
3. DDC: PCA9306 (or 2 x BSS138) per receiver: source side pulled up to the
   source's +5 V, FPGA side to 3.3 V. FPGA drives SDA open-drain only, SCL is
   input only.
4. HPD (pin 19) through a FET + 1 k to the source's +5 V, gated by expander B;
   +5V sense (pin 18) through a divider (e.g. 10 k / 15 k) to expander B.
5. DUT-facing outputs: 33-100 ohm series resistors near the connector
   (brief section 5). Shield-only outputs stay tri-stated until the FPGA has
   read the shield revision from expander A (so a bodge harness on those pins
   is never driven).
6. Rows 1-2 (VIN), VADJ rows 9/15/21 and rows 34-39 (config) are never
   signal pins. Rows 34-39: no connection on the shield. VIN may be fed from
   the power board's regulated 12 V (0045 power-path note).

## Net list by function

| Function | Nets (ball) |
|---|---|
| HDMI1 (DUT1) | HDMI1_CLK_P/N (C18/C19), HDMI1_D0_P/N (F18/E18), HDMI1_D1_P/N (B20/A20), HDMI1_D2_P/N (E16/D16), HDMI1_SCL (C13), HDMI1_SDA (B13) |
| HDMI2 (DUT2) | HDMI2_CLK_P/N (D17/C17), HDMI2_D0_P/N (B15/B16), HDMI2_D1_P/N (C14/C15), HDMI2_D2_P/N (A13/A14), HDMI2_SCL (D14), HDMI2_SDA (D15) |
| HDMI3 (DUT3) | HDMI3_CLK_P/N (L19/L20), HDMI3_D0_P/N (M21/L21), HDMI3_D1_P/N (M18/L18), HDMI3_D2_P/N (N18/N19), HDMI3_SCL (H13), HDMI3_SDA (G13) |
| DUT0 (P12, unchanged) | DUT0_TCK J20, DUT0_TMS J19, DUT0_TDI H20, DUT0_TDO K21, DUT0_UART_TO K22, DUT0_UART_FROM J21, DUT0_KIO8 N20, DUT0_KIO9 M22, DUT0_KIO10 N22 |
| DUT1 (P13, unchanged) | DUT1_TCK F19, DUT1_TMS C22, DUT1_TDI D20, DUT1_TDO E19, DUT1_UART_TO D19, DUT1_UART_FROM F20, DUT1_KIO8 A18, DUT1_KIO9 B18, DUT1_KIO10 B17 |
| DUT2 (P13) | DUT2_TCK E13, DUT2_TMS F16, DUT2_TDI F13, DUT2_TDO C20, DUT2_UART_TO F14, DUT2_UART_FROM E14, DUT2_KIO8 E17, DUT2_KIO9 A15, DUT2_KIO10 A16 |
| DUT3 (P12) | DUT3_TCK K13, DUT3_TMS J14, DUT3_TDI M13, DUT3_TDO G20, DUT3_UART_TO L13, DUT3_UART_FROM K14, DUT3_KIO8 H14, DUT3_KIO9 H15, DUT3_KIO10 J15 |
| Physical keyboard (P12) | PK_KIO8 K18, PK_KIO9 H22, PK_KIO10 J22 (unchanged); PK_TCK H19, PK_TMS M20, PK_TDI H18, PK_TDO K19; PK_JTAGEN on expander B |
| Shield I2C (P12) | I2C_SCL G15, I2C_SDA G16 (expanders A and B, external I2C header; 3.3 V pull-ups on the shield) |
| Neighbour link (P12) | NB_UART_TX G17, NB_UART_RX G18 (+ GND on the 3-pin header) |
| Spares | SP_P13_B22, SP_P13_A19, SP_P12_H17 (input only) |

DUT directions: UART_TO = FPGA -> DUT RX (JB1 7), UART_FROM = DUT TX -> FPGA
(JB1 3); KIO8 (clock) and KIO9 (LED data) are inputs from the DUT, KIO10
(key data) an output to the DUT. JB1/J5 pin numbers as in ADR 0008.

## I2C expanders

Expander A: **TCA6424A** (24-bit), address 0x22 (ADDR low).

| Port.bit | Dir | Net | Meaning |
|---|---|---|---|
| P0.0-7 | in | SHD_REV0..7 | shield/link board revision (strapped; v1 = 0x01) |
| P1.0 | in | SHD_FEAT0 | HDMI1 capture fitted |
| P1.1 | in | SHD_FEAT1 | power relay header fitted |
| P1.2 | in | SHD_FEAT2 | HDMI2 capture fitted |
| P1.3 | in | SHD_FEAT3 | HDMI3 capture fitted |
| P1.4 | in | SHD_FEAT4 | DUT2 JTAG/UART/keyboard ports fitted |
| P1.5 | in | SHD_FEAT5 | DUT3 JTAG/UART/keyboard ports fitted |
| P1.6 | in | SHD_FEAT6 | neighbour UART fitted |
| P1.7 | in | SHD_FEAT7 | reserved (0) |
| P2.0-7 | out | PWR_CTL0..7 | power/relay control outputs to the 1x11 keyed header, pull-downs (off at reset) |

Expander B: **TCA6416A** (16-bit), address 0x20 (ADDR low).

| Port.bit | Dir | Net | Meaning |
|---|---|---|---|
| P0.0 | out | HDMI1_HPD_EN | drive HDMI1 HPD (pin 19) high through FET + 1 k |
| P0.1 | out | HDMI2_HPD_EN | same, HDMI2 |
| P0.2 | out | HDMI3_HPD_EN | same, HDMI3 |
| P0.3 | out | PK_JTAGEN | physical keyboard J5 pin 3 (JTAG enable), default low |
| P0.4 | in | HDMI1_5V_SENSE | HDMI1 source +5 V present (divider) |
| P0.5 | in | HDMI2_5V_SENSE | HDMI2 source +5 V present |
| P0.6 | in | HDMI3_5V_SENSE | HDMI3 source +5 V present |
| P0.7 | in | PWRB_PRESENT | power board PRESENT (1x11 pin 11, 100 k pull-down; high = present), as in `shield.md` |
| P1.0 | in | DUT0_VIO_SENSE | JB1 pin 6 (VIO) of DUT0, divider |
| P1.1 | in | DUT1_VIO_SENSE | DUT1 |
| P1.2 | in | DUT2_VIO_SENSE | DUT2 |
| P1.3 | in | DUT3_VIO_SENSE | DUT3 |
| P1.4 | in | DUT0_KB_SENSE | J5 pin 2 (3.3 V from the DUT) of DUT0's keyboard connector |
| P1.5 | in | DUT1_KB_SENSE | DUT1 |
| P1.6 | in | DUT2_KB_SENSE | DUT2 |
| P1.7 | in | DUT3_KB_SENSE | DUT3 |

The FPGA polls expander B every ~1 ms; the tri-state gating of DUT-facing
outputs then reacts within about 1 ms, which the series resistors make
harmless (0045 round 3). The expanders' INT and RESET pins are not wired to
the FPGA (spare pads; RESET pulled up).

FPGA side (2026-11-27, issue 0049 step 2): `hdl/src/top/shield_io.vhd` with
`hdl/src/common/i2c_master.vhd`, 400 kHz, in the shield build only
(`SHIELD_RX` > 0). A boot probe reads A's revision/features; output
registers are written before the configuration registers (both parts power
up with output registers 0xFF), so CTRL and HPD never pulse high. Each ~1 ms
slot: read B's inputs, write B P0 (HPD_EN = receiver in the build, clocks
locked and its capture fitted per SHD_FEAT0/2/3; PK_JTAGEN), write A P2
(PWR_CTL0..7 = MGMT key 0x0062, bit n = power-board output n; after an FPGA
reconfiguration with the shield powered, the state already in A is kept
until the host sets one). Configuration is rewritten every 256 slots and
after any failure. DUT0/DUT1 sense for the output gating comes from B
(unpowered until the first good poll and after a failed one); status in
the heartbeat shield block (ADR 0005 section 3c). A single-register
ext_* hook in shield_io serves further devices on the bus (fan controller,
temperature sensor, issue 0052): their 7-bit addresses must avoid 0x20 and
0x22.

## Bodge harness vs shield

The shield build (`SHIELD_RX` > 0) is a separate bitstream from the normal
(bodge-harness) one: TMDS_33 on P12 L19/L20/M21/L21 (HDMI3) and P13 rows
18/19 cannot be LVCMOS at the same time. With the bodge harness those balls
sit under the physical keyboard strip (J5 pins 3-6) and the DUT keyboard
strips (J5 pins 3-6): TMDS inputs there are harmless (inputs, 3.3 V), but
**physical keyboard JTAG over the bodge strip (K19, L19, L20, M21, L21)
only exists in the normal build**. On the shield it moves to H19/M20/H18/K19
(K19 = TDO keeps its bodge position) with JTAGEN on expander B.

## Header tables

Current use = `boards/mimas_a7/mimas_a7.xdc` and the bodge harnesses
(`docs/cabling/dut-cable.md`, ADR 0008 amendments 2-5). CC = clock capable.

### P12 (bank 15)

| Row | Col | Ball | Pair (vendor) | CC | Current use (mimas_a7.xdc / bodge) | Shield use | Net |
|---|---|---|---|---|---|---|---|
| 1 | A+B | - | - | - | raw input (5-12 V); shield may feed regulated 12 V here (0045/0047) | raw input (5-12 V) | VIN |
| 2 | A+B | - | - | - | raw input (5-12 V); shield may feed regulated 12 V here (0045/0047) | raw input (5-12 V) | VIN |
| 3 | A+B | - | - | - | ground | ground | GND |
| 4 | A | J20 | L11P (GPIO_1_P) | SRCC | DUT0 TCK | DUT0 JTAG TCK (JB1 4) | DUT0_TCK |
| 4 | B | J21 | L11N (GPIO_1_N) | SRCC | DUT0 UART from DUT | DUT0 UART from DUT (JB1 3) | DUT0_UART_FROM |
| 5 | A | K21 | L9P (GPIO_2_P) |  | DUT0 TDO | DUT0 JTAG TDO (JB1 8) | DUT0_TDO |
| 5 | B | K22 | L9N (GPIO_2_N) |  | DUT0 UART to DUT | DUT0 UART to DUT (JB1 7) | DUT0_UART_TO |
| 6 | A | H20 | L8P (GPIO_3_P) |  | DUT0 TDI | DUT0 JTAG TDI (JB1 10) | DUT0_TDI |
| 6 | B | G20 | L8N (GPIO_3_N) |  | DUT0 VIO sense | **DUT3 TDO** (input; VIO sense moves to expander B) | DUT3_TDO |
| 7 | A | J19 | L12P (GPIO_4_P) | MRCC | DUT0 TMS | DUT0 JTAG TMS (JB1 12) | DUT0_TMS |
| 7 | B | H19 | L12N (GPIO_4_N) | MRCC | free (harness: JB1 11 n.c.) | physical keyboard TCK | PK_TCK |
| 8 | A+B | - | - | - | ground | ground | GND |
| 9 | A+B | - | - | - | 3.3 V (VADJ, fixed); TMDS terminations, logic supply | 3.3 V (VADJ, fixed) | VADJ_3V3 |
| 10 | A | J22 | L7P (GPIO_5_P) |  | phys. keyboard KIO10 | physical keyboard KIO10 (J5 10) | PK_KIO10 |
| 10 | B | H22 | L7N (GPIO_5_N) |  | phys. keyboard KIO9 | physical keyboard KIO9 (J5 9) | PK_KIO9 |
| 11 | A | K18 | L13P (GPIO_6_P) | MRCC | phys. keyboard KIO8 | physical keyboard KIO8 (J5 8) | PK_KIO8 |
| 11 | B | K19 | L13N (GPIO_6_N) | MRCC | free (harness: phys. kbd J5 7 TDO) | physical keyboard TDO (input, same as harness) | PK_TDO |
| 12 | A | L19 | L14P (GPIO_7_P) | SRCC | free (harness: phys. kbd J5 6 TDI) | HDMI3 TMDS clock + (SRCC) | HDMI3_CLK_P |
| 12 | B | L20 | L14N (GPIO_7_N) | SRCC | free (harness: phys. kbd J5 5 TCK) | HDMI3 TMDS clock - | HDMI3_CLK_N |
| 13 | A | M21 | L10P (GPIO_8_P) |  | free (harness: phys. kbd J5 4 TMS) | HDMI3 TMDS D0 + | HDMI3_D0_P |
| 13 | B | L21 | L10N (GPIO_8_N) |  | free (harness: phys. kbd J5 3 JTAGEN) | HDMI3 TMDS D0 - | HDMI3_D0_N |
| 14 | A+B | - | - | - | ground | ground | GND |
| 15 | A+B | - | - | - | 3.3 V (VADJ, fixed); TMDS terminations, logic supply | 3.3 V (VADJ, fixed) | VADJ_3V3 |
| 16 | A | N22 | L15P (GPIO_9_P) |  | DUT0 KIO10 | DUT0 keyboard KIO10 (J5 10) | DUT0_KIO10 |
| 16 | B | M22 | L15N (GPIO_9_N) |  | DUT0 KIO9 | DUT0 keyboard KIO9 (J5 9) | DUT0_KIO9 |
| 17 | A | N20 | L18P (GPIO_10_P) |  | DUT0 KIO8 | DUT0 keyboard KIO8 (J5 8) | DUT0_KIO8 |
| 17 | B | M20 | L18N (GPIO_10_N) |  | free (harness: DUT0 J5 7) | physical keyboard TMS | PK_TMS |
| 18 | A | M18 | L16P (GPIO_11_P) |  | free (harness: DUT0 J5 6) | HDMI3 TMDS D1 + | HDMI3_D1_P |
| 18 | B | L18 | L16N (GPIO_11_N) |  | free (harness: DUT0 J5 5) | HDMI3 TMDS D1 - | HDMI3_D1_N |
| 19 | A | N18 | L17P (GPIO_12_P) |  | free (harness: DUT0 J5 4) | HDMI3 TMDS D2 + | HDMI3_D2_P |
| 19 | B | N19 | L17N (GPIO_12_N) |  | free (harness: DUT0 J5 3) | HDMI3 TMDS D2 - | HDMI3_D2_N |
| 20 | A+B | - | - | - | ground | ground | GND |
| 21 | A+B | - | - | - | 3.3 V (VADJ, fixed); TMDS terminations, logic supply | 3.3 V (VADJ, fixed) | VADJ_3V3 |
| 22 | A | H17 | L6P (GPIO_13_P) |  | DUT0 kbd 3V3 sense | spare, input only (kbd sense moves to expander B) | SP_P12_H17 |
| 22 | B | H18 | L6N (GPIO_13_N) |  | free | physical keyboard TDI | PK_TDI |
| 23 | A | G17 | L4P (GPIO_14_P) |  | free | neighbour UART TX (out) | NB_UART_TX |
| 23 | B | G18 | L4N (GPIO_14_N) |  | free | neighbour UART RX (in) | NB_UART_RX |
| 24 | A+B | - | - | - | ground | ground | GND |
| 25 | A | G15 | L2P (GPIO_15_P) |  | free | shield I2C SCL (open drain) | I2C_SCL |
| 25 | B | G16 | L2N (GPIO_15_N) |  | free | shield I2C SDA (open drain) | I2C_SDA |
| 26 | A | J15 | L5P (GPIO_16_P) |  | free | DUT3 keyboard KIO10 (out) | DUT3_KIO10 |
| 26 | B | H15 | L5N (GPIO_16_N) |  | free | DUT3 keyboard KIO9 (in) | DUT3_KIO9 |
| 27 | A+B | - | - | - | ground | ground | GND |
| 28 | A | K13 | L19P (GPIO_17_P) |  | free | DUT3 JTAG TCK | DUT3_TCK |
| 28 | B | K14 | L19N (GPIO_17_N) |  | free | DUT3 UART from DUT | DUT3_UART_FROM |
| 29 | A | M13 | L20P (GPIO_18_P) |  | free | DUT3 JTAG TDI | DUT3_TDI |
| 29 | B | L13 | L20N (GPIO_18_N) |  | free | DUT3 UART to DUT | DUT3_UART_TO |
| 30 | A+B | - | - | - | ground | ground | GND |
| 31 | A | J14 | L3P (GPIO_19_P) |  | free | DUT3 JTAG TMS | DUT3_TMS |
| 31 | B | H14 | L3N (GPIO_19_N) |  | free | DUT3 keyboard KIO8 (in) | DUT3_KIO8 |
| 32 | A | H13 | L1P (GPIO_20_P) |  | free | HDMI3 DDC SCL (via level shifter) | HDMI3_SCL |
| 32 | B | G13 | L1N (GPIO_20_N) |  | free | HDMI3 DDC SDA (via level shifter) | HDMI3_SDA |
| 33 | A+B | - | - | - | ground | ground | GND |
| 34 | A+B | - | - | - | XADC Vp/Vn, VBAT, RESET, config SPI flash | **do not connect** | NC |
| 35 | A+B | - | - | - | XADC Vp/Vn, VBAT, RESET, config SPI flash | **do not connect** | NC |
| 36 | A+B | - | - | - | XADC Vp/Vn, VBAT, RESET, config SPI flash | **do not connect** | NC |
| 37 | A+B | - | - | - | XADC Vp/Vn, VBAT, RESET, config SPI flash | **do not connect** | NC |
| 38 | A+B | - | - | - | XADC Vp/Vn, VBAT, RESET, config SPI flash | **do not connect** | NC |
| 39 | A+B | - | - | - | XADC Vp/Vn, VBAT, RESET, config SPI flash | **do not connect** | NC |
| 40 | A+B | - | - | - | ground | ground | GND |

### P13 (bank 16)

| Row | Col | Ball | Pair (vendor) | CC | Current use (mimas_a7.xdc / bodge) | Shield use | Net |
|---|---|---|---|---|---|---|---|
| 1 | A+B | - | - | - | raw input (5-12 V); shield may feed regulated 12 V here (0045/0047) | raw input (5-12 V) | VIN |
| 2 | A+B | - | - | - | raw input (5-12 V); shield may feed regulated 12 V here (0045/0047) | raw input (5-12 V) | VIN |
| 3 | A+B | - | - | - | ground | ground | GND |
| 4 | A | F19 | L18P (GPIO_21_P) |  | DUT1 TCK | DUT1 JTAG TCK (JB1 4) | DUT1_TCK |
| 4 | B | F20 | L18N (GPIO_21_N) |  | DUT1 UART from DUT | DUT1 UART from DUT (JB1 3) | DUT1_UART_FROM |
| 5 | A | E19 | L14P (GPIO_22_P) | SRCC | DUT1 TDO | DUT1 JTAG TDO (JB1 8) | DUT1_TDO |
| 5 | B | D19 | L14N (GPIO_22_N) | SRCC | DUT1 UART to DUT | DUT1 UART to DUT (JB1 7) | DUT1_UART_TO |
| 6 | A | D20 | L19P (GPIO_23_P) |  | DUT1 TDI | DUT1 JTAG TDI (JB1 10) | DUT1_TDI |
| 6 | B | C20 | L19N (GPIO_23_N) |  | DUT1 VIO sense | **DUT2 TDO** (input; VIO sense moves to expander B) | DUT2_TDO |
| 7 | A | C22 | L20P (GPIO_24_P) |  | DUT1 TMS | DUT1 JTAG TMS (JB1 12) | DUT1_TMS |
| 7 | B | B22 | L20N (GPIO_24_N) |  | free (harness: JB1 11 n.c.) | spare | SP_P13_B22 |
| 8 | A+B | - | - | - | ground | ground | GND |
| 9 | A+B | - | - | - | 3.3 V (VADJ, fixed); TMDS terminations, logic supply | 3.3 V (VADJ, fixed) | VADJ_3V3 |
| 10 | A | F18 | L15P (GPIO_25_P) |  | free | HDMI1 TMDS D0 + | HDMI1_D0_P |
| 10 | B | E18 | L15N (GPIO_25_N) |  | free | HDMI1 TMDS D0 - | HDMI1_D0_N |
| 11 | A | C18 | L13P (GPIO_26_P) | MRCC | free | HDMI1 TMDS clock + (MRCC) | HDMI1_CLK_P |
| 11 | B | C19 | L13N (GPIO_26_N) | MRCC | free | HDMI1 TMDS clock - | HDMI1_CLK_N |
| 12 | A | D17 | L12P (GPIO_27_P) | MRCC | free | HDMI2 TMDS clock + (MRCC) | HDMI2_CLK_P |
| 12 | B | C17 | L12N (GPIO_27_N) | MRCC | free | HDMI2 TMDS clock - | HDMI2_CLK_N |
| 13 | A | B20 | L16P (GPIO_28_P) |  | free | HDMI1 TMDS D1 + | HDMI1_D1_P |
| 13 | B | A20 | L16N (GPIO_28_N) |  | free | HDMI1 TMDS D1 - | HDMI1_D1_N |
| 14 | A+B | - | - | - | ground | ground | GND |
| 15 | A+B | - | - | - | 3.3 V (VADJ, fixed); TMDS terminations, logic supply | 3.3 V (VADJ, fixed) | VADJ_3V3 |
| 16 | A | B17 | L11P (GPIO_29_P) | SRCC | DUT1 KIO10 | DUT1 keyboard KIO10 (J5 10) | DUT1_KIO10 |
| 16 | B | B18 | L11N (GPIO_29_N) | SRCC | DUT1 KIO9 | DUT1 keyboard KIO9 (J5 9) | DUT1_KIO9 |
| 17 | A | A18 | L17P (GPIO_30_P) |  | DUT1 KIO8 | DUT1 keyboard KIO8 (J5 8) | DUT1_KIO8 |
| 17 | B | A19 | L17N (GPIO_30_N) |  | free (harness: DUT1 J5 7) | spare | SP_P13_A19 |
| 18 | A | E16 | L5P (GPIO_31_P) |  | free (harness: DUT1 J5 6) | HDMI1 TMDS D2 + | HDMI1_D2_P |
| 18 | B | D16 | L5N (GPIO_31_N) |  | free (harness: DUT1 J5 5) | HDMI1 TMDS D2 - | HDMI1_D2_N |
| 19 | A | B15 | L7P (GPIO_32_P) |  | free (harness: DUT1 J5 4) | HDMI2 TMDS D0 + | HDMI2_D0_P |
| 19 | B | B16 | L7N (GPIO_32_N) |  | free (harness: DUT1 J5 3) | HDMI2 TMDS D0 - | HDMI2_D0_N |
| 20 | A+B | - | - | - | ground | ground | GND |
| 21 | A+B | - | - | - | 3.3 V (VADJ, fixed); TMDS terminations, logic supply | 3.3 V (VADJ, fixed) | VADJ_3V3 |
| 22 | A | A15 | L9P (GPIO_33_P) |  | DUT1 kbd 3V3 sense | **DUT2 keyboard KIO9** (input; kbd sense moves to expander B) | DUT2_KIO9 |
| 22 | B | A16 | L9N (GPIO_33_N) |  | free | DUT2 keyboard KIO10 (out) | DUT2_KIO10 |
| 23 | A | C14 | L3P (GPIO_34_P) |  | free | HDMI2 TMDS D1 + | HDMI2_D1_P |
| 23 | B | C15 | L3N (GPIO_34_N) |  | free | HDMI2 TMDS D1 - | HDMI2_D1_N |
| 24 | A+B | - | - | - | ground | ground | GND |
| 25 | A | A13 | L10P (GPIO_35_P) |  | free | HDMI2 TMDS D2 + | HDMI2_D2_P |
| 25 | B | A14 | L10N (GPIO_35_N) |  | free | HDMI2 TMDS D2 - | HDMI2_D2_N |
| 26 | A | C13 | L8P (GPIO_36_P) |  | free | HDMI1 DDC SCL (via level shifter) | HDMI1_SCL |
| 26 | B | B13 | L8N (GPIO_36_N) |  | free | HDMI1 DDC SDA (via level shifter) | HDMI1_SDA |
| 27 | A+B | - | - | - | ground | ground | GND |
| 28 | A | D14 | L6P (GPIO_37_P) |  | free | HDMI2 DDC SCL (via level shifter) | HDMI2_SCL |
| 28 | B | D15 | L6N (GPIO_37_N) |  | free | HDMI2 DDC SDA (via level shifter) | HDMI2_SDA |
| 29 | A | E13 | L4P (GPIO_38_P) |  | free | DUT2 JTAG TCK | DUT2_TCK |
| 29 | B | E14 | L4N (GPIO_38_N) |  | free | DUT2 UART from DUT | DUT2_UART_FROM |
| 30 | A+B | - | - | - | ground | ground | GND |
| 31 | A | F13 | L1P (GPIO_39_P) |  | free | DUT2 JTAG TDI | DUT2_TDI |
| 31 | B | F14 | L1N (GPIO_39_N) |  | free | DUT2 UART to DUT | DUT2_UART_TO |
| 32 | A | F16 | L2P (GPIO_40_P) |  | free | DUT2 JTAG TMS | DUT2_TMS |
| 32 | B | E17 | L2N (GPIO_40_N) |  | free | DUT2 keyboard KIO8 (in) | DUT2_KIO8 |
| 33 | A+B | - | - | - | ground | ground | GND |
| 34 | A+B | - | - | - | FPGA JTAG TCK/TDI/TDO/TMS, INIT_B, DONE, PROGRAM_B, M0-2 | **do not connect** | NC |
| 35 | A+B | - | - | - | FPGA JTAG TCK/TDI/TDO/TMS, INIT_B, DONE, PROGRAM_B, M0-2 | **do not connect** | NC |
| 36 | A+B | - | - | - | FPGA JTAG TCK/TDI/TDO/TMS, INIT_B, DONE, PROGRAM_B, M0-2 | **do not connect** | NC |
| 37 | A+B | - | - | - | FPGA JTAG TCK/TDI/TDO/TMS, INIT_B, DONE, PROGRAM_B, M0-2 | **do not connect** | NC |
| 38 | A+B | - | - | - | FPGA JTAG TCK/TDI/TDO/TMS, INIT_B, DONE, PROGRAM_B, M0-2 | **do not connect** | NC |
| 39 | A+B | - | - | - | FPGA JTAG TCK/TDI/TDO/TMS, INIT_B, DONE, PROGRAM_B, M0-2 | **do not connect** | NC |
| 40 | A+B | - | - | - | ground | ground | GND |

## Gate build results (2026-11-27, commit 8e473b8)

`VIVADO_OUT=build/vivado-shield VIVADO_GENERICS="SHIELD_RX=3" make bitstream`:
on-board HDMI IN + HDMI1..HDMI3 on the pins above, each with its own DDC
EDID server and video_meas.

* Placed and routed, DRC as the normal build (4 known warnings, MIG/pk_kio9).
* **TIMING MET: WNS +0.238 ns, WHS +0.051 ns** (normal build path limits;
  the header receiver pixel domains have 25-28 ns setup slack, +0.074 ns
  hold).
* Utilisation: LUT 19603 / 32600 (60 %), FF 23961 (37 %), BRAM 32 / 75,
  bonded IOB 168 / 250, **PLLE2 5 / 5**, MMCM 5 / 5, BUFG 21 / 32, BUFIO 1,
  BUFR 1, **IDELAYCTRL 5 / 5**, IDELAYE2 33, ISERDESE2 40.
* Placement: HDMI1 PLL in X1Y1 and HDMI2 PLL in X0Y0 (both fed through a
  BUFG from bank 16), HDMI3 PLL in X0Y1 (its own region, dedicated route).
  IDELAYCTRL: one per region (X0Y0 RGMII, X0Y1 HDMI3, X0Y2 HDMI1+HDMI2
  shared, X1Y0 DDR3, X1Y1 on-board HDMI IN).

Verdict: **4 DUTs per board fit**, with no clocking resource left
(all PLLs, MMCMs and IDELAYCTRL sites used). A later clock need would use
the shared-PLL fallback for HDMI2/HDMI3 (issue 0049).
