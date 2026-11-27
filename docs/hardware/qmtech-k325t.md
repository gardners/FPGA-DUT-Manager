# QMTECH XC7K325T core board + QMTECH daughter board (DUT1)

Issue 0057. Bring-up design and tools: `targets/qmtech-k325t/`.

## Sources

| What | Where |
|---|---|
| Core board manual (hardware) | `~/Downloads/QMTECH_Kintex-7_XC7K325T_Core_Board_User_Manual(Hardware)_V01.pdf`; also https://github.com/ChinaQMTECH/QMTECH_XC7K325T_CORE_BOARD |
| Core board schematic | same repo, `Schematic/QMTECH-XC7K325T-CORE-BOARD-V2-20211104.pdf` |
| Core board demo XDC | same repo, `Software/Test01_led_key.zip` (`LED_KEY.xdc`: LEDs J26/H26, clock F22, key AF9 LVCMOS18) |
| Daughter board schematic | https://github.com/ChinaQMTECH/DB_FPGA, `QMTECH_DB_For_FPGA_V04.pdf` (title block `QMTECH_DB_FPGA_V02`) |
| Daughter board manual (A100T setup, same DB) | DB_FPGA repo, `Example_Setups/QMTECH_Artix-7_XC7A100T_Starter_Kit_User_Manual(DaughterBoard)-V01.pdf` |
| Cross-check | LiteX: `litex_boards/platforms/qmtech_xc7k325t.py` (J2/J3 connector -> ball) and `litex_boards/extensions/qmtech.py` (daughter-board peripherals -> J2/J3 pins), https://github.com/litex-hub/litex-boards |

## Header numbering

The daughter board names its header nets `J2_IOn` / `J3_IOn`; the DB
schematic shows `J2_IO7` on physical header pin 5, i.e. **DB net `J2_IOn` =
core-board U5 pin n-2, `J3_IOn` = U4 pin n-2** (U5 pin 5 = A8 in the core
manual, LiteX `J2:7` = A8). LiteX's connector tables use the DB net numbers;
this document does too ("J2:n"). Core U5 = DB J2 (banks 14/15/16), core U4
= DB J3 (banks 12/13).

All header IOs are **HR banks 12-16 at 3.3 V** (bank 12/13 VCCO comes from
3V3 through R31/R32; removing them lets U4 pins 3/4 supply it instead).
The only 1.8 V pins in use on the core board are the user keys SW2/SW3 (AF9,
AF10, HP bank 33, LVCMOS18, 4.7k pull-ups to 1V8): never drive them, never
put a 3.3 V standard on them.

## Pin map

Levels from the DB schematic: segments active low (330R), digit selects
active high (S9014 NPN emitter followers from 3V3 into a common-anode
display), LEDs active low (1k from 3V3), buttons active low (4.7k pull-ups,
switch to GND).

