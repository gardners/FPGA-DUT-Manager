# 0041: Build and flash the relay controller with arduino-cli

Status: Open
Opened: 2026-11-25 (owner: "Let's do it with arduino-cli")

Install arduino-cli (plus the arduino:avr core) into the local toolchain
(`tools/`, git-ignored). Add Makefile targets to compile the sketch for
the Uno R3 and upload it (`make relay-fw`, `make relay-flash PORT=...`),
then bring it up on the bench with `dutctl relay`.

Power (owner): the Uno is fed 5 V into its DC barrel from a PC supply.
See the notes below about the barrel input.

## 2026-11-25 progress (lead)

* `make relay-fw` / `make relay-flash PORT=/dev/ttyACM0` use the system
  arduino-cli (Ubuntu package 1.2.2), falling back to a downloaded copy in
  `tools/`. The arduino:avr core (1.8.8) is kept in `tools/arduino`. The
  sketch uses 6768 B of flash (20%) and 827 B of RAM (40%).
* Flashed to the Uno R3 on /dev/ttyACM0 (USB serial 851383130343518102C2).
  VERSION, STATUS, ALL OFF and the error reply all work over USB serial.
  No relay has been switched yet (waiting for the owner's wiring).
* Fixed two `dutctl relay` bugs found on the bench:
  - The request id came from `time()` in whole seconds, so two calls in
    one second reused it and the controller answered the second from its
    duplicate cache without running it (`ALL OFF` returned the previous
    STATUS reply). The id now mixes microseconds and the pid.
  - The first open resets the Uno (DTR), losing the command. dutctl now
    resends the same line (same id, so a command is never run twice) after
    0.4 s or straight after `EVENT BOOT`, for up to 4 s. After a forced
    reset the first command now answers in 0.68 s.
* Power (owner): the Uno is fed 5 V into its DC barrel from a PC supply.
