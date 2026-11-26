# 0043: Second HDMI receiver on the expansion headers

Status: Open (investigation)
Opened: 2026-11-26 (owner request)

Each Mimas has one HDMI IN (bank 35, through the IP4776 buffer), so only one
of a board's two DUTs (the "video target") can be captured, passed through or
thumbnailed. The board's other video input is DisplayPort, which needs the GTP
transceivers and a DP sink (design brief O-12). The owner suggests skipping
DP and adding a second HDMI (DVI/TMDS) receiver on header pins.

## Why it looks possible

* The header banks (P12 = bank 15, P13 = bank 16) are fixed at 3.3 V
  (ADR 0003), and **TMDS_33** is a 7-series HR-bank input standard that needs
  VCCO = 3.3 V. The header pins are routed as true P/N pairs.
* At 720x480/576 the link runs at 27 MHz x 10 = 270 Mb/s per lane (3.7 ns
  per bit). dvi2rgb already aligns each lane on its own (IDELAY and bitslip),
  so a few centimetres of lane-to-lane skew is tolerable.
* **P13 rows 10-13 are unused** now (the physical keyboard sits on P12 rows
  10-14, and the DUT keyboards use rows 16-22). That gives four true pairs in
  bank 16, two of them clock-capable:

  | P13 row | Pair (A/B ball) | Ball type | Proposed |
  |---|---|---|---|
  | 10 | F18 / E18 | IO_L15 (DQS) | D0 |
  | 11 | C18 / C19 | IO_L13 **MRCC** | TMDS clock |
  | 12 | D17 / C17 | IO_L12 **MRCC** | D1 |
  | 13 | B20 / A20 | IO_L16 | D2 |
  | 14 | GND | | cable ground |

  The clock pair is on an MRCC pin in the same bank as the data pairs, so
  BUFIO/BUFR or a PLL can clock the ISERDESes there. The P/N polarity on the
  header may need swapping per lane; dvi2rgb can invert lanes in logic.
* DDC (SCL/SDA), HPD and +5V sense can use spare P13 pins (column B rows
  23-26 or 28-33). They are slow signals and don't need clock-capable pins.
  A second `ddc_edid` instance serves the same EDID.

## Problems to solve

1. **Termination.** TMDS_33 inputs have no internal termination. Each of the
   8 lines needs a 50 ohm pull-up to 3.3 V at the receiver. The on-board
   input has these through the IP4776. A small adapter is needed: an HDMI
   socket breakout plus 8 resistors and ESD protection.
2. **Signal integrity.** The header traces aren't impedance-controlled or
   length-matched. Dupont jumpers would be marginal; a short adapter that
   plugs straight onto rows 10-14 (2x5 IDC, like the old chain ribbon) with
   twisted or coax pairs to the HDMI socket is better. Measure the lock rate
   and TMDS error counts (hdmi_rx_period) with different cables.
3. **5 V side.** The source pulls DDC up to 5 V, and the FPGA pins aren't
   5 V tolerant: use a level shifter (PCA9306/BSS138) or clamp. HPD to the
   source can be 3.3 V through 1 k. Sense +5V (HDMI pin 18) with a divider.
4. **Clocking resources.** All 5 MMCMs are in use (DDR3 took the last one);
   3 PLLs are free. dvi2rgb currently uses an MMCM for the 5x serial clock,
   so it needs a PLLE2 variant (or the bank 16 CMT's PLL, if it is free).
   Check after placement which CMT is used.
5. **FPGA resources.** A second dvi2rgb, video_meas/hdmi_rx_period,
   capture-source mux, and a second thumb_capture or a muxed one. Build
   currently ~9.7 k LUTs / 20.5 BRAM of 32.6 k / 75, so it should fit.
6. **Conflicts.** P13 rows 10-13 were the chain up-link in ADR 0007. That pin
   plan is already broken by the keyboard moves (ADR 0008 amendment 4), so
   the chain will need re-planning anyway (issues 0011, 0044).

## Plan

1. Paper check: the Mimas V3 schematic for P13 rows 10-13 (series parts?
   trace lengths?) and Xilinx UG471 for TMDS_33 on HR banks with external
   termination.
2. Build a test bitstream with a second receiver on P13 rows 10-13 (generic
   `HDMI_RX2`, off by default), reporting lock, resolution and error counts in
   the heartbeat. Ask the owner for an adapter (breakout + resistors).
3. If it locks reliably: give the second DUT its own capture, passthrough
   source and live thumbnail. Make the heartbeat "video target" per DUT,
   and let dutctl screenshot use either DUT.

## 2026-11-26

The adapter becomes a small PCB that sits straight on the header: issue
0045.
