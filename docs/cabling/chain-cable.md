# Chain cable (supervisor ↔ supervisor)

Two straight 10-way IDC ribbons per link, 2x5 female IDC on both ends,
**pin 1 to pin 1**, no crossover. Ribbon "A" joins header rows 10–14, ribbon
"B" joins rows 16–20. The 2x5 connector's pin 1 sits on header pin A10 (resp.
A16); pin 2 on B10 (B16). Do **not** use a wider connector: rows 9, 15 and 21
are VADJ (3.3 V supply) and must not be bridged between boards.

```
 node n (closer to master)                 node n+1
 P12 rows 10-14  ==== ribbon A ====  P13 rows 10-14
 P12 rows 16-20  ==== ribbon B ====  P13 rows 16-20
```

The master is the node with nothing plugged into P13 rows 10–20.

| IDC pin | Hdr pin | Signal | Dir (n ← n+1) | P12 ball (n) | P13 ball (n+1) |
|---|---|---|---|---|---|
| A1 | A10 | VD0 | ← | J22 | F18 |
| A2 | B10 | VD1 | ← | H22 | E18 |
| A3 | A11 | **VCLK** | ← | K18 (MRCC) | C18 (MRCC) |
| A4 | B11 | VD2 | ← | K19 | C19 |
| A5 | A12 | VD3 | ← | L19 | D17 |
| A6 | B12 | VD4 | ← | L20 | C17 |
| A7 | A13 | VD5 | ← | M21 | B20 |
| A8 | B13 | VD6 | ← | L21 | A20 |
| A9 | A14 | GND | | | |
| A10 | B14 | GND | | | |
| B1 | A16 | VD7 | ← | N22 | B17 |
| B2 | B16 | VD8 | ← | M22 | B18 |
| B3 | A17 | VD9 | ← | N20 | A18 |
| B4 | B17 | VD10 | ← | M20 | A19 |
| B5 | A18 | VD11 | ← | M18 | E16 |
| B6 | B18 | VD12 | ← | L18 | D16 |
| B7 | A19 | VD13 | ← | N18 | B15 |
| B8 | B19 | **CTL_DN** | → | N19 | B16 |
| B9 | A20 | GND | | | |
| B10 | B20 | GND | | | |

All LVCMOS33. Outputs: 8 mA, SLOW slew initially (raise only if eye
measurements require). Inputs: no pull, except CTL_DN on the up-link (P13 B16)
which has PULLDOWN for presence detection.

Recommended: shrouded keyed 2x5 headers are not fitted on the Mimas; mark
pin 1 on the board and the cable, and keep ribbons ≤ 30 cm until measured.
