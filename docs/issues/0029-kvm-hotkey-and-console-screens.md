# 0029: KVM hotkey on the physical keyboard; three console screens

Status: Open
Opened: 2026-11-25 (owner request)

Despite policy living in the host, a small local selector is worth having
in the FPGA so the bench keyboard/monitor work without a server.

**Hotkey.** Left SHIFT + right SHIFT held >= 1 s, then tap MEGA: disconnect
the physical keyboard and the monitor from the current DUT and wait for a
digit 1-9, 0 selecting among the first 10 ordinal DUTs (machine numbers
0-9, as used for the keyboard power-LED colours; 0 = the tenth). Then
connect keyboard + video to that DUT. The hotkey keys themselves must not
reach any DUT while it is being recognised (to decide: suppress SHIFTs
after the 1 s hold, or only MEGA and the digit).

**Three console screens** (text_display), each its own screen RAM
(80x25 chars + attrs + palette per screen; more BRAM):
1. *Editable* — the existing host-written screen (TEXT_WRITE, port 6508).
2. *No video* — shown instead of the editable screen when the selected
   DUT has no video signal (centred reverse-video message, footer).
3. *Select* — "Select device under test to connect to", shown while a
   selection is pending: digits 1-9, 0 in reverse-video boxes, the digit
   replaced by a frowning face (CP437 0x02-style glyph, to choose) when no
   device occupies that slot; auto-updated by the FPGA from what it knows
   about the slots (phase 1: this board's two DUTs; chain later).

**Protocol.**
* Heartbeat reports which screen is displayed (0 editable, 1 no video,
  2 select) — new field (ADR 0005; candidate: link-block reserved byte or a
  board-block byte).
* Management: key to request a screen (force editable / no video / select,
  or auto); TEXT_WRITE gets a screen selector so the host can edit all
  three (address space or header field — decide in ADR 0012 amendment).

**Questions for the owner.** Hold time exactly 1 s and MEGA as a tap
(press+release)? Should ESC (or timeout) cancel the selection and return to
the previous DUT? Which glyph for "no device"?

## 2026-11-25 owner answers / decisions

* All keys pass through to the DUT (double SHIFT + MEGA was chosen because
  almost no software cares about those presses): no suppression.
* Hold >= 1 s then MEGA as a tap (press + release); ESC or 10 s without a
  choice cancels and returns to the previous DUT (lead defaults, owner did
  not object).
* Digits in keyboard order **1 2 3 4 5 6 7 8 9 0** both on screen and as
  keys: key "1" = machine 0 ... key "0" = machine 9.
* Each choice's reverse-video box is drawn in that machine's power-LED colour
  (red, orange, yellow, green, blue, purple, white; half-bright from 7).
* "No device" = frowning face drawn into font code 0x7F (CP437 has none).
* Backgrounds differ: select screen black, no-video screen green-screen
  green, editable screen blue (default).

Implementation plan: text_display with 3 screens (chars/attrs/palette each,
screen number in TEXT_WRITE address bits 14:13), the select screen's boxes
drawn as an FPGA overlay (not RAM writes) from the slot-presence vector;
kvm_hotkey entity on the physical key bitmap; displayed screen = forced
(mgmt key) or select-pending / no-video / editable; heartbeat reports it.

## 2026-11-25 implemented (simulation)

text_display three screens + overlay (tb_text_screens), kvm_hotkey
(tb_kvm_hotkey), selection by hotkey in supervisor_core, auto screen choice,
key 0x0035, heartbeat byte 109, `dutctl set console-screen`, `dutctl text
--screen N`, `dutctl listen` shows the screen. Hardware test pending.
