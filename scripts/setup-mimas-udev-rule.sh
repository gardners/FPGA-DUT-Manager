#!/usr/bin/env bash
# Install a udev rule so that pre-V4 Numato Mimas A7 boards (USB 2a19:1009,
# an FT2232H with a Numato VID/PID) are usable without root:
#   * the USB device is accessible to the plugdev group / logged-in user
#     (openFPGALoader uses libftdi on FTDI channel B = USB interface 01 for
#     JTAG, per Numato's openocd config; libftdi detaches ftdi_sio itself), and
#   * ftdi_sio is told about the VID:PID so channel A (USB interface 00), the
#     board's user UART, appears as /dev/ttyUSBn with a stable
#     /dev/mimas-<usb-serial> symlink. Channel B's tty is left unlinked.
#
# Run once, then unplug and reinsert the board(s).
set -euo pipefail

RULE=/etc/udev/rules.d/99-mimas-a7.rules
VID=2a19
PID=1009

if [[ $EUID -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

cat > "$RULE" <<EOF
# Numato Mimas A7 (pre-V4, USB-B): FT2232H with Numato VID/PID.
# Installed by FPGA-DUT-Manager scripts/setup-mimas-udev-rule.sh
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="$VID", ATTR{idProduct}=="$PID", MODE="0664", GROUP="plugdev", TAG+="uaccess", RUN+="/bin/sh -c '/sbin/modprobe ftdi_sio; echo $VID $PID > /sys/bus/usb-serial/drivers/ftdi_sio/new_id 2>/dev/null || true'"
# FTDI channel A (USB interface 00) is the user UART; channel B (01) is JTAG.
SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="", IMPORT{builtin}="usb_id"
SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="$VID", ENV{ID_MODEL_ID}=="$PID", ENV{ID_USB_INTERFACE_NUM}=="00", MODE="0660", GROUP="dialout", SYMLINK+="mimas-\$env{ID_SERIAL_SHORT}"
EOF

udevadm control --reload-rules
echo "Installed $RULE."

# Bind now as well, so a reinsert is belt-and-braces rather than mandatory.
modprobe ftdi_sio
echo "$VID $PID" > /sys/bus/usb-serial/drivers/ftdi_sio/new_id 2>/dev/null || true

u=${SUDO_USER:-$USER}
for g in plugdev dialout; do
	if ! id -nG "$u" | grep -qw "$g"; then
		usermod -aG "$g" "$u"
		echo "Added $u to group $g (log out and in again to take effect)."
	fi
done

echo "Now unplug and reinsert each Mimas A7; expect /dev/mimas-<serial>."
ls -l /dev/mimas-* 2>/dev/null || true
