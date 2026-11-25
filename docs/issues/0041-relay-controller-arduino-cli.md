# 0041: Build and flash the relay controller with arduino-cli

Status: Open
Opened: 2026-11-25 (owner: "Let's do it with arduino-cli")

Install arduino-cli (plus the arduino:avr core) into the local toolchain
(`tools/`, git-ignored). Add Makefile targets to compile the sketch for
the Uno R3 and upload it (`make relay-fw`, `make relay-flash PORT=...`),
then bring it up on the bench with `dutctl relay`.

Power (owner): the Uno is fed 5 V into its DC barrel from a PC supply.
See the notes below about the barrel input.
