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
