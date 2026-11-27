# FPGA-DUT-Manager top-level Makefile
#
# From a fresh checkout:
#   make deps        # (once, uses sudo apt-get) system packages
#   make toolchain   # build pinned nvc, GHDL, yosys+ghdl plugin, nextpnr,
#                    # prjxray, openFPGALoader and the xc7a50t chipdb into tools/
#   make test        # all VHDL unit tests (nvc) and C host-tool tests
#   make bitstream   # FLOW=vivado (default): build/vivado/supervisor.bit
#                    # FLOW=openxc7: build/mimas_a7/supervisor.bit
#   make jtagload    # load bitstream into FPGA SRAM over the Mimas USB JTAG
#   make flash       # write bitstream to the Mimas SPI flash
#   make dutctl      # build the Linux control CLI
#   make vivado      # same as make bitstream FLOW=vivado (needs Vivado)
#   make pcb-routing # autoroute generated PCBs whose generator changed (Freerouting)
#
# JOBS controls toolchain compile parallelism (default: min(nproc/2, free GB/3)).

SHELL      := /bin/bash
REPO       := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TOOLS      := $(REPO)/tools
PREFIX     := $(TOOLS)/prefix
STAMPS     := $(TOOLS)/stamps
BUILD      := $(REPO)/build
# JOBS: empty = scripts/build-toolchain.sh picks min(nproc/2, available GB / 3)
JOBS       ?=
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
.PHONY: vivado all help deps toolchain test test-hdl test-sw bitstream jtagload jtagload-good flash relay-fw relay-flash \
        detect dutctl list-boards check-board clean distclean pcb-routing

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
TOOL_STEPS := nvc openfpgaloader yosys prjxray nextpnr ghdl ghdl-plugin chipdb

$(STAMPS)/nvc:            | $(STAMPS)/deps
$(STAMPS)/openfpgaloader: | $(STAMPS)/deps
$(STAMPS)/yosys:          | $(STAMPS)/deps
$(STAMPS)/prjxray:        $(STAMPS)/yosys
$(STAMPS)/nextpnr:        $(STAMPS)/prjxray
$(STAMPS)/ghdl:           | $(STAMPS)/deps
$(STAMPS)/ghdl-plugin:    $(STAMPS)/ghdl $(STAMPS)/yosys
$(STAMPS)/chipdb:         $(STAMPS)/nextpnr

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
	python3 -I $(REPO)/tests/netproto.py
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

# Default flow is Vivado (owner decision 2026-11-25, ADR 0001); the
# open-source flow remains available with FLOW=openxc7.
FLOW ?= vivado
ifeq ($(FLOW),vivado)
DEFAULT_BIT := $(BUILD)/vivado/supervisor.bit
bitstream: vivado
else
DEFAULT_BIT := $(BITDIR)/supervisor.bit
bitstream: $(BITDIR)/supervisor.bit
	@ls -l $<
endif

# Vivado build (timing sign-off / alternative bitstream) on a machine with
# Vivado installed; needs nothing from tools/. VIVADODIR may point at the
# install (see scripts/vivado_wrapper).
vivado:
	@mkdir -p $(BUILD)/vivado
	@rm -f $(BUILD)/vivado/timing_verdict.txt $(BUILD)/vivado/supervisor.bit
	cd $(BUILD)/vivado && $(REPO)/scripts/vivado_wrapper -mode batch -notrace \
	    -log vivado.log -journal vivado.jou -source $(REPO)/vivado/build.tcl

# ---------------------------------------------------------------- board access
list-boards:
	@$(REPO)/scripts/find-mimas.sh --list

check-board:
	@$(REPO)/scripts/find-mimas.sh --require

detect: check-board | $(STAMPS)/openfpgaloader
	$(OFL) $(CABLE_ARGS) --detect

# BIT=path loads another bitstream (e.g. build/vivado/supervisor.bit)
BIT ?= $(DEFAULT_BIT)
jtagload: $(BIT) check-board | $(STAMPS)/openfpgaloader
	$(OFL) $(CABLE_ARGS) --write-sram $(BIT)

# last bitstream verified on hardware (see bits/README.md)
jtagload-good: check-board | $(STAMPS)/openfpgaloader
	$(OFL) $(CABLE_ARGS) --write-sram $(REPO)/bits/known-good.bit

flash: $(BIT) check-board | $(STAMPS)/openfpgaloader
	$(OFL) $(CABLE_ARGS) --write-flash $(BIT)

