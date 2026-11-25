# ADR 0008: Header P12/P13 allocation and cable families

Status: Proposed (2026-11-25)

## Context

Each Mimas header (P12 bank 15, P13 bank 16) is 2x40 with this row pattern
(pairs are A/B at the same row):

```
row  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34..39 40
     VIN VIN G  S  S  S  S  G  V  S  S  S  S  G  V  S  S  S  S  G  V  S  S  G  S  S  G  S  S  G  S  S  G  cfg/spi G
```
(S = signal pair, G = GND both columns, V = VADJ 3.3 V both columns.)

Cables must never span rows 1–2 (VIN), V rows, or rows 34–39. That leaves
five 8-signal **blocks** per header:

| Block | Rows | IDC | Geometry |
|---|---|---|---|
| X | 3–8 | 2x6 | G S S S S G |
| CA | 10–14 | 2x5 | S S S S G |
| CB | 16–20 | 2x5 | S S S S G |
| J | 22–27 | 2x6 | S S G S S G |
| K | 28–33 | 2x6 | S S G S S G |

Clock-capable pins exist only in rows 4–19 (ADR 0003).

MEGA65 connectors (R6 schematic, `pcbs/mega65r6`; R3–R5 to be confirmed):

* **JB1** (TE0790 socket, 2x6): 1 GND, 2 GND, 3 DBG_UART_TX (MEGA65 out),
  4 TCK, 5 3.3V (n.c. on MEGA65), 6 VIO (3.3 V), 7 DBG_UART_RX (MEGA65 in,
  10 kΩ pull-down), 8 TDO, 9 n.c., 10 TDI, 11 n.c., 12 TMS.
* **J5 keyboard** (2x5): 1 GND, 2 3.3V (from MEGA65), 3 KB_JTAGEN, 4 KB_TMS,
  5 KB_TCK, 6 KB_TDI, 7 KB_TDO, 8 KB_IO1 (=kio8 clock from MEGA65),
  9 KB_IO2 (=kio9 LED data from MEGA65), 10 KB_IO3 (=kio10 key data to MEGA65).

Neither maps straight onto a Mimas block (JB1 pin 12 TMS would land on GND;
J5 pin 2 3.3 V would land on GND), so a straight ribbon from Mimas to MEGA65
is impossible.

## Decision

Allocation (identical bitstream on every node):

