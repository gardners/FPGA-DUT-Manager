# FPGA-DUT-Manager top-level Makefile
#
# From a fresh checkout:
#   make deps        # (once, uses sudo apt-get) system packages
#   make toolchain   # build pinned nvc, GHDL, yosys+ghdl plugin, nextpnr,
#                    # prjxray, openFPGALoader and the xc7a50t chipdb into tools/
#   make test        # all VHDL unit tests (nvc) and C host-tool tests
#   make bitstream   # build/mimas_a7/supervisor.bit
#   make jtagload    # load bitstream into FPGA SRAM over the Mimas USB JTAG
#   make flash       # write bitstream to the Mimas SPI flash
#   make dutctl      # build the Linux control CLI
#
# JOBS controls compile parallelism for the toolchain build (default 1).

SHELL      := /bin/bash
REPO       := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TOOLS      := $(REPO)/tools
PREFIX     := $(TOOLS)/prefix
STAMPS     := $(TOOLS)/stamps
BUILD      := $(REPO)/build
JOBS       ?= 1
export JOBS TOOLS

# Use our own tools first.
export PATH := $(PREFIX)/venv/bin:$(PREFIX)/bin:$(PATH)

NVC        := $(PREFIX)/bin/nvc
YOSYS      := $(PREFIX)/bin/yosys
NEXTPNR    := $(PREFIX)/bin/nextpnr-himbaechel
OFL        := $(PREFIX)/bin/openFPGALoader
FASM2FRAMES:= $(PREFIX)/venv/bin/fasm2frames
FRAMES2BIT := $(PREFIX)/bin/xc7frames2bit

BOARD      ?= mimas_a7
PART       ?= xc7a50tfgg484-1
FAMILY     := artix7
CHIPDB     := $(TOOLS)/chipdb/xc7a50t.bin
PRJXRAY_DB  = $(firstword $(wildcard $(PREFIX)/share/nextpnr/external/prjxray-db $(TOOLS)/src/openxc7/prjxray-db))

# Mimas A7 pre-V4: FT2232H with Numato VID/PID. Channel A (interface 0) is the
# user UART; channel B (interface 1) is JTAG behind a buffer whose active-low
# OE_N is on DBUS6 (Numato openocd numato_mimasa7.cfg: init 0x0008 dir 0x004b).
# openFPGALoader knows this board as mimas_a7 (cable "numato" = 2a19:1009,
# interface B, low byte 0x08/dir 0x4b; flash via SPI bridge bitstream).
# The profile's default 30 MHz TCK reads a corrupt IDCODE on our board
# (issue 0002); 6 MHz is reliable.
JTAG_FREQ  ?= 6000000
CABLE_ARGS ?= -b mimas_a7 --freq $(JTAG_FREQ)
# Select a particular board with FTDI_SERIAL=<usb serial> when several are attached.
ifneq ($(FTDI_SERIAL),)
CABLE_ARGS += --ftdi-serial $(FTDI_SERIAL)
endif

.DELETE_ON_ERROR:
FORCE:
.PHONY: all help deps toolchain test test-hdl test-sw bitstream jtagload flash \
        detect dutctl list-boards check-board clean distclean

all: test bitstream dutctl

help:
	@sed -n '2,15p' $(REPO)/Makefile

# ---------------------------------------------------------------- toolchain
deps:
	$(REPO)/scripts/check-deps.sh --install

$(STAMPS)/deps:
	@mkdir -p $(STAMPS)
	$(REPO)/scripts/check-deps.sh
	@touch $@

# Order: nvc and openFPGALoader first (small, unblock simulation and board
# bring-up), then the big openXC7 stack, GHDL + plugin, then the chipdb.
TOOL_STEPS := nvc openfpgaloader openxc7 ghdl ghdl-plugin chipdb

$(STAMPS)/nvc:            | $(STAMPS)/deps
$(STAMPS)/openfpgaloader: | $(STAMPS)/deps
$(STAMPS)/openxc7:        | $(STAMPS)/deps
$(STAMPS)/ghdl:           | $(STAMPS)/deps
$(STAMPS)/ghdl-plugin:    $(STAMPS)/ghdl $(STAMPS)/openxc7
$(STAMPS)/chipdb:         $(STAMPS)/openxc7

$(addprefix $(STAMPS)/,$(TOOL_STEPS)):
	@mkdir -p $(STAMPS) $(TOOLS)/logs
	$(REPO)/scripts/build-toolchain.sh $(notdir $@) 2>&1 | tee $(TOOLS)/logs/$(notdir $@).log
	@touch $@

