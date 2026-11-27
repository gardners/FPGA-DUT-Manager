# 0057: Controlled bring-up of the QMTECH XC7K325T board (DUT1)

Status: open (owner request 2026-11-27). Related: 0054 (JTAG), 0055 (power),
0056 (JTAG release when idle), docs/cabling/dut-cable.md section 4.

## Request (owner, 2026-11-27)

Task an agent with a controlled bring-up of the QMTECH XC7K325T core board
on its QMTECH daughter board, reached through supervisor DUT1 (P13 rows
3-7, endpoint 203.28.176.87) and powered by relay channel 5. dutctl can't
yet talk to this board's UART (the daughter board's UART is on its mini-USB
port), capture its screen, or reach its network. The owner will plug in a
VGA monitor, and will add two wires for a UART into the JTAG adaptor cable
if we allocate a pair of pins on the daughter board's J11. Start by counting
on the 3-digit 7-segment LED display.

## Known so far

* IDCODE 0x43651093 (XC7K325T rev 4) through DUT1, relay 5 on/off.
* Core board: QMTECH XC7K325T-1FFG676C, 50 MHz clock on F22, S25FL256L
  flash; header pinout in ~/Downloads/QMTECH_Kintex-7_XC7K325T_Core_Board_
  User_Manual(Hardware)_V01.pdf (headers U4/U5 match the A200T board's
  U4/U2 in position, pin 1 and power pins).
* JTAG outputs stay driven between transactions (0056): power the board off
  only after leaving TMS and TDI low, or unplug the lead.

## Progress (agent, 2026-11-27)

* **Docs**: core-board schematic, demo XDC and the DB_FPGA V04 schematic from
  github.com/ChinaQMTECH (QMTECH_XC7K325T_CORE_BOARD, DB_FPGA), cross-checked
  with LiteX's `qmtech_xc7k325t` platform and `extensions/qmtech.py`. Pin map
  in `docs/hardware/qmtech-k325t.md`. DB net `J2_IOn` = core U5 pin n-2,
  `J3_IOn` = U4 pin n-2. All header pins HR 3.3 V; only the core keys
  (AF9/AF10, bank 33) are 1.8 V. The core board has 2 user LEDs (not 4);
  the DB adds 5 LEDs and 5 buttons.
* **UART allocation**: PMOD J11 pin 4 (D10) = K325T TX -> Mimas P13 row 4 B;
  J11 pin 10 (E10) = K325T RX <- P13 row 5 B; GND on J11 pin 5/11. 2 Mbaud
  8N1 (supervisor default).
* **Toolchain**: Vivado 2023.2 builds xc7k325tffg676-1 (licence file in
  ~/.Xilinx covers the 325T, "version limit 2023.10" info only). Bring-up
  design: 343 LUTs, WNS +13.9 ns. openXC7 not needed; not evaluated further.
* **JTAG speed**: `dutctl jtag-speed 203.28.176.87 1`: ok to half 3 (20.8 MHz),
  FAIL at half 2; recommended half 6 (10.4 MHz). Not saved (duts.conf is empty).
* **Flash image**: at power-on STAT = 0x401079fc, DONE = 1 (a factory image
  boots from SPI flash). Flash untouched.
* **Bug found (supervisor/dutctl)**: openFPGALoader over `dutctl xvc` stalled
  ("jtag: no response") on the first large shift. Bisected with raw XVC
  shifts: <= 7904 bits per JTAG_REQ works, >= 7912 bits gets no response
  (UDP payload > 2000 bytes; 24-byte header + 2 x 988 bytes). dutctl splits
  at DP_JTAG_MAX_BITS = 8192 and ADR 0005 allows 8192. Either the supervisor
  RX path drops frames over ~2046 bytes or the JTAG buffer is short; needs a
  fix in dutctl (chunk <= 7904) or the HDL (lead). Workaround:
  `targets/qmtech-k325t/xvc-split.py`.
* **Load**: `targets/qmtech-k325t/k325t.sh load` (dutctl xvc -> xvc-split ->
  openFPGALoader xvc-client, SRAM): 1.44 s for the 1.26 MB compressed
  bitstream, STAT afterwards 0x401079fc, DONE = 1.
* **Power-off** (19:1x): `k325t.sh off` parked TMS=TDI=0 (one TCK, TAP to
  Run-Test/Idle), relay 5 off; heartbeat then shows DUT1 `vio=0 out=0`, so
  no back-powering. The bring-up image is SRAM-only: after power-on the
  board runs its flash image again until `k325t.sh load`.
* Waiting for the owner: what the 7-seg/LEDs/VGA show, and the J11 UART wires.

### 2026-11-27 owner check and lead notes

* Owner: the 7-segment display counts on the K325T, and the 5 daughter-board
  LEDs count in binary at about 1 Hz. VGA not reported yet.
* The bring-up design was loaded by the lead over plain XVC (through the
  split proxy) on supervisor build cf8acc83 (idle JTAG parked low): load
  1.6 s, DONE=1.
* The owner hands power control of the K325T (relay channel 5) to the lead
  for the rest of the bring-up.
* **Relay channel 5 has a loose joint somewhere**: it turned the K325T off
  a few times while the owner was working near it. Expect occasional
  unexpected power loss (a JTAG request then answers "unpowered").