| Header | Block | Function |
|---|---|---|
| P12 | X | Physical keyboard host (master's own keyboard) + 5 spares |
| P12 | CA+CB | Chain **down-link** port (ADR 0007) |
| P12 | J | DUT0 JTAG + UART + VIO sense |
| P12 | K | DUT0 keyboard + 3V3 sense |
| P13 | X | Relay / PSU control outputs (future direct drive via level shifters) |
| P13 | CA+CB | Chain **up-link** port |
| P13 | J | DUT1 JTAG + UART + VIO sense |
| P13 | K | DUT1 keyboard + 3V3 sense |

Within J and K blocks (same positions on both headers, so DUT0 and DUT1
harnesses are interchangeable):

| Pos | J block | K block |
|---|---|---|
| A(r) | TCK → | KIO8 ← (clock from DUT) |
| B(r) | TMS → | KIO9 ← (LED data from DUT) |
| A(r+1) | TDI → | KIO10 → (key data to DUT) |
| B(r+1) | TDO ← | KB 3V3 sense ← |
| A(r+3) | UART to DUT → (DUT RX) | spare (future reset contact) |
| B(r+3) | UART from DUT ← (DUT TX) | spare (future power button) |
| A(r+4) | VIO sense ← | spare |
| B(r+4) | spare (future PROG_B) | spare |

(r = 22 for J, 28 for K; rows r+2 and r+5 are GND.)

**Cable families**

1. *Chain*: two straight 10-way IDC ribbons (2x5 ↔ 2x5), P12 CA→P13 CA and
   P12 CB→P13 CB of the neighbour. Keyed shrouded headers recommended. No
   adapter.
2. *DUT*: one **DUT adapter** per DUT (perfboard now, small PCB later) with a
   2x6 + 2x6 socket pair matching the Mimas J and K blocks, and a JB1-style
   2x6 plus a J5-style 2x5 header so that **straight** 12-way and 10-way IDC
   ribbons run from adapter to MEGA65. The adapter holds the 33–100 Ω series
   resistors (source damping + back-power current limiting), the sense
   dividers/comparators per design brief §5, and the pin remapping. Until it
   exists, a Dupont jumper harness following `docs/cabling/dut-cable.md` is
   acceptable for bench work with the brief's power-sequencing cautions.
3. *Physical keyboard*: adapter X-block → J5-style 2x5; supplies the
   keyboard's 3.3 V from a Mimas VADJ pin via a polyfuse (never from a DUT).
4. *Relays*: P13 X-block → level shifter → XC4418 (future; Arduino first).

## Consequences

Each node uses 2 chain ribbons + 2 DUT adapters (4 ribbons to MEGA65s). Spares:
5 in P12 X, 6 across J/K blocks per DUT.

## Amendment 2026-11-25 (owner): physical keyboard on P12 rows 6-9

Keyboard JTAG is not needed; only KIO8-10, GND and 3.3 V. To keep the
bench cable to two short strips, the physical keyboard uses P12 rows 6-9
in a single 2x4 housing (rows 4-5 of the X block become spares):

| P12 row | A (P) | B (N) |
|---|---|---|
| 6 | H20: J5 pin 7 (KB_TDO) — leave unwired | G20: J5 pin 8 KIO8 |
| 7 | J19: J5 pin 9 KIO9 | H19: J5 pin 10 KIO10 |
| 8 | GND: J5 pin 1 | GND |
| 9 | VADJ 3.3 V: J5 pin 2 | VADJ 3.3 V |

Keyboard side: a 2x2 housing on J5 pins 7-10 (pin 7 position empty) and a
1x2 on pins 1-2. The keyboard supply comes from VADJ, not an FPGA pin.

## Amendment 2 2026-11-25 (owner): bench layout with straight jumper strips

Supersedes the J/K block positions and amendment 1. Goal: each harness is
straight strips of male-to-female jumpers (see docs/cabling/dut-cable.md).

| Header | Rows / column | Function |
|---|---|---|
| P12 / P13 | rows 3-7, both columns | DUT0 / DUT1 JTAG + UART: JB1 rows 1, 2, 4, 5, 6 (JB1 row 3, 3.3 V/VIO, skipped) |
| P12 / P13 | column A rows 22-26 | DUT0 / DUT1 keyboard: KIO8, KIO9, GND, KIO10, 3V3 sense |
| P12 | column B rows 21-25 | physical keyboard: 3.3 V (VADJ), KIO8, KIO9, GND, KIO10 |
| P12 / P13 | rows 10-13, 16-19 | chain link (unchanged, ADR 0007) |
| P13 | column B rows 21-26, rows 28-33 | spare (relay outputs later) |

VIO sense moves to row 6 column A (JB1 pin 9 position, n.c. on the MEGA65;
optional extra jumper from JB1 pin 6). "DUT powered" is now VIO **or** the
keyboard cable's 3.3 V, so the keyboard harness alone enables JTAG/UART
outputs.

## Amendment 3 2026-11-25 (owner): keyboard blocks mirror J5

Supersedes the keyboard rows of amendment 2. Each keyboard harness is two
straight 1x5 strips that keep the J5 2x5 order (Mimas column A = odd pins,
B = even); only J5 pin 2 (3.3 V) is a separate jumper, because the Mimas
has no row with GND and a signal/supply side by side.

| Header | Rows | Function |
|---|---|---|
| P12 / P13 | 8-12 (+ row 13 B) | DUT0 / DUT1 keyboard: 8A GND, 11B KIO8, 12A KIO9, 12B KIO10; 13B 3V3 sense |
| P12 | 14-18 (+ row 15) | physical keyboard: 14A GND, 17B KIO8, 18A KIO9, 18B KIO10; pin 2 to row 15 (VADJ) |

Consequence: rows 10-13 and 16-19 are no longer free for the chain link
(ADR 0007); its pins must be reallocated in phase 3 (rows 22-33 are free on
both headers but have no clock-capable pins, which the forwarded chain
clock may need — to be decided then).
