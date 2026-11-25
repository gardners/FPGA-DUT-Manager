# 0030: Physical keyboard LED status and LED ownership modes

Status: Done (2026-11-25; logged after implementation)
Opened: 2026-11-25 (owner requests)

* Power LED shows the connected machine: gentle red pulse when the selected
  DUT is not powered; red, orange, yellow, green, blue, purple, white for
  machine 0-6, half brightness for 7-13 (machine = 2 * DUT-ID nibble +
  half). Drive LEDs show the DUT's own. `hdl/src/kbd/kbd_led_status.vhd` +
  tb. Owner confirmed the red pulse on hardware.
* Management keys 0x0033 (mode: 0 status, 1 DUT pass-through, 2 host) and
  0x0034 (host LED vector, 12 bytes); `dutctl set kbd-leds` / `kbd-led-rgb`;
  ADR 0005 section 4. Acked / rejected correctly on hardware (b568335d).
