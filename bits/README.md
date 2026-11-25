# Known-good bitstreams (Vivado, SRAM load over JTAG)

Kept outside `build/` so `make clean` does not remove them. The `.bit` files
are git-ignored; this index is tracked. Load with

    make jtagload-good                      # bits/known-good.bit
    make jtagload BIT=bits/supervisor-<id>.bit

Board must run from the DC jack (USB power alone browns out).

| Build id | Commit | Verified on hardware (2026-11-25) | Notes |
|---|---|---|---|
| cf46426d | cf46426 | hwtest --quick PASS | **known-good**; select-mode double blink (0029) |
| 4e98bd9a | 4e98bd9 | **hwtest.sh 60 PASS / 0 FAIL** | mgmt bad-length codes, caps b3 |
| d3db353e | d3db353 | hwcheck PASS; HDMI loopback locked 720x480 of 858x525 27.000 MHz; console-screen 0-3 forced and reported | KVM hotkey + three console screens (0029) |
| e59d3351 | e59d335 | hwcheck PASS; `video none` with no source | HDMI IN receiver (dvi2rgb) + video block, untested with a source |
| b568335d | b568335 | hwcheck PASS; kbd-leds / kbd-led-rgb keys acked, bad value rejected | physical keyboard LED mode keys |
| 98e1fce8 | 98e1fce | hwcheck PASS both DUTs; MK-I keyboard detected; DNA read | keyboard power-LED status, device DNA |
| 41289d54 | 41289d5 | hwcheck PASS both DUTs | checksum pipelined, WNS +0.28 ns |
| a9a18703 | a9a1870 | hwcheck PASS both DUTs; hunter idle (phase 0, 0 bad) | RX phase hunter (0028); harness columns swapped (ADR 0008 am. 5) |
| 198c4519 | 198c451 | hwcheck PASS both DUTs | timing MET; keyboard pin 2 in column B (row 22 B sense / 15 B supply) |
| 681af897 | 681af89 | hwcheck PASS both DUTs | timing MET; keyboard blocks reversed (ADR 0008 am. 4) |
| 8efc02b0 | 8efc02b | hwcheck PASS both DUTs | timing MET; keyboard blocks mirror J5 (ADR 0008 am. 3) |
| e54a2e92 | e54a2e9 | hwcheck PASS both DUTs | all timing MET (RX constrained to measured eye); jumper-strip wiring (ADR 0008 am. 2); MEGA KVM boot screen |
| 83113773 | 8311377 | hwcheck PASS both DUTs; 200-ping burst 0% loss | timing MET (internal); RGMII RX MMCM at 123.75 deg |
| cd2f921d | cd2f921 | DHCP both DUTs (0 / 0x10), heartbeats, console position OK | keyboard pins on P12 rows 6-9; 480p60; WNS -0.42 |
| a4b00fb9 | a4b00fb | DHCP both DUTs, ping, seg7 `0-10` | console LEFT 18 (3 px too far right) |
| 6e7991b4 | 6e7991b | DHCP, heartbeats (DUT 0 only, old ID scheme) | 480p60, LEFT 0 (left edge cropped) |
| da7897a1 | da7897a | DHCP, heartbeats, ping, mgmt, text | 576p50, old ID scheme |
