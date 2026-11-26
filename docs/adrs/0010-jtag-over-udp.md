# ADR 0010: JTAG engine and host XVC proxy

Status: Proposed (2026-11-25); agreed in the brief (§12, O-13).

## Decision

* FPGA: one `jtag_engine` per DUT, stop-and-wait, max 8192 bits per
  transaction, vectors held in one 2 KiB BRAM (TMS+TDI in) and 1 KiB (TDO out)
  per engine. Wire format in ADR 0005 §7.
* TCK generated from `clk_sys` with a half-period counter (≥2 cycles). TMS/TDI
  are updated just after TCK falls (and before the first rising edge), TDO is
  sampled on TCK rising, TCK idles low after the last bit. Exactly N rising
  edges per transaction (testbench counts them).
* Target power unsensed (VIO low) → request rejected without clocking
  (`aborted-unpowered`), outputs tri-stated.
* Host: `dutctl xvc --dut <ip> --port 2542` runs a standard XVC 1.0 server
  (TCP) and maps `shift:` to sequenced UDP requests, splitting >8192-bit
  shifts at bit boundaries with no extra edges. `getinfo:` advertises
  `xvcServer_v1.0:<maxbits>`; `settck:` maps to `tck_half_period`.
* m65 support for the Mimas FTDI (USB JTAG to the Mimas itself, not to DUTs)
  is a separate patch to mega65-tools (issue 0010).

## Amendment 2026-11-27 (issue 0046, ADR 0014): keyboard CPLD target

A third `jtag_engine` drives the physical keyboard's JTAG pins (J5 pins
3-7, P12 rows 13-11 B). JTAG_REQ flags b1 selects it on either endpoint;
JTAG_RESP byte 17 = 1 marks its responses. It is "powered" while a
keyboard is detected and for 10 s after the last detection or transaction,
or forced by MGMT key 0x0061. `dutctl jtag-idcode IP --kbd` and
`dutctl xvc IP --kbd` use it.
