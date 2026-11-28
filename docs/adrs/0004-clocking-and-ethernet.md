# ADR 0004: Clocking and RGMII Ethernet

Status: Proposed (2026-11-25)

## Context

RTL8211E with RXDLY/TXDLY strapped off: RGMII data and clock are edge aligned
in both directions at the PHY, so the FPGA must add ~2 ns (90° at 125 MHz) of
skew to TXC and to the RX capture clock. Only 1000BASE-T carries the raster
stream (~650 Mb/s); 10/100 operation is useless for this project.

## Decision

Clock domains (deliberately few):

| Domain | Source | Use |
|---|---|---|
| `clk_sys` 125 MHz | MMCM from 100 MHz H4 | Everything: MAC TX, packet engines, UART, JTAG, keyboard, chain control, front panel |
| `clk_tx90` 125 MHz +90° | same MMCM | ODDR that forwards RGMII TXC only |
| `clk_ref` 200 MHz | same MMCM | IDELAYCTRL |
| `clk_rx` 125 MHz | PHY RXC (W19, MRCC) via BUFG | RGMII IDDR capture → async FIFO into `clk_sys` |
| `clk_pix` (phase 2) | HDMI RX / chain clock | Video only, crosses via async FIFO |

* TX: IDDR/ODDR on all RGMII TX pins clocked by `clk_sys`; TXC = ODDR(1,0) on
  `clk_tx90`. MAC TX runs at one byte per `clk_sys` cycle (GMII-style 8-bit).
* RX: RXD/RX_CTL pass through IDELAYE2 (fixed tap, generic `RGMII_RX_IDELAY`,
  default 2.0 ns ≈ 26 taps at 78 ps); capture with IDDR on `clk_rx`. If the
  openXC7 flow cannot place IDELAYE2, fall back to an MMCM on RXC with a +90°
  output (generic `RGMII_RX_SKEW_MODE`). Tracked in issue 0004.
* The MAC is our own small RGMII/GMII MAC (preamble/SFD, FCS CRC-32, IFG,
  minimum frame padding) written for this project with structure informed by
  LiteEth (BSD-2) and HewnWeb's RMII byte pipeline. CRC uses the mega65-core
  style LFSR function regenerated for 8-bit data.
* PHY management: MDIO is used read-only to report BMSR link/autoneg and
  RTL8211E PHYSR (reg 0x11) speed/duplex in heartbeat. No register writes in
  phase 1. Heartbeat flags `link_not_1000` so a 100 Mb/s negotiation is
  obvious. PHY reset held ≥10 ms after configuration, then ≥30 ms before use.
* **Amendment (2026-11-28, issue 0070): speed detection and gigabit
  renegotiation without MDIO.** The design still drives no MDC/MDIO. RXC
  also feeds a BUFR (the RX MMCM only locks at 125 MHz) clocking a 3-bit
  divider; its top bit is synchronised into `clk_sys` and its transitions
  counted over 2^15 cycles (262 µs): >62.5 MHz = 1000, >8 MHz = 100,
  >0.5 MHz = 10, else none, debounced over 5 windows (`link_speed_meter`).
  If the link sits at 10/100 for 1 s, `gig_renegotiate` holds `phy_rst_n`
  low for 2 s (after the unchanged ~33 ms power-up reset), then allows 3 s
  plus a back-off of 0 / 2 / 10 / 30 / 60 s (60 s thereafter) before it
  judges again; 60 s of gigabit resets the back-off. While the PHY is held,
  the RX MMCM is held in reset too, and the RX phase hunter (issue 0028) is
  held in reset whenever the MMCM is unlocked, the link is not at gigabit or
  the PHY is held, so hunting always restarts from the default phase on a
  real 125 MHz clock. The speed and attempt count are in the heartbeat link
  block (ADR 0005 section 3a); the seven-segment display shows ` 100`,
  `  10` or `noLk` while the link is not at gigabit.
* Single physical PHY, two logical endpoints (DUT0, DUT1) each with own MAC
  and IPv4 address; ARP answers for both (ADR 0005).

## Compatibility note: V4 boards (KSZ9031)

No wire-level incompatibility: both PHYs are standard 1000BASE-T RGMII, so mixed
boards on one switch are fine and the UDP protocol is identical. FPGA-side
differences would be: different pin LOCs (separate board profile/XDC), RGMII
skew (KSZ9031 has programmable pad skews via MMD registers; default internal
delays differ, so the IDELAY/phase generics would change), speed status
register (KSZ9031 reg 0x1F vs RTL8211E 0x11) and reset/strap timing. The
board profile carries these as generics; V4 support is not planned.
