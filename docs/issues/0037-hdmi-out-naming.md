# 0037: HDMI OUT identity: SPD InfoFrame, then the monitor's EDID

Status: Open
Opened: 2026-11-25 (owner: "Both, but start with 1")

1. Send an SPD InfoFrame (CTA-861 Source Product Description, vendor "MEGA65",
   product "MEGA KVM" plus the connected machine) on HDMI OUT. This needs
   the transmitter to send HDMI data islands (preamble, guard bands, TERC4,
   BCH ECC) on the console path. Passthrough (DVI from the source) gets
   them too if practical. Otherwise SPD is sent on the console only.
   Monitors that ignore SPD must be unaffected.
2. Later: read the downstream monitor's EDID over HDMI OUT DDC (I2C
   master), report its name and modes to the host, and optionally pass it
   on to HDMI IN (US-09).
