# dutctl - host CLI for the Mimas A7 DUT supervisors
REPO   := $(abspath ../..)
BUILD  := build
CC     ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra -Werror -Iinclude
LDLIBS += -lm

LIB_SRC := src/dutproto.c src/uartstream.c src/xvc.c src/rasterframe.c src/pngwrite.c src/screenshot.c \
           src/dutconf.c src/jtagdisc.c src/jtagspeed.c
LIB_OBJ := $(LIB_SRC:src/%.c=$(BUILD)/%.o)

.PHONY: all test clean install
all: $(BUILD)/dutctl

$(BUILD)/%.o: src/%.c include/*.h | $(BUILD)
	$(CC) $(CFLAGS) -D_GNU_SOURCE -c -o $@ $<

# openFPGALoader fallback when it is not on $PATH: this repo's tools/
$(BUILD)/main.o: src/main.c include/*.h | $(BUILD)
	$(CC) $(CFLAGS) -D_GNU_SOURCE -DDUTCTL_REPO_OFL='"$(REPO)/tools/prefix/bin/openFPGALoader"' -c -o $@ $<

$(BUILD)/dutctl: $(BUILD)/main.o $(LIB_OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD)/test_main: tests/test_main.c $(LIB_OBJ) include/*.h | $(BUILD)
	$(CC) $(CFLAGS) -fsanitize=address,undefined -o $@ tests/test_main.c $(LIB_SRC) $(LDLIBS)

$(BUILD)/vectors.txt: $(REPO)/tests/gen_proto_vectors.py $(REPO)/tests/netproto.py | $(BUILD)
	python3 -I $< $@

test: $(BUILD)/test_main $(BUILD)/vectors.txt $(BUILD)/dutctl
	$(BUILD)/test_main $(BUILD)/vectors.txt $(BUILD)/test.png
	python3 -I tests/check_png.py $(BUILD)/test.png

$(BUILD):
	mkdir -p $@

install: $(BUILD)/dutctl
	install -D -m755 $< $(DESTDIR)$(HOME)/.local/bin/dutctl

clean:
	rm -rf $(BUILD)
