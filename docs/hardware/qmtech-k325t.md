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
| microSD J9 (CD, DAT1, DAT0, CLK, CMD, DAT3, DAT2) | J3:8, 9, 10, 11, 12, 13, 14 | U4-6..12 | AE21, AE22, AF22, AE23, AF23, V21, W21 | 4.7k pull-ups (R68-R74); see below |
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

### microSD (issue 0057, verified 2026-11-27)

Probe design: `targets/qmtech-k325t/hdl/k325t_sdprobe.vhd` (README there).

**Daughter-board slot J9** (DB schematic, LiteX `sdcard` agrees): J9-1
DAT2 = J3:14 (W21), J9-2 CD/DAT3 = J3:13 (V21), J9-3 CMD = J3:12 (AF23),
J9-5 CLK = J3:11 (AE23), J9-7 DAT0 = J3:10 (AF22), J9-8 DAT1 = J3:9 (AE22),
J9-9 card detect = J3:8 (AE21). All seven have 4.7k pull-ups to 3.3 V.
**CD reads 0 with a card inserted, 1 when empty.** SPI mode (CS = DAT3,
DI = CMD, DO = DAT0, SCK = CLK) works at 250 kHz.

**PMOD microSD adapter on J11 pins 1-6** (the owner's no-silkscreen
adapters, plugged in the orientation used on 2026-11-27): found by trying
all 24 assignments of J11 pins 1-4:

| J11 pin | Ball | Adapter signal (SPI) | SD pin |
|---|---|---|---|
| 1 | A8 | DO (MISO) | DAT0 |
| 2 | B9 | SCK | CLK |
| 3 | A10 | CS | DAT3 |
| 4 | D10 | DI (MOSI) | CMD |
| 5 | GND | GND | VSS |
| 6 | 3.3 V | VCC | VDD |

This is not the Digilent PmodSD order (CS, MOSI, MISO, SCK). The adapter
has no pull-up resistors: with the FPGA's weak pull-down all four pins read
0. With no FPGA pull, J11-3 recovers to 1 after being driven low (the card's
own DAT3 pull-up) and pins 1, 2 and 4 float. No pin is tied to a rail. J11
pins 7-10 follow the FPGA pull (nothing connected). Use the FPGA's pull-ups
(PULLUP on all four, at least on DO and CS) when talking to the card. A
card fresh from power-up ignored the first CMD0 here; send CMD0 again
until it answers 0x01.

Cards seen (2026-11-27):

| Slot | CID | Decoded | CSD | Capacity |
|---|---|---|---|---|
| J11 adapter | `7FFFFF3132333220100000003A00BBB7` | MID 0x7F, OID 0xFFFF, PNM "1232 ", PRV 1.0, PSN 0x0000003A, MDT 2011-11 (no-name) | `007F00325B5A83C5FFFFCF8016800013` (CSD 1.0, READ_BL_LEN 10, C_SIZE 3863, C_SIZE_MULT 7) | 1932 MiB (2 GB SDSC: CMD8 accepted, OCR 0x80FF8000, CCS = 0, byte addressing) |
| J9 (DB slot) | `035344534C31364780C486104C01147D` | MID 0x03 (SanDisk), OID "SD", PNM "SL16G", PRV 8.0, PSN 0xC486104C, MDT 2017-04 | `400E00325B59000076B27F800A404013` (CSD 2.0, C_SIZE 30386) | 15193 MiB (16 GB SDHC, OCR 0xC0FF8000, CCS = 1) |

### JP1 (2x9, daughter board)

From the DB_FPGA V04 schematic (net labels sit above their wires): pin 1 is
3.3 V, pin 2 GND; J2_IO60 and J2_IO59 have 4.7 k pull-ups to 3.3 V (R63,
R64). DB net J2_IOn = core U5 pin n-2.

| JP1 pin | Signal | Ball | JP1 pin | Signal | Ball |
|---|---|---|---|---|---|
| 1 | 3.3 V | | 2 | GND | |
| 3 | J2_IO60 (4.7k pull-up) | D26 | 4 | J2_IO59 (4.7k pull-up) | C26 |
| 5 | J2_IO58 | B25 | 6 | J2_IO57 | B26 |
| 7 | J2_IO56 | F25 | 8 | J2_IO55 | E26 |
| 9 | J2_IO54 | E25 | 10 | J2_IO53 | D25 |
| 11 | J2_IO52 | D23 | 12 | J2_IO51 | D24 |
| 13 | J2_IO50 | E21 | 14 | J2_IO49 | E22 |
| 15 | J2_IO48 | A23 | 16 | J2_IO47 | A24 |
| 17 | J2_IO46 | D19 | 18 | J2_IO45 | D20 |

Bank 14/15 (HR, 3.3 V). Check pins 1/2 with a meter before wiring.

## UART to the supervisor (JP1 -> DUT1 cable)

Moved from J11 to JP1 on 2026-11-27 (owner: J10/J11 are kept for PMOD
microSD adapters).

| JP1 pin | K325T ball | Direction | Mimas P13 | Supervisor signal |
|---|---|---|---|---|
| 6 | B26 | K325T output (TX) | row 4 B | "UART from DUT (in)" |
| 4 | C26 | K325T input (RX; 4.7k pull-up on the board) | row 5 B | "UART to DUT (out)" |
| 2 | GND | | row 3 (A/B, already GND via the JTAG lead) | |

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
