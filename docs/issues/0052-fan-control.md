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

## 2026-11-27 owner answers (round 10)

* Fan protection: **eFuses if they are cheap** (and pad-free, JLC-stocked),
  otherwise resettable fuses. Agent to search; PTC is the fallback.
* 8 fans: 2 on the KVM front panel, and 3 on each of two shelf fan plates on
  long leads (0051). All 120 mm, 12 V, 4-pin PWM preferred.
* With two fan groups in different places, at least three PWM channels are
  useful (KVM pair, shelf group A, shelf group B), with tach read on every fan.

## 2026-11-27 progress: fan control on the power main board (agent, feature/power-fans)

Details, register-level usage and the part comparison are in
`docs/hardware/power-board.md`, section "Fans, I2C and temperature".

* **Headers:** J23/J24 replaced by **8 x Molex 47053-1000 4-pin PWM headers**
  (J30-J37, C240840) on the always-on group (the master rocker still switches
  them). FAN0-1 KVM front panel, FAN2-4 shelf plate A, FAN5-7 shelf plate B.
* **Controller:** no pad-free part covers 8 fans (EMC2303/2305 and MAX31790
  have exposed pads; ADT747x have too few tachs and no stock). Chosen:
  **4 x Microchip EMC2302-1-AIZL-TR** (MSOP-10, no pad, C626969, 217 in
  stock, $3.14 at 1-9) behind a **TCA9548APWR** I2C switch (0x70, C130026,
  $0.70), because the EMC2302 address is fixed (0x2E). One PWM (26 kHz) and
  one tach per fan: 8 independent channels. No MCU needed.
* **Safe default = 100 %:** each PWM goes through a 2N7002 inverter (gate
  pull-down), so a controller that is unpowered, at its power-on default
  (00h, open drain), stuck behind the mux, or whose 4 s watchdog fired,
  leaves every fan at full speed. The host sets PWM push-pull (2Bh = 03h),
  inverted polarity (2Ah = 03h) and WD_EN (20h = 60h), then writes duty to
  30h/40h and reads tach from 3Eh-3Fh/4Eh-4Fh.
* **Protection:** **Infineon BSP452** smart high-side switch per header
  (SOT-223, C58074, 24k in stock, $1.53 at 1-9 / $1.26 at 10+; limit
  0.7-2.4 A, thermal auto-restart). Small 12 V eFuses only come in pad
  packages. Against a 0.5 A PTC (C720075, $0.03): about $10 more per board,
  but a shorted fan lead is limited in microseconds and never pulls the
  always-on group (Mimas, GS105) into its 5 A limit; with a PTC it would reset
  the Mimas boards before the PTC trips. Swapping to PTCs later is a small
  change.
* **Temperature:** TMP75AIDR (SOIC-8, C30389, $0.29) at **0x48** on the main
  board (eFuse area) and at **0x49** on the input board between the banana
  FET columns. The FETs are on the input board, so it needs its own sensor:
  J6 (main) to J8 (input), JST XH 5-pin (GND, 3V3, SDA, SCL, /ALERT). All
  ALERTs wire-OR onto /INT (J5 pin 5).
* Main board grows to **230 x 80 mm** (fan block on the right). STATUS J4
  is now 1x10 (tach is read over I2C).
* ERC 0 on all three schematics; DRC 0 on both boards with schematic parity
  (unrouted only). BOM and CPL CSVs in `hardware/mega-kvm-power/out/`.

For the owner:
* BSP452 (default) or PTC per header?
* Please measure the always-on group's master-on inrush with 8 fans at
  100 % plus both Mimas boards: if it trips the 5 A limit, raise R182's
  limit or feed the fan switches from VBUS.
