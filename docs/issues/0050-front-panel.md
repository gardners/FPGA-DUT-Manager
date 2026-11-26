# 0050: Front panel PCB and display modes

Status: Open
Opened: 2026-11-27 (owner request)

Front panel of the MEGA-KVM case (0048):
* 16x2 HD44780 LCD with an I2C backpack (or 40x2 if similar in price);
* per DUT a red LED (powered) and a green LED (selected), for 8 DUTs;
* a few momentary buttons: input selection (next/previous) and mode
  (scan / fixed / PIP);
* master on/off rocker with backlight (wired to the power board, 0047).

A small PCB on the master shield's I2C header: an I2C expander (e.g.
TCA6424A or 2 x PCA9555/TCA9535) for 16 LEDs and the buttons, with
interrupt output; the LCD's backpack on the same bus. JLCPCB-assembled,
with LCSC parts.

Display modes (FPGA/host features, to design when the panel exists):
* **fixed:** today's behaviour (one selected DUT);
* **scan:** cycle through the DUTs that have video, with a settable dwell;
* **PIP:** selected DUT full screen plus small live inset(s) of others,
  reusing the thumbnail store (0035/0036).
