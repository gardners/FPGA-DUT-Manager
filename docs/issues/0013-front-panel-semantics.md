# 0013: Seven-segment and LED front panel semantics

Status: Open (phase 3)
Opened: 2026-11-25

Brief O-16: 8 green LEDs one-hot selected DUT (steady video / blink keyboard), seven-seg n oF m. Confirm on hardware.

## 2026-11-25

First hardware run (owner): video works; seven-segment showed garbage. Cause:
the segment pins are not in a..g order. V3.1 schematic sheet 12: 7SEG_0..7
-> G, F, A, B, DP, C, D, E (common anode, active low). Fixed in
seg7_status; digit order still to confirm on hardware.
