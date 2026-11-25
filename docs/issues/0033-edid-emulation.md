# 0033: EDID emulation on HDMI IN

Status: Open
Opened: 2026-11-25 (lead; design brief US-09)

HDMI IN currently releases DDC (no EDID) and asserts HPD. Real sources
(MEGA65, and later HewnWeb boards) may read EDID to choose a mode. Provide
an EDID advertising the 27 MHz modes we capture (720x480p60 and
720x576p50, DVI or HDMI as appropriate), served by dvi2rgb's DDC EEPROM
emulation (kEmulateDDC) or our own I2C slave, on the Mimas HDMI IN DDC pins
(SCL J2, SDA H2). Later (US-09): host-settable EDID and HPD control via
management.
