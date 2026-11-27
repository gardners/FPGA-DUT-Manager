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
