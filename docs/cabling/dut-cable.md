# DUT cabling (supervisor ↔ MEGA65)

Each supervisor serves two DUTs: **DUT0 on P12**, **DUT1 on P13**, identical
positions. Per DUT there are two Mimas blocks, J (rows 22–27) and K (rows
28–33), and two MEGA65 connectors, JB1 (TE0790 socket, remove the TE0790)
and J5 (keyboard; unplug the keyboard).

A straight ribbon cannot be used (JB1 pin 12 TMS and J5 pin 2 3.3 V would
land on Mimas GND rows), so there are two options:

* **Bench harness now**: female–female Dupont jumpers per the tables below.
  Twist each signal with a ground where practical; keep ≤ 30 cm.
* **DUT adapter (recommended, issue 0008)**: small board with two 2x6 headers
  matching Mimas J/K blocks (straight 12-way ribbons from the Mimas), and a
  2x6 "JB1" + 2x5 "J5" header so straight 12-/10-way ribbons go to the
  MEGA65. Adds 47 Ω series resistors on every supervisor output, 1 kΩ series
  on every input, and the sense circuits.

## J block → MEGA65 JB1

| Mimas pin | DUT0 ball (P12) | DUT1 ball (P13) | Signal | Dir | MEGA65 JB1 pin |
|---|---|---|---|---|---|
| A22 | H17 | A15 | TCK | → | 4 |
| B22 | H18 | A16 | TMS | → | 12 |
| A23 | G17 | C14 | TDI | → | 10 |
| B23 | G18 | C15 | TDO | ← | 8 |
| A24/B24 | — | — | GND | | 1, 2 |
| A25 | G15 | A13 | UART to DUT (DBG_UART_RX) | → | 7 |
| B25 | G16 | A14 | UART from DUT (DBG_UART_TX) | ← | 3 |
| A26 | J15 | C13 | VIO sense (via ≥10 kΩ) | ← | 6 |
| B26 | H15 | B13 | spare (future PROG_B) | | — |
| A27/B27 | — | — | GND | | 1, 2 |

JB1 pins 5, 9, 11: leave unconnected.

## K block → MEGA65 J5 (keyboard)

| Mimas pin | DUT0 ball (P12) | DUT1 ball (P13) | Signal | Dir | MEGA65 J5 pin |
|---|---|---|---|---|---|
| A28 | K13 | D14 | KIO8 / KB_IO1 (clock+sync from MEGA65) | ← | 8 |
| B28 | K14 | D15 | KIO9 / KB_IO2 (LED data from MEGA65) | ← | 9 |
| A29 | M13 | E13 | KIO10 / KB_IO3 (key data to MEGA65) | → | 10 |
| B29 | L13 | E14 | 3V3 sense (via ≥10 kΩ) | ← | 2 |
| A30/B30 | — | — | GND | | 1 |
| A31..B32 | | | spares | | — |

J5 pins 3–7 (keyboard CPLD JTAG): leave unconnected.

## Physical keyboard (master only) → P12 X block

| Mimas pin | Ball | Signal | Keyboard cable (J5-style) pin |
|---|---|---|---|
| A3/B3, A8/B8 | — | GND | 1 |
| (VADJ via polyfuse, adapter) | — | 3.3 V supply to keyboard | 2 |
| A4 | J20 | PK_IO1 (MK-I clock / MK-II SDA) | 8 |
| B4 | J21 | PK_IO2 (MK-I LED data / MK-II SCL) | 9 |
| A5 | K21 | PK_IO3 (MK-I key data / MK-II holds low) | 10 |

## Electrical rules (from design brief §5)

* All supervisor outputs toward a DUT are tri-stated unless that DUT's sense
  input reads powered (`target output enable policy`, ADR 0005 key 0x0060).
* Sense pins are inputs with no pull; the series resistor limits clamp current
  if the DUT is powered and the Mimas is not. Measure residual voltages before
  unattended use.
* Never connect a MEGA65 3.3 V pin to a Mimas supply pin.
