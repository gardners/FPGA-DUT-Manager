#!/usr/bin/env bash
# Check (and with --install, apt-get install) the system packages needed to
# build the toolchain in tools/. Everything else is built from source.
set -euo pipefail

PKGS=(build-essential git ca-certificates curl cmake pkg-config bison flex gawk
	autoconf automake python3 python3-dev python3-venv default-jre-headless uuid-dev
	libboost-filesystem-dev libboost-iostreams-dev libboost-thread-dev
	libboost-program-options-dev libboost-python-dev libeigen3-dev
	libreadline-dev zlib1g-dev tcl-dev libffi-dev
	gnat llvm-dev libzstd-dev
	libftdi1-dev libusb-1.0-0-dev libudev-dev)

missing=()
for p in "${PKGS[@]}"; do
	if [[ $(dpkg-query -W -f='${Status}' "$p" 2>/dev/null || true) != 'install ok installed' ]]; then
		# Accept a versioned llvm-N-dev in place of llvm-dev.
		if [[ $p == llvm-dev ]] && dpkg-query -W -f='${Package}\n' 'llvm-*-dev' 2>/dev/null | grep -q .; then
			continue
		fi
		missing+=("$p")
	fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
	echo "All system build dependencies present."
	exit 0
fi

if [[ ${1:-} == --install ]]; then
	sudo apt-get update
	sudo apt-get install -y "${missing[@]}"
else
	echo "Missing system packages: ${missing[*]}" >&2
	echo "Run 'make deps' (uses sudo apt-get) or install them yourself." >&2
	exit 1
fi
