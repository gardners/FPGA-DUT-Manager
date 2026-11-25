# Digilent dvi2rgb (DVI 1.0 sink for Xilinx 7-series)

Imported for issue 0022 (HDMI/DVI capture input), unmodified.

* Upstream: https://github.com/Digilent/vivado-library, `ip/dvi2rgb/src`
* Commit: see `UPSTREAM_COMMIT`
* Licence: the source files carry a **BSD 3-clause** header (Copyright
  Digilent Incorporated, author Elod Gyorgy); the repository-level
  `LICENSE` is MIT. Both are permissive and compatible with this
  project's LGPL-2.1-or-later; keep the headers and `LICENSE` intact, and
  do not use Digilent's name to endorse this project.
* Vivado-only: instantiates UNISIM primitives (ISERDESE2, IDELAYE2,
  IDELAYCTRL, MMCME2_ADV, BUFR, BUFG); wrapped by
  `hdl/src/platform/xc7/hdmi_rx_xc7.vhd`. Used with kClkRange = 5 (pixel
  clock >= 25 MHz: the 27 MHz MEGA65 modes), kDebug = false (no ILA cores),
  kEmulateDDC = false for now (no EDID emulation; HPD is asserted).
* `src/dvi2rgb.xdc` is read scoped to the dvi2rgb module (`read_xdc -ref`).
