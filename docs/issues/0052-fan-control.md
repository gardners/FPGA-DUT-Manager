# 0052: Fan control: up to 8 PWM fans on the power board

Status: open (owner request 2026-11-27). Related: 0047 (power board), 0051
(rack layout).

## Request (owner, 2026-11-27)

* Large, quiet 12 V fans with PWM speed control, through spare GPIOs or an
  I2C fan controller.
* Fan headers on the power board, each with a small eFuse (or similar
  protection). Allow up to **8 fans**.

## Current state

The power main board (0047) has two 3-pin headers (J23/J24) in the
always-on group with series resistors for a fixed slow-down. There is no
speed control. The master rocker already switches the always-on group, so the
fans go off with everything else.

## Proposal (lead, 2026-11-27)

* **8 x standard 4-pin PWM headers** (GND, +12 V, TACH, PWM). 3-pin fans plug
  into them and run at full speed (or through the existing resistor option).
* **Control over I2C, not FPGA pins.** The shield's pins are all used (0049),
  and the power board already has the J5 I2C header (GND, 3V3, SDA, SCL,
  /INT). The supervisor talks to it through the shield's I2C bus, on the same
  bus as the expanders (0049 step 2). The fan policy (a temperature curve)
  lives in the host or in a small fixed FPGA state machine, with a safe
  default: if the I2C master never writes, the fans run at a fixed
  quiet-but-safe duty (the controller's power-on default, set by a strap or
  resistor).
* **Controller: requirements**
  * 25 kHz PWM (the Intel 4-pin spec; ~1.5 kHz LED drivers such as the
    PCA9685 make fans whine);
  * a tach input per fan;
  * pad-free package (SSOP/TSSOP/MSOP/SOIC), JLC-stockable;
  * an I2C address that is free (shield 0x20/0x22, front panel 0x25/0x26).
* **Candidates to check** (packages and stock not yet verified):
  * Microchip EMC2301/EMC2302 (1-2 fans, MSOP);
  * EMC2305 (5 fans, but probably QFN with a pad, so likely out);
  * MAX31790 (6 fans, TQFN with a pad, likely out).

  If no pad-free part covers 8 fans, run 2-4 PWM banks from MSOP controllers
  and read every tach.
* **Protection per header:**
  * Recommended: a 0.5 A PTC (1206/1812 resettable fuse) per header, plus
    the already fused always-on group. That's cheaper and smaller than eight
    eFuses, and a stalled or shorted fan cannot hurt the shared rail.
  * If you want real eFuses, a small pad-free one must be found first.
    Most small eFuses are WSON/QFN with a pad.
* **Temperature sensing** (from 0051's fire assessment): an I2C sensor on the
  power main board next to the input FETs (for example a TMP102-class or
  LM75-class part in a pad-free package), so the supervisor can report
  temperature, raise fan speed and cut DUT power on over-temperature.
* The always-on group budget grows by 8 fans x ~0.1-0.3 A. That's fine
  within its 5 A eFuse, but recheck it against the Mimas, GS105 and USB-hub
  load (0051).

## Questions for the owner

* PTC per header (recommended) or eFuse per header?
* Are all 8 fans on the KVM power board, or do some go to shelves on longer
  leads (0051 Q3)?
