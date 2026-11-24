# Native unit tests for the relay controller logic (the sketch itself is
# built with the Arduino IDE / arduino-cli for Uno or Nano).
BUILD := ../../build/firmware
.PHONY: test
test: $(BUILD)/test_relay_core
	$(BUILD)/test_relay_core
$(BUILD)/test_relay_core: test/test_relay_core.cpp relay_core.h
	mkdir -p $(BUILD)
	g++ -std=c++11 -Wall -Wextra -Werror -Wno-format-truncation -fsanitize=address,undefined -o $@ $<
