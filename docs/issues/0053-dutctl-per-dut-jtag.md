# 0053: dutctl per-DUT JTAG setup and USB JTAG adaptor discovery

Status: open (owner request 2026-11-27). Related: 0051 (separate shelves mean
mostly USB JTAG), 0054 (speed probe).

## Request (owner, 2026-11-27)

dutctl needs a per-DUT setup that knows whether a DUT uses the supervisor's
on-board JTAG ("octopus") or a dedicated USB JTAG adaptor, and a mode that
helps auto-discover which USB JTAG adaptor belongs to which DUT.

## Proposal (lead)

* **Per-DUT configuration file** (host side, e.g.
  `~/.config/dutctl/duts.conf`, plain `key = value` sections). The FPGA stays
  lean; this is host policy. Each DUT section has:
  * supervisor IP and DUT index;
  * `jtag = octopus | usb`;
  * for USB: the adaptor identity (USB serial plus vendor/product, and the
    FTDI channel), and the UART tty of the same adaptor (the TE0790 carries
    both);
  * for octopus: the measured safe TCK (from 0054).
* dutctl commands (`jtag-idcode`, `xvc`, m65 wrappers) look the DUT up and
  pick the transport. For USB, dutctl prints or launches the right
  openFPGALoader / m65 / hw_server arguments, or serves XVC itself.
* **Discovery mode** (`dutctl jtag-discover`):
  1. list the USB JTAG adaptors (FTDI 0403:6010/6014 and TE0790, Digilent;
     the Mimas 2a19:1009 is excluded);
  2. scan each adaptor's chain once (IDCODE);
  3. switch each DUT's power off in turn through the supervisor's eFuse
     control, rescan, and see which adaptor's chain disappears (TDO stuck,
     IDCODE 0 or all ones); switch it back on;
  4. write the mapping into the configuration file, after confirmation.

  Variant: hold a DUT in reset or watch its UART banner, for adaptors that
  stay powered with the target off. Power cycling DUTs needs the owner's
  consent at run time (`--yes`), because it interrupts work on them.
* The octopus path keeps working unchanged. `jtag = octopus` simply uses the
  existing jtag_engine with the configured TCK.

## Notes

* openFPGALoader and m65 both select an FTDI by serial number, so the
  mapping is enough to drive them.
* Adaptors without a unique serial (some clones) cannot be told apart after
  a replug. Discovery then also records the USB port path and warns about
  it.

## Progress

### 2026-11-27 (sub-agent, branch feature/dutctl-jtag)

Host side implemented in `sw/dutctl` (no HDL / protocol change):

* `src/dutconf.c`: the per-DUT file `~/.config/dutctl/duts.conf`
  (`$XDG_CONFIG_HOME`, `$DUTCTL_CONF`, global `--conf FILE`). `[name]`
  sections with `ip`, `dut`, `jtag = octopus|usb`, `tck_half`,
  `kbd_tck_half`, `usb_vid/usb_pid/usb_serial/ftdi_channel/usb_path/tty`,
  `cable`, `usb_freq`, `relay = TTY CHANNEL` (the power path: the existing
  relay controller, since the supervisor has no eFuse control in the
  protocol yet). Parser reports problems with line numbers; the writer edits
  the text in place (comments and unknown keys survive) and replaces the
  file atomically.
* `dutctl duts` lists the DUTs. `jtag-idcode`, `xvc` (and `jtag-speed`)
  take `IP [DUT]` or a DUT name. Octopus: the configured `tck_half` is used
  (`xvc`: as the fastest TCK that `settck` may pick); a DUT index goes into
  the header's dut field. USB: print the openFPGALoader line
  (`-c CABLE --ftdi-serial S --ftdi-channel N [--freq F] --detect` or
  `--xvc --port P`) plus m65's `-f SERIAL -l TTY`; `--exec` runs it.
* `dutctl jtag-discover` (`src/jtagdisc.c`, sysfs walk with the root as a
  parameter, `$DUTCTL_SYSFS_USB` to override): FTDI 0403:6010/6011/6014/6001,
  TE0790 (product string), Digilent (manufacturer string, and the Adept VID
  1443), Mimas 2a19:1009 excluded; interfaces with driver and ttyUSB.
  `--scan` reads chains with `openFPGALoader --detect` (channel 0 default,
  `--channel N`); FT232R only with `--all` (usually an Arduino-style serial
  port); adaptors carrying a configured relay tty are never scanned.
  `--power-cycle --yes [--dut NAME]... [--wait S] [--write]`: power off via
  the relay, rescan, find the one adaptor whose chain disappeared, power on,
  confirm it came back, propose `jtag = usb` + `usb_*` + `cable` + `tty`
  (the adaptor's other channel's tty, as on the TE0790), write after a y/N
  prompt or with `--write`. Adaptors without a serial are recorded by
  `usb_path` and scanned by `--busdev-num`, with a warning.
* Tests (`make -C sw/dutctl test`, 329 checks): config parse / errors /
  lookup / in-place writer / file round trip, a fake sysfs tree (TE0790,
  Digilent HS2, serial-less FT2232H, FT232R, Mimas and a root hub excluded,
  version-sorted port paths), openFPGALoader `--detect` parsing and command
  lines.

Limitations / not tested on hardware:
* No JTAG adaptor except an Arrow USB Blaster (an Intel cable, listed but
  never scanned) is attached to the build box, so `--scan` and
  `--power-cycle` have only been run against the fake tree; the power cycle
  was deliberately not run (no consent, and no DUT here). Needs an owner run
  with a TE0790 / FT2232H adaptor on a real DUT.
* Scanning an FTDI channel with openFPGALoader (libftdi) detaches ftdi_sio
  from that channel; its ttyUSB comes back only on replug. Channel 0 is
  JTAG on the usual adaptors, so the UART on channel 1 is unaffected.
* Adaptors that are powered by the target (VREF-only designs keep their USB
  side up) are fine; adaptors whose chain does not change when the DUT is
  off (e.g. a target that still answers on standby power) need the
  "hold in reset / watch the UART banner" variant, not implemented.
* `--ftdi-serial` is used (deprecated in newer openFPGALoader in favour of
  `--usb-serial-num`, but understood by both old and new versions).
