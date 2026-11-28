# 0070: Drop the link for 2 s and renegotiate when it comes up at 10/100

Status: open (owner, 2026-11-28). Related: 0018 (100 Mbit not supported:
gigabit only), 0028 (RGMII RX phase hunter), ADR 0004, ADR 0005 section 3a
(heartbeat link block), RTL8211E(G) datasheet v1.6 (docs/datasheets/).

## Owner (2026-11-28)

"If it comes up at 100M or 10M, we should disable the port for 2 seconds,
then turn it back on, so that it can hopefully renegotiate gigabit."

Context: on the new 2.5G switch (0.5 m leads) the switch showed the
supervisor's port at 100 Mbit; our MAC is gigabit-only (0018), so DHCP and
everything else failed silently until the owner forced the port to gig on
the switch.

## Design (lead)

* **Detect the speed without MDIO** (the design drives no MDC/MDIO today):
  count RGMII RX clock (RXC) edges against the 125 MHz system clock over a
  fixed window: ~125 MHz = 1000BASE-T, ~25 MHz = 100, ~2.5 MHz = 10, ~0 =
  no link / PHY in reset. Debounce over a few windows.
* **Renegotiate**: if the link has been up but not gigabit for ~1 s (after
  configuration and after each attempt), hold PHY reset (phy_rst_n low) for
  2 s, release, wait for the PHY to come out of reset and autonegotiate
  (~3-5 s), measure again. Back off (e.g. 2 s, then 10 s, 30 s, max 60 s
  between attempts) so a partner that really can only do 100 doesn't make
  the link flap forever; keep retrying slowly.
* The RX phase hunter (0028) must not fight it: ignore / suspend hunting
  while the speed is not gigabit or the PHY is in reset.
* **Report** in the heartbeat link block (byte 139 is reserved today, or
  new bytes): measured speed (0 none, 1 = 10, 2 = 100, 3 = 1000),
  renegotiation attempts since configuration. Of course the heartbeat only
  gets out at gigabit, so the counter shows after the fact how many tries
  it took. 7-segment: a short code while not at gigabit (e.g. `100`) so a
  person at the bench sees it.
* Possible later addition (not this issue): MDIO, to advertise 1000BASE-T
  only (and/or disable EEE) so a link partner can't pick 100 at all; the
  datasheet has the registers.

## Progress 2026-11-28 (agent, branch feature/gig-renegotiate)

Implemented, simulated and built (Vivado build `dfb35f76`: TIMING MET, WNS
+0.028 ns, WHS +0.050 ns; worst path is the existing rxmem -> net_rx one;
LUTs 66.9 %; 2 BUFR). Not yet on hardware.

* `hdl/src/net/link_speed_meter.vhd`: RXC -> BUFR (in `rgmii_xc7`, port
  `rxc_meas`; the RX MMCM cannot lock below 125 MHz) -> 3-bit divider; its
  MSB crosses into clk_sys through 2 flip-flops (one bit, so a stopped or
  floating RXC is harmless) and transitions are counted over 2^15 cycles
  (262 us): > 62.5 MHz = 3 (1000), > 8 MHz = 2 (100), > 0.5 MHz = 1 (10),
  else 0 (none). The speed changes after 5 equal windows (~1.3 ms).
* `hdl/src/net/gig_renegotiate.vhd`: after the unchanged power-up reset
  (~33 ms after the MMCM locks) it waits SETTLE 3 s, then if the speed is
  10/100 for 1 s without a break it holds the PHY in reset 2 s (`phy_hold`,
  registered into `phy_rst_n`), then waits 3 s + back-off before judging
  again. Back-off after attempt n of an episode: 2 s, 10 s, 30 s, then 60 s
  every time. So a 100-only partner loses the link at t = ~4 s, ~12 s,
  ~28 s, ~64 s, ~130 s, then every ~66 s. 60 s at gigabit ends the episode
  (next fault retries quickly again). Speed "none" neither triggers nor
  counts as good. Attempts counter saturates at 255.
* RX MMCM held in reset while the PHY is held; the RX phase hunter (0028)
  is held in reset while the MMCM is unlocked (previously: only reset on the
  relock edge), the speed is not 1000 or the PHY is held, so it cannot hunt
  on an absent/25 MHz clock and always restarts from the default phase.
* Heartbeat link block (ADR 0005 s3a): byte 138 `rx_link_flags` b3:2 =
  speed code, b4 = PHY held; byte 139 `rx_reneg` = attempts (was
  reserved). Speed code 0 on the wire = older build. dutctl `listen`
  prints `eth 1000M reneg N` (only when the code is non-zero), `--kv` adds
  `link_speed=` and `rx_reneg=`.
* Seven-segment: ` 100`, `  10`, `noLk` while not at gigabit (overrides
  `dHCP` and the IDs).
* Tests: `tb_link_speed` (meter at 125/123.5/25/2.5 MHz/stopped, a 40 us
  glitch, FSM timing/back-off/episode reset/no-link/disable/saturation),
  `tb_seg7_status` codes, `tb_supervisor_core` heartbeat check (speed 3,
  5 attempts), netproto selftest layout, dutctl vector `heartbeat_link`.

Unknowns for hardware: what RXC the RTL8211E drives with no cable (2.5 or
25 MHz, or stopped in link-down power saving). If it runs at 2.5/25 MHz
with the cable out, the board will show `  10`/` 100` and reset the PHY
with the back-off (harmless, at most once a minute after the first few);
MDIO (or RGMII in-band status) would tell link-down from 10/100 later.

## 2026-11-28 lead: merged and built

Merged into feature/foundation (246580b); make test green (43 HDL,
netproto selftest, 995 dutctl, 52 relay). Build **246580b6**: TIMING MET,
WNS +0.193 ns, WHS +0.020 ns. dutctl installed (decodes `eth 1000M reneg
N`), keeper restarted. Hardware test waits for the owner at the switch
(force the port to 100, watch the drop/retry, back to auto) and a hardweb
reload window.