# ---------------------------------------------------------------- host software
dutctl:
	$(MAKE) -C $(REPO)/sw/dutctl

# ---------------------------------------------------------------- relay controller (issue 0041)
# The arduino:avr core is kept in tools/arduino (git-ignored).
# The system arduino-cli (e.g. the Ubuntu package) if installed, else a local copy.
ARDUINO_CLI ?= $(or $(shell command -v arduino-cli 2>/dev/null),$(REPO)/tools/prefix/bin/arduino-cli)
ARDUINO_ENV := ARDUINO_DIRECTORIES_DATA=$(REPO)/tools/arduino/data \
	ARDUINO_DIRECTORIES_DOWNLOADS=$(REPO)/tools/arduino/staging \
	ARDUINO_DIRECTORIES_USER=$(REPO)/tools/arduino/user
RELAY_FQBN ?= arduino:avr:uno
RELAY_OUT := $(BUILD)/firmware/relay-controller
PORT ?= /dev/ttyACM0
$(ARDUINO_CLI):
	mkdir -p $(REPO)/tools/dl/arduino-cli $(REPO)/tools/prefix/bin
	curl -fsSL -o $(REPO)/tools/dl/arduino-cli/ac.tgz \
	  https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Linux_64bit.tar.gz
	tar -C $(REPO)/tools/dl/arduino-cli -xzf $(REPO)/tools/dl/arduino-cli/ac.tgz arduino-cli
	cp $(REPO)/tools/dl/arduino-cli/arduino-cli $@
relay-fw: $(ARDUINO_CLI)
	$(ARDUINO_ENV) $(ARDUINO_CLI) core list | grep -q '^arduino:avr ' || \
	  { $(ARDUINO_ENV) $(ARDUINO_CLI) core update-index && $(ARDUINO_ENV) $(ARDUINO_CLI) core install arduino:avr; }
	$(ARDUINO_ENV) $(ARDUINO_CLI) compile -b $(RELAY_FQBN) --warnings all \
	  --output-dir $(RELAY_OUT) $(REPO)/firmware/relay-controller
relay-flash: relay-fw
	$(ARDUINO_ENV) $(ARDUINO_CLI) upload -b $(RELAY_FQBN) -p $(PORT) \
	  --input-dir $(RELAY_OUT) $(REPO)/firmware/relay-controller

# ---------------------------------------------------------------- PCB autorouting (issue 0050)
# Downloads a pinned Freerouting jar into tools/dl (git-ignored) and reroutes
# a generated board only when its generator scripts are newer than its
# tracks.json. Force a reroute with `make -B pcb-routing`. Needs java (21+) and the
# KiCad 10 flatpak (see hardware/*/tools/build_all.sh).
FREEROUTING_VERSION ?= 2.5.0
FREEROUTING_SHA256  ?= f6f51bb02245e8e717f9359bd260cc9c5c0b1bc0acc8b7cb2cd5b8ffeb5de3c7
FREEROUTING_JAR     ?= $(TOOLS)/dl/freerouting/freerouting-$(FREEROUTING_VERSION).jar
FRONT_PCB           := $(REPO)/hardware/mega-kvm-front
pcb-routing: $(FRONT_PCB)/tracks.json
$(FREEROUTING_JAR):
	mkdir -p $(dir $@)
	curl -fsSL -o $@.part \
	  https://github.com/freerouting/freerouting/releases/download/v$(FREEROUTING_VERSION)/freerouting-$(FREEROUTING_VERSION).jar
	echo "$(FREEROUTING_SHA256)  $@.part" | sha256sum -c --quiet
	mv $@.part $@
$(FRONT_PCB)/tracks.json: $(wildcard $(FRONT_PCB)/tools/*.py) $(FRONT_PCB)/tools/build_all.sh \
                          $(REPO)/scripts/route-front-panel.sh | $(FREEROUTING_JAR)
	$(REPO)/scripts/route-front-panel.sh $(FREEROUTING_JAR)
	touch $@

# ---------------------------------------------------------------- housekeeping
clean:
	rm -rf $(BUILD)
	$(MAKE) -C $(REPO)/sw/dutctl clean

# Removes the built toolchain too (hours to rebuild at JOBS=1).
distclean: clean
	rm -rf $(TOOLS)/prefix $(TOOLS)/src $(TOOLS)/stamps $(TOOLS)/chipdb $(TOOLS)/logs
