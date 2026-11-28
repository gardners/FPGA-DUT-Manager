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
