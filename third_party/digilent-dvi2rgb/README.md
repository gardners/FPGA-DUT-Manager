# Digilent dvi2rgb (DVI 1.0 sink for Xilinx 7-series)

Imported for issue 0022 (HDMI/DVI capture input). Modified since (marked
"FPGA-DUT-Manager change" in the source; everything else is upstream):

* 2026-11-25, issue 0040, `src/dvi2rgb.vhd`: generic `kHdmiAware` (default
  false = upstream behaviour) and outputs `vid_pHdmi`, `vid_pIsland`. With
  `kHdmiAware` the video DE comes from our `hdl/src/video/hdmi_rx_period.vhd`
  (LGPL-2.1-or-later), which drops HDMI video guard bands and data islands
  from DE using the per-channel control decode, and takes HSYNC/VSYNC from
  the TERC4 characters inside data islands (upstream holds the last control
  value there, moving the HSYNC edge). The upstream `pHSync`/`pVSync`
  assignments moved into the `not kHdmiAware` branch.

* 2026-11-27, issue 0049 (shield header receivers): `TMDS_Clocking.vhd`
  generics `kPllBufg` (PLLE2_BASE + BUFG 5x/1x clocks instead of MMCM +
  BUFIO/BUFR), `kClkInBufg` (TMDS clock to the PLL through a BUFG),
  `kIodelayGroup` and `kIdelayCtrl` (IODELAY_GROUP as a VHDL attribute, the
  IDELAYCTRL optional); `TMDS_Decoder.vhd`/`InputSERDES.vhd` `kInvert`
  (per-lane P/N swap) and `kIodelayGroup`; `dvi2rgb.vhd` passes them
  through; `dvi2rgb.xdc` no longer sets IODELAY_GROUP (it put every
  instance in one group). Defaults keep the upstream behaviour.

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