toolchain: $(addprefix $(STAMPS)/,$(TOOL_STEPS))
	@echo "Toolchain ready in $(PREFIX)"

# Individual entry points, e.g. `make tool-nvc`.
tool-%: $(STAMPS)/%
	@true

# ---------------------------------------------------------------- tests
include $(REPO)/hdl/sources.mk

test: test-hdl test-sw

test-hdl: $(STAMPS)/nvc
	$(REPO)/scripts/run-hdl-tests.sh $(TB)

test-sw:
	$(MAKE) -C $(REPO)/sw/dutctl test
	$(MAKE) -C $(REPO)/firmware/relay-controller test

# ---------------------------------------------------------------- bitstream
BITDIR := $(BUILD)/$(BOARD)
# 32-bit build id embedded in heartbeats: short git hash (+ 'd' if dirty -> top bit)
BUILD_ID ?= $(shell git -C $(REPO) rev-parse --short=8 HEAD 2>/dev/null || echo 00000000)
XDC    := $(REPO)/boards/$(BOARD)/$(BOARD).xdc

$(BITDIR)/build_id_pkg.vhd: FORCE
	@mkdir -p $(BITDIR)
	@printf 'library ieee;\nuse ieee.std_logic_1164.all;\npackage build_id_pkg is\n  constant BUILD_ID : std_logic_vector(31 downto 0) := x"%s";\nend package;\n' \
	    $(BUILD_ID) > $@.tmp
	@cmp -s $@.tmp $@ && rm $@.tmp || mv $@.tmp $@

$(BITDIR)/supervisor.json: $(SYNTH_SOURCES) $(BITDIR)/build_id_pkg.vhd $(REPO)/scripts/synth.ys.in | $(STAMPS)/ghdl-plugin
	@mkdir -p $(BITDIR)
	sed -e 's|@SOURCES@|$(BITDIR)/build_id_pkg.vhd $(strip $(SYNTH_SOURCES))|' -e 's|@TOP@|$(SYNTH_TOP)|' \
	    -e 's|@OUT@|$@|' $(REPO)/scripts/synth.ys.in > $(BITDIR)/synth.ys
	$(YOSYS) -m ghdl -l $(BITDIR)/yosys.log -s $(BITDIR)/synth.ys

$(BITDIR)/supervisor.fasm: $(BITDIR)/supervisor.json $(XDC) | $(STAMPS)/chipdb
	$(NEXTPNR) --device $(PART) --chipdb $(CHIPDB) -o xdc=$(XDC) \
	    --json $< -o fasm=$@ --log $(BITDIR)/nextpnr.log \
	    --report $(BITDIR)/report.json --threads 1

$(BITDIR)/supervisor.frames: $(BITDIR)/supervisor.fasm
	$(FASM2FRAMES) --part $(PART) --db-root $(PRJXRAY_DB)/$(FAMILY) $< > $@

$(BITDIR)/supervisor.bit: $(BITDIR)/supervisor.frames
	$(FRAMES2BIT) --part_file $(PRJXRAY_DB)/$(FAMILY)/$(PART)/part.yaml \
	    --part_name $(PART) --frm_file $< --output_file $@

bitstream: $(BITDIR)/supervisor.bit
	@ls -l $<

# ---------------------------------------------------------------- board access
list-boards:
	@$(REPO)/scripts/find-mimas.sh --list

check-board:
	@$(REPO)/scripts/find-mimas.sh --require

detect: check-board | $(STAMPS)/openfpgaloader
	$(OFL) $(CABLE_ARGS) --detect

jtagload: $(BITDIR)/supervisor.bit check-board | $(STAMPS)/openfpgaloader
	$(OFL) $(CABLE_ARGS) --write-sram $<

flash: $(BITDIR)/supervisor.bit check-board | $(STAMPS)/openfpgaloader
	$(OFL) $(CABLE_ARGS) --write-flash $<

# ---------------------------------------------------------------- host software
dutctl:
	$(MAKE) -C $(REPO)/sw/dutctl

# ---------------------------------------------------------------- housekeeping
clean:
	rm -rf $(BUILD)
	$(MAKE) -C $(REPO)/sw/dutctl clean

# Removes the built toolchain too (hours to rebuild at JOBS=1).
distclean: clean
	rm -rf $(TOOLS)/prefix $(TOOLS)/src $(TOOLS)/stamps $(TOOLS)/chipdb $(TOOLS)/logs