| Peripheral | DB net | Core header pin | Ball | Notes |
|---|---|---|---|---|
| 50 MHz clock | — | — | F22 | bank 14 |
| Core LED2 (D2) | — | — | J26 | active low |
| Core LED3 (D3) | — | — | H26 | active low |
| Core SW2 / SW3 | — | — | AF9 / AF10 | **1.8 V HP bank 33**, active low |
| 7-seg a | J2:31 | U5-29 | B16 | |
| 7-seg b | J2:26 | U5-24 | C14 | |
| 7-seg c | J2:28 | U5-26 | B15 | |
| 7-seg d | J2:32 | U5-30 | C16 | |
| 7-seg e | J2:34 | U5-32 | B17 | |
| 7-seg f | J2:29 | U5-27 | D16 | |
| 7-seg g | J2:25 | U5-23 | C13 | |
| 7-seg dp | J2:30 | U5-28 | D15 | |
| DIG_1 (Q5, left?) | J2:33 | U5-31 | A17 | active high |
| DIG_2 (Q6) | J2:27 | U5-25 | A15 | active high |
| DIG_3 (Q7, right?) | J2:35 | U5-33 | D18 | active high |
| DB LED D1..D5 | J2:40, 39, 38, 37, 36 | U5-38..34 | A18, A19, C17, C18, E18 | active low |
| DB SW1 | J3:7 | U4-5 | AD21 | active low |
| DB SW2..SW5 | J2:44, 43, 42, 41 | U5-42..39 | B20, A20, C19, B19 | active low |
| CP2102 RXD (FPGA TX) | J2:15 | U5-13 | B11 | mini-USB UART |
| CP2102 TXD (FPGA RX) | J2:16 | U5-14 | B12 | driven by the CP2102: input only |
| VGA HS / VS | J3:44 / J3:43 | U4-42 / U4-41 | W26 / W25 | 100R series |
| VGA R4..R0 | J3:57, 56, 59, 58, 60 | | P23, P25, N26, N23, M26 | see VGA note |
| VGA G5..G0 | J3:51, 50, 53, 52, 54, 55 | | T22, U25, R22, T23, R23, R25 | |
| VGA B4..B0 | J3:46, 45, 48, 47, 49 | | V26, U26, V24, V23, U24 | |
| Ethernet RTL8211EG (GMII) | J3:15-42 | | (LiteX `eth`) | PHY drives RX pins: leave as inputs |
| microSD | J3:8-14 | | | |
| PMOD J10 (pins 1-4 / 7-10) | J2:17, 19, 21, 23 / 18, 20, 22, 24 | U5-15..22 | C11, A12, D13, A14 / C12, A13, D14, B14 | |
| PMOD J11 | see below | | | |

VGA note: the DB uses resistor networks (1k / 2k, some in series); the MSB
of each colour has the 1k network. The bit order above is inferred from the
resistor values; LiteX lists the same pins in the opposite order. The
bring-up pattern's colour bars drive all bits of a channel equally (order
does not matter); the grey ramp along the bottom shows whether the order is
right (smooth ramp) or reversed (jumpy, non-monotonic ramp).

Digit order (which of DIG_1..3 is the leftmost digit) is from the usual
3-digit display pinout (pin 12 = digit 1); to be confirmed by the owner.

### PMOD J11 (2x6)

| J11 pin | Signal | Ball | J11 pin | Signal | Ball |
|---|---|---|---|---|---|
| 1 | J2:7 | A8 | 7 | J2:8 | A9 |
| 2 | J2:9 | B9 | 8 | J2:10 | C9 |
| 3 | J2:11 | A10 | 9 | J2:12 | B10 |
| 4 | J2:13 | D10 | 10 | J2:14 | E10 |
| 5 | GND | | 11 | GND | |
| 6 | 3.3 V | | 12 | 3.3 V | |

Bank 16 (HR, 3.3 V).

## UART to the supervisor (J11 -> DUT1 cable)

| J11 pin | K325T ball | Direction | Mimas P13 | Supervisor signal |
|---|---|---|---|---|
| 4 | D10 | K325T output (TX) | row 4 B | "UART from DUT (in)" |
| 10 | E10 | K325T input (RX, internal pull-up) | row 5 B | "UART to DUT (out)" |
| 5 or 11 | GND | | row 3 (A/B, already GND via the JTAG lead) | |

Format: **2,000,000 baud 8N1**, the supervisor's default (`DEFAULT_BAUD_INC`,
ADR 0005 key 0x0010). If the supervisor's baud was changed, set it back with
`dutctl set 203.28.176.87 baud 2000000`; read with `dutctl uart 203.28.176.87`.

## JTAG

6-pin header J1 (3V3, GND, TCK, TDO, TDI, TMS), wired to DUT1 per
`docs/cabling/dut-cable.md` section 4. IDCODE 0x43651093 (XC7K325T rev 4).
`dutctl jtag-speed 203.28.176.87 1` (2026-11-27): ok up to half 3 (20.8
MHz), fails at half 2 (31.25 MHz); recommended **tck_half 6 = 10.4 MHz**.

Configuration: M[2:0] = 001 (master SPI), S25FL256L flash. At power-on the
board boots its SPI-flash image (status register 0x401079fc, DONE = 1, so a
factory image is present). **Do not write the flash** (owner rule); load SRAM
only with `targets/qmtech-k325t/k325t.sh load`.
