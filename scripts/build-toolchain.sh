#!/usr/bin/env bash
# Build the pinned open-source FPGA toolchain into tools/ inside this repo.
#
# Usage: scripts/build-toolchain.sh <component>
#   components: nvc openfpgaloader yosys prjxray nextpnr ghdl ghdl-plugin chipdb
#
# Environment:
#   JOBS    parallel compile jobs (default nproc; run one heavy build at a time
#           rather than several competing ones)
#   TOOLS   tools directory (default <repo>/tools)
#
# Every component is pinned to an exact tag or commit below. Bump them
# deliberately and record the change in docs/adrs/0001-toolchain.md.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS=${TOOLS:-$REPO_ROOT/tools}
PREFIX=$TOOLS/prefix
SRC=$TOOLS/src
# default: one job per 3 GB of available RAM, at most half the cores
# (nextpnr compiles can use 1-2 GB each and the owner's laptop is also in
# use; JOBS=10 exhausted its RAM on 2026-11-25)
if [[ -z ${JOBS:-} ]]; then
	avail_gb=$(awk '/MemAvailable/ {print int($2 / 1048576)}' /proc/meminfo)
	JOBS=$(( avail_gb / 3 ))
	(( JOBS > $(nproc) / 2 )) && JOBS=$(( $(nproc) / 2 ))
	(( JOBS < 1 )) && JOBS=1
fi

# ---- Pins -----------------------------------------------------------------
NVC_REPO=https://github.com/nickg/nvc.git
NVC_REV=r1.23.1
GHDL_REPO=https://github.com/ghdl/ghdl.git
GHDL_REV=v6.0.0
GHDL_PLUGIN_REPO=https://github.com/ghdl/ghdl-yosys-plugin.git
GHDL_PLUGIN_REV=c21051d6e5a18b70d0ef7ce398758d7fbec5068e
OFL_REPO=https://github.com/trabucayre/openFPGALoader.git
OFL_REV=v1.2.0
# openXC7 toolchain-sources-builder (BSD-3-Clause, Hans Baier et al.) pins
# yosys v0.71, openXC7/nextpnr, prjxray, prjxray-db and fpga-assembler.
OPENXC7_BUILDER_URL=https://raw.githubusercontent.com/openXC7/toolchain-installer/791f07bc0a2022dafc52a7a93e2516ef9ea0db94/toolchain-sources-builder.sh
# FPGA die for the chip database (part is xc7a50tfgg484-1)
CHIPDB_DIE=xc7a50t
# ---------------------------------------------------------------------------

mkdir -p "$PREFIX/bin" "$SRC"
export PATH="$PREFIX/bin:$PATH"

