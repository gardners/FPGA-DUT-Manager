# DUT and keyboard cabling (bench jumper strips)

Owner layout, 2026-11-25 (ADR 0008 amendment 2): everything can be bodged
with **straight strips of male-to-female jumpers** (or crimped housings):

| Harness | Mimas end | Other end |
|---|---|---|
| JTAG + UART to a MEGA65 | 2 strips of 5 (columns A and B), rows 3-7 | JB1: rows 1-2, skip row 3 (pins 5/6), rows 4-6 |
| DUT keyboard to a MEGA65 | rows 20 down to 16, both columns (J5 in order) + 1 single jumper | J5 2x5 straight; pin 2 jumper to row 22 A |
| Physical keyboard (master only) | P12 rows 14 down to 10, both columns (in order) + 1 single jumper | keyboard 2x5 straight; pin 2 jumper to row 15 A |

**DUT0 uses P12, DUT1 uses P13, at identical positions.**

> **WARNINGS — read before plugging anything in**
>
> * **JTAG strips skip a row on the MEGA65 side.** JB1 row 3 (pins 5/6:
>   3.3 V and VIO) is *not* part of the strip: Mimas rows 3-7 map to JB1
>   rows 1, 2, then **4, 5, 6**. If the JB1 end is pushed on one row out,
>   TCK/TDO land on 3.3 V/VIO.
> * **The keyboard blocks run the opposite way to the JTAG block.** JTAG
>   goes *up* the Mimas from GND row 3 (JB1 pin 1 at row 3, pin 12 at row 7);
>   each keyboard block goes *down* from its GND row (J5 pin 1 at row 14 or
>   20, pin 10 at row 10 or 16). Check the GND end of every strip first.
> * **Mimas rows 9, 15 and 21 are 3.3 V on both columns** (and rows 1-2 are
>   raw 12 V VIN). They sit directly next to the keyboard and JTAG blocks; a
>   strip shifted by one row puts a signal — or the MEGA65's own 3.3 V —
>   onto the Mimas supply. Only one wire may touch a 3.3 V row: the
>   *physical* keyboard's pin 2 on row 15. A DUT keyboard's pin 2 goes to
>   row 22 A (sense), **never** row 21.
> * Before powering up, check with a meter: every strip's GND wire reads 0 Ω
>   to Mimas GND, and no MEGA65-side wire reads 0 Ω to Mimas 3.3 V except the
>   physical keyboard's pin 2.

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

A direct map of JB1 with its 3.3 V/VIO row left out: **Mimas column B = JB1
odd pins (pin-1 side), column A = JB1 even pins** (amendment 5).

| Mimas row | Column B (cable odd pins) | DUT0 / DUT1 ball | JB1 | Column A (cable even pins) | DUT0 / DUT1 ball | JB1 |
|---|---|---|---|---|---|---|
| 3 | GND | — | 1 | GND | — | 2 |
| 4 | UART from DUT (in) | J21 / F20 | 3 | TCK (out) | J20 / F19 | 4 |
| 5 | UART to DUT (out) | K22 / D19 | 7 | TDO (in) | K21 / E19 | 8 |
| 6 | VIO sense (in, optional) | G20 / C20 | 9 (n.c.) | TDI (out) | H20 / D20 | 10 |
| 7 | spare | H19 / B22 | 11 (n.c.) | TMS (out) | J19 / C22 | 12 |

The column-B wires for rows 6-7 land
on JB1 n.c. pins and can be left out. For VIO sensing, run one extra jumper
from JB1 pin 6 (VIO) to Mimas row 6 column B (a 1-2.2 kOhm series resistor: the
sense ball has the FPGA's internal pull-down, as strong as ~10 kOhm (7-series
IRPD up to ~330 uA at 3.3 V), so 10 kOhm can leave it below VIH; the resistor
avoids back-feeding the Mimas when only the MEGA65 is powered); the
heartbeat then shows `vio=1` when the MEGA65 is on.

The supervisor treats the DUT as powered when **either** VIO (if wired) or
the keyboard harness's 3.3 V is present, and keeps TCK/TMS/TDI/UART-out
tri-stated otherwise — so connect the keyboard harness too, or JTAG stays
off.

## 2. DUT keyboard (per DUT): Mimas rows 20 down to 16 -> J5, in order

