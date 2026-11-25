# DUT and keyboard cabling (bench jumper strips)

Owner layout, 2026-11-25 (ADR 0008 amendment 2): everything can be bodged
with **straight strips of male-to-female jumpers** (or crimped housings):

| Harness | Mimas end | Other end |
|---|---|---|
| JTAG + UART to a MEGA65 | 2 strips of 5 (columns A and B), rows 3-7 | JB1: rows 1-2, skip row 3 (pins 5/6), rows 4-6 |
| DUT keyboard to a MEGA65 | 1 strip of 5, column A rows 22-26 | J5: pins 8, 9, 1, 10, 2 |
| Physical keyboard (master only) | 1 strip of 5, P12 column B rows 21-25 | keyboard: pins 2, 8, 9, 1, 10 |

**DUT0 uses P12, DUT1 uses P13, at identical positions.**

## Finding rows and columns on the Mimas

Each of P12/P13 is 2x40. A "row" is one pin pair; row 1 is the end whose
two pins carry **VIN (raw DC-jack voltage, 12 V)** — never connect rows
1-2. Column A carries the P side of each pair, column B the N side. Check
with a meter before plugging anything in: rows 3, 8, 14, 20, 24, 27, 30, 33
are GND on both columns; rows 9, 15, 21 are 3.3 V (VADJ) on both columns.
Rows 34-39 are FPGA configuration / flash pins — stay clear.

## MEGA65 connectors (R6 schematic; numbering odd/even = two rows)

JB1 (TE0790 socket, remove the TE0790), 2x6:

```
 1 GND        2 GND
 3 UART_TX    4 TCK        (UART_TX = MEGA65 output)
 5 3.3V n.c.  6 VIO        (row skipped by the strip)
 7 UART_RX    8 TDO        (UART_RX = MEGA65 input)
 9 n.c.      10 TDI
11 n.c.      12 TMS
```

J5 (keyboard; unplug the keyboard ribbon), 2x5:

```
 1 GND        2 3.3V (from the MEGA65)
 3 KB_JTAGEN  4 KB_TMS     (keyboard JTAG: not used)
 5 KB_TCK     6 KB_TDI
 7 KB_TDO     8 KIO8       (KIO8 clock from MEGA65)
 9 KIO9      10 KIO10      (KIO9 LED data from MEGA65, KIO10 key data to it)
```

## 1. JTAG + UART (per DUT): Mimas rows 3-7 -> JB1

A direct map of JB1 with its 3.3 V/VIO row left out: Mimas column A = JB1
odd pins, column B = JB1 even pins.

| Mimas row | Column A | DUT0 / DUT1 ball | JB1 | Column B | DUT0 / DUT1 ball | JB1 |
|---|---|---|---|---|---|---|
| 3 | GND | — | 1 | GND | — | 2 |
| 4 | UART from DUT (in) | J20 / F19 | 3 | TCK (out) | J21 / F20 | 4 |
| 5 | UART to DUT (out) | K21 / E19 | 7 | TDO (in) | K22 / D19 | 8 |
| 6 | VIO sense (in, optional) | H20 / D20 | 9 (n.c.) | TDI (out) | G20 / C20 | 10 |
| 7 | spare | J19 / C22 | 11 (n.c.) | TMS (out) | H19 / B22 | 12 |

The column-A wires for rows 6-7 land
on JB1 n.c. pins and can be left out. If VIO sensing is wanted, run one
extra jumper from JB1 pin 6 to Mimas row 6 column A instead of pin 9.

The supervisor treats the DUT as powered when **either** VIO (if wired) or
the keyboard harness's 3.3 V is present, and keeps TCK/TMS/TDI/UART-out
tri-stated otherwise — so connect the keyboard harness too, or JTAG stays
off.

## 2. DUT keyboard (per DUT): Mimas column A rows 22-26 -> J5

| Mimas row (column A) | Signal | DUT0 / DUT1 ball | J5 pin |
|---|---|---|---|
| 22 | KIO8 (in, clock from MEGA65) | H17 / A15 | 8 |
| 23 | KIO9 (in, LED data from MEGA65) | G17 / C14 | 9 |
| 24 | GND | — | 1 |
| 25 | KIO10 (out, key data to MEGA65) | G15 / A13 | 10 |
| 26 | 3.3 V sense (in) | J15 / C13 | 2 |

The MEGA65's own 3.3 V only goes to a sense input; it is never connected to
the Mimas 3.3 V.

## 3. Physical keyboard (master supervisor only): P12 column B rows 21-25

| Mimas row (column B) | Signal | Ball | Keyboard connector pin |
|---|---|---|---|
| 21 | 3.3 V (VADJ, supplies the keyboard) | — | 2 |
| 22 | KIO8 (MK-I clock / MK-II SDA) | H18 | 8 |
| 23 | KIO9 (MK-I LED data / MK-II SCL) | G18 | 9 |
| 24 | GND | — | 1 |
| 25 | KIO10 (MK-I key data in) | G16 | 10 |

The keyboard type (MK-I or MK-II) is detected automatically; `dutctl
listen` reports it. No keyboard JTAG wires are needed.

## Cautions

* Keep strips short (<= 30 cm); add a ground wire alongside if signals
  look noisy.
* The later DUT adapter (issue 0008) adds series resistors and proper
  sense circuits; until then a DUT powered while the supervisor is off can
  back-power through the I/O protection diodes, so power the supervisor first.