log() { printf '\n=== [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# clone_at <dir> <repo> <rev>: shallow-ish checkout of an exact rev
clone_at() {
	local dir=$1 repo=$2 rev=$3
	if [[ ! -d "$SRC/$dir/.git" ]]; then
		git clone --filter=blob:none "$repo" "$SRC/$dir"
	fi
	git -C "$SRC/$dir" fetch --tags origin
	git -C "$SRC/$dir" checkout --force "$rev"
	git -C "$SRC/$dir" submodule update --init --recursive
}

build_nvc() {
	log "nvc $NVC_REV"
	clone_at nvc "$NVC_REPO" "$NVC_REV"
	cd "$SRC/nvc"
	./autogen.sh
	rm -rf build && mkdir build && cd build
	local llvm_config
	llvm_config=$(command -v llvm-config || true)
	../configure --prefix="$PREFIX" --enable-tcl=no \
		${llvm_config:+--with-llvm="$llvm_config"}
	make -j"$JOBS"
	make install
	"$PREFIX/bin/nvc" --version
}

build_openfpgaloader() {
	log "openFPGALoader $OFL_REV"
	clone_at openFPGALoader "$OFL_REPO" "$OFL_REV"
	cd "$SRC/openFPGALoader"
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_CMSISDAP=OFF
	cmake --build build --parallel "$JOBS"
	cmake --install build
	"$PREFIX/bin/openFPGALoader" --Version || true
}

build_openxc7() {
	log "openXC7 (yosys, prjxray, prjxray-db, nextpnr, fpga-as)"
	local builder=$SRC/openxc7-builder.sh
	curl -fsSL -o "$builder.orig" "$OPENXC7_BUILDER_URL"
	# System packages are checked by scripts/check-deps.sh (and installed by
	# `make deps`), so stop the builder from calling sudo apt-get itself.
	sed -e 's/^\tcheck_dependencies$/\t: # deps checked by scripts\/check-deps.sh/' \
		"$builder.orig" > "$builder"
	# We only need yosys for VHDL (via GHDL) -> skip the bundled slang
	# SystemVerilog frontend and unit tests; they dominate a JOBS=1 build.
	sed -i -e 's|^\tcmake -S . -B build -DCMAKE_BUILD_TYPE=Release "\${CMAKE_OPTS\[@\]}"$|\tcmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DYOSYS_WITHOUT_SLANG=ON -DYOSYS_ENABLE_UNIT_TESTS=OFF "${CMAKE_OPTS[@]}"|' "$builder"
	grep -q 'YOSYS_WITHOUT_SLANG=ON' "$builder" || {
		echo "error: could not disable slang in openXC7 builder" >&2
		exit 1
	}
	grep -q 'deps checked by scripts' "$builder" || {
		echo "error: could not neutralise check_dependencies in openXC7 builder" >&2
		exit 1
	}
	mkdir -p "$SRC/openxc7"
}

# One openXC7 component per call, so an interrupted build only redoes that
# component (the builder wipes a component's build directory each run).
build_openxc7_part() {
	local part=$1
	[[ -f $SRC/openxc7-builder.sh ]] || build_openxc7
	log "openXC7 $part (JOBS=$JOBS)"
	cd "$SRC/openxc7"
	INSTALL_PREFIX="$PREFIX" JOBS="$JOBS" bash "$SRC/openxc7-builder.sh" "$part"
}

build_fpga_as() {
	log "fpga-as (optional, needs bazel download)"
	local builder=$SRC/openxc7-builder.sh
	cd "$SRC/openxc7"
	INSTALL_PREFIX="$PREFIX" JOBS="$JOBS" bash "$builder" fpga-as
}

build_ghdl() {
	log "GHDL $GHDL_REV (mcode backend, provides libghdl for synthesis)"
	clone_at ghdl "$GHDL_REPO" "$GHDL_REV"
	cd "$SRC/ghdl"
	rm -rf build && mkdir build && cd build
	../configure --prefix="$PREFIX"
	make -j"$JOBS"
	make install
	"$PREFIX/bin/ghdl" --version | head -1
}

build_ghdl_plugin() {
	log "ghdl-yosys-plugin $GHDL_PLUGIN_REV"
	clone_at ghdl-yosys-plugin "$GHDL_PLUGIN_REPO" "$GHDL_PLUGIN_REV"
	cd "$SRC/ghdl-yosys-plugin"
	make clean || true
	make -j"$JOBS" GHDL="$PREFIX/bin/ghdl" YOSYS_CONFIG="$PREFIX/bin/yosys-config"
	make install GHDL="$PREFIX/bin/ghdl" YOSYS_CONFIG="$PREFIX/bin/yosys-config"
	"$PREFIX/bin/yosys" -m ghdl -p 'help ghdl' >/dev/null
}

build_chipdb() {
	log "nextpnr chip database for $CHIPDB_DIE"
	# shellcheck disable=SC1091
	source "$PREFIX/export.sh" 2>/dev/null || true
	local gen=$PREFIX/share/nextpnr/himbaechel/uarch/xilinx/gen/xilinx_gen.py
	local db=$PREFIX/share/nextpnr/external/prjxray-db
	[[ -d $db ]] || db=$(dirname "$(find "$PREFIX" -maxdepth 6 -type d -name artix7 -path '*prjxray-db*' | head -1)")
	mkdir -p "$TOOLS/chipdb"
	"$PREFIX/venv/bin/python3" "$gen" --xray "$db/artix7" --device "$CHIPDB_DIE" \
		--bba "$TOOLS/chipdb/$CHIPDB_DIE.bba"
	"$PREFIX/bin/bbasm" -l "$TOOLS/chipdb/$CHIPDB_DIE.bba" "$TOOLS/chipdb/$CHIPDB_DIE.bin"
	rm -f "$TOOLS/chipdb/$CHIPDB_DIE.bba"
}

case "${1:-}" in
	nvc) build_nvc ;;
	openfpgaloader) build_openfpgaloader ;;
	openxc7) build_openxc7 ;;
	yosys|prjxray|nextpnr) build_openxc7_part "$1" ;;
	fpga-as) build_fpga_as ;;
	ghdl) build_ghdl ;;
	ghdl-plugin) build_ghdl_plugin ;;
	chipdb) build_chipdb ;;
	*) echo "usage: $0 {nvc|openfpgaloader|yosys|prjxray|nextpnr|fpga-as|ghdl|ghdl-plugin|chipdb}" >&2; exit 2 ;;
esac