The block mirrors J5 row for row, running *down* the Mimas (column B = J5
odd pins, column A = even pins), so all ten wires can be two straight 1x5
strips. J5 pins 3-7 are the keyboard-CPLD JTAG signals; they land on FPGA
pins the design leaves unused (never driven, weak pull-down), so wiring them
is harmless. Only J5 pin 2 (the MEGA65's 3.3 V) needs its own jumper, kept in
column A with the other even pins: it would otherwise sit on GND, and it
must go to the sense input on row 22, **never to row 21** (the Mimas 3.3 V
supply: that would tie the two boards' regulators together).

| Mimas row | Column B (J5 odd pins) | J5 | Column A (J5 even pins) | J5 |
|---|---|---|---|---|
| 22 | — | | **3.3 V sense in** — H17 / A15 | **2 (separate jumper)** |
| 21 | (Mimas 3.3 V row — nothing here) | | | |
| 20 | GND | 1 | GND — leave empty (pin 2 is moved) | — |
| 19 | KB_JTAGEN (unused pin) | 3 | KB_TMS (unused pin) | 4 |
| 18 | KB_TCK (unused pin) | 5 | KB_TDI (unused pin) | 6 |
| 17 | KB_TDO (unused pin) | 7 | KIO8 in — N20 / A18 | 8 |
| 16 | KIO9 in — M22 / B18 | 9 | KIO10 out — N22 / B17 | 10 |

(Balls: DUT0 on P12 / DUT1 on P13.)

## 3. Physical keyboard (master supervisor only): P12 rows 14 down to 10

Same idea; here the keyboard's pin 2 is its 3.3 V *supply*, which comes from
the Mimas 3.3 V row 15 right next to the block.

| Mimas row | Column B (odd pins) | Keyboard pin | Column A (even pins) | Keyboard pin |
|---|---|---|---|---|
| 15 | 3.3 V | | **3.3 V supply (VADJ)** | **2 (separate jumper)** |
| 14 | GND | 1 | GND — leave empty (pin 2 is moved) | — |
| 13 | KB_JTAGEN — L21 | 3 | KB_TMS — M21 | 4 |
| 12 | KB_TCK — L20 | 5 | KB_TDI — L19 | 6 |
| 11 | KB_TDO (in) — K19 | 7 | KIO8 (MK-I clock / MK-II SDA / type 3 held low) — K18 | 8 |
| 10 | KIO9 (MK-I LED data / MK-II SCL) — H22 | 9 | KIO10 (MK-I key data) — J22 | 10 |

The keyboard type (type 3, MK-I or MK-II) is detected automatically;
`dutctl listen` reports it. Rows 13-11 B carry the keyboard CPLD's JTAG
(ADR 0014): tri-stated unless the keyboard JTAG target is enabled, so the
CPLD can be read (`dutctl jtag-idcode IP --kbd`) and flashed through XVC
(`dutctl xvc IP --kbd`).

## Cautions

* Keep strips short (<= 30 cm); add a ground wire alongside if signals
  look noisy.
* The later DUT adapter (issue 0008) adds series resistors and proper
  sense circuits; until then a DUT powered while the supervisor is off can
  back-power through the I/O protection diodes, so power the supervisor first.

## 4. Xilinx K325T board, 6-pin JTAG header (owner, 2026-11-27)

Header pins 1-6: 3V3, GND, TCK, TDO, TDI, TMS (3.3 V JTAG). No UART (the
board's UART is on its mini-USB port). Wire it to the DUT port's rows 3-7
(DUT1 = P13) as for JB1:

| K325T pin | Signal | Mimas row / column |
|---|---|---|
| 1 | 3V3 | **1 kOhm** in series -> row 6 B (VIO sense) |
| 2 | GND | row 3 (A or B) |
| 3 | TCK | row 4 A |
| 4 | TDO | row 5 A |
| 5 | TDI | row 6 A |
| 6 | TMS | row 7 A |

Rows 4 B, 5 B and 7 B stay empty. The 3V3 wire is the board's power sense:
without it (and with no keyboard harness) the supervisor keeps TCK/TMS/TDI
tri-stated. The 1 kOhm keeps the sense reliable and limits current if the
Mimas is unpowered (back-feed through its input clamp) or the ball is ever
driven low by a wrong bitstream (3.3 mA instead of a short on the K325T
3V3 rail). There is no workaround without the wire: the JTAG outputs follow
the power sense only; `out-policy` (key 0x0060) switches the UART and
keyboard outputs, not JTAG.

**Back-powering caution (2026-11-27):** while the sense reads powered, TCK
(low), TMS and TDI (their last bit, TMS usually high after a reset to
Test-Logic-Reset) stay driven between transactions. When the DUT is switched
off, a high TMS/TDI feeds its 3V3 rail through the FPGA's input clamp
diodes; if that holds the rail high enough, the sense keeps reading powered
and the outputs keep driving. Until the supervisor releases idle JTAG
outputs (issue 0056), unplug the JTAG lead or leave the DUT powered while
the lead is connected and the supervisor is running.
