# Known-good bitstreams (Vivado, SRAM load over JTAG)

Kept outside `build/` so `make clean` does not remove them. The `.bit` files
are git-ignored; this index is tracked. Load with

    make jtagload-good                      # bits/known-good.bit
    make jtagload BIT=bits/supervisor-<id>.bit

Board must run from the DC jack (USB power alone browns out).

| Build id | Commit | Verified on hardware (2026-11-25) | Notes |
|---|---|---|---|
| aba06812 | aba0681 | 2026-11-27: hwtest 63/0 (DHCP both DUTs, real DVI source, passthrough); keyboard IDCODE 0x012ba043 via remote JTAG | timing pipelining (net_tx DHCP, dhcp_client, thumb_rx_writer, mosaic), MGMT dup compare; normal WNS +0.200 ns, shield build +0.276 ns. **known-good** |
| 88734375 | 8873437 | 2026-11-27: hwtest 63/0 (real DVI source on HDMI IN, passthrough); keyboard CPLD IDCODE 0x012ba043 over remote JTAG (`dutctl jtag-idcode IP --kbd`) | keyboard type 3 host + keyboard JTAG (0046), shield receivers off (SHIELD_RX=0), WNS +0.234 ns. |
| 6c2c91fd | 6c2c91f (main at cb5ca98, docs only on top) | hwtest 63/0 (caps 0x9F); select screen on the self-loop shows machine 1's live thumbnail (recursive picture), machine 0 colour bars, frowns for empty slots | **known-good**; thumbnails (0035) and Ethernet relay (0038) |
| 523dd029 | 523dd02 | hwtest 63/0; HDMI OUT now HDMI (SPD/AVI InfoFrames); self-loop measures 720x480 of 858x525 with HDMI+islands flags; raster 720x480 complete; DDR3 ok | HDMI OUT SPD/AVI (0037, monitor OSD not yet checked by owner), HDMI-aware receiver (0040) |
| c2b6d912 | c2b6d91 | hwtest 63/0; DDR3 calibrates, self-test 1 MiB 0 errors on both endpoints; select screen (console-screen 3) captured over the self-loop: 2x2 mosaic, colour bars for machines 0/1, frowns for empty slots | DDR3 frame store (0034), mosaic select screen (0036) |
| e7393132 | e739313 | hwtest 61/0; self-loop: passthrough attempts back off to 8 s, never latch; 600-frame capture 597 complete / 3 INCOMPLETE (no bogus sizes) | video passthrough (0032), stable geometry |
| c0fbba73 | c0fbba7 | hwtest.sh 61 PASS / 0 FAIL (EDID itself not readable on the loopback) | EDID "MEGA KVM" 480p60/576p50 on HDMI IN (0033) |
| d29ea748 | d29ea74 | **hwtest.sh 61 PASS / 0 FAIL incl. raster capture**; owner: one-handed hotkey works | no raster to broadcast; one-handed hotkey |
| 1bd43fca | 1bd43fc | hwcheck PASS; **HDMI loopback capture: complete 720x480 frames via dutctl video, pixel-exact colours** | raster capture (0023) |
| cf46426d | cf46426 | hwtest --quick PASS | select-mode double blink (0029) |
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
