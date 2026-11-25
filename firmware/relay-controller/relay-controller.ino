// relay-controller.ino - USB serial control of a Jaycar XC4418 8-channel
// relay module (active-high inputs) for DUT 12 V power.
// Builds unchanged for Arduino Uno and Nano (ATmega328P). Protocol:
// docs/adrs/0009-power-relay-controller.md. 115200 8N1, '\n' terminated.
//
// Wiring (ADR 0009 "Wiring", owner 2026-11-25): eight consecutive digital
// lines D2..D9 -> XC4418 IN1..IN8 (on an Uno R3 that is a 6-way strip on
// D2..D7 plus a 2-way strip on D8..D9: the two digital headers have the
// odd 0.16" gap between D7 and D8), and a separate 2-way power strip from
// the Uno power header's adjacent 5V/GND pins to the relay board VCC/GND.
// D0/D1 (USB serial) and D13 (bootloader LED blinks) are deliberately
// unused. All 8 coils on draw about 0.6 A: more than the Uno's USB 5 V
// (500 mA polyfuse) can supply, see ADR 0009.
// Fit 10k pull-downs from each IN to GND so relays stay OFF while the
// Arduino resets or bootloads. Optional D10 -> transistor -> ATX PS_ON#.
// LGPL-2.1-or-later.
#include "relay_core.h"

#if defined(ARDUINO_AVR_NANO) || defined(ARDUINO_AVR_UNO) || defined(ARDUINO_AVR_DUEMILANOVE)
// identical pin capabilities on Uno and Nano
#endif

static const uint8_t RELAY_PINS[RELAY_CHANNELS] = {2, 3, 4, 5, 6, 7, 8, 9};
static const uint8_t PSU_PIN = 10;          // HIGH = assert PS_ON# via NPN
static const bool RELAY_ACTIVE_HIGH = true;  // XC4418: HIGH energises the relay

static RelayCore core;
static uint8_t applied_mask = 0xFF;
static uint8_t applied_psu = 0xFF;

static void apply_outputs() {
  if (core.mask != applied_mask) {
    for (uint8_t i = 0; i < RELAY_CHANNELS; i++) {
      bool on = core.mask & (1u << i);
      digitalWrite(RELAY_PINS[i], (on == RELAY_ACTIVE_HIGH) ? HIGH : LOW);
    }
    applied_mask = core.mask;
  }
  if (core.psu != applied_psu) {
    digitalWrite(PSU_PIN, core.psu ? HIGH : LOW);
    applied_psu = core.psu;
  }
}

void setup() {
  // Drive the latch to OFF before enabling the outputs.
  for (uint8_t i = 0; i < RELAY_CHANNELS; i++) {
    digitalWrite(RELAY_PINS[i], RELAY_ACTIVE_HIGH ? LOW : HIGH);
    pinMode(RELAY_PINS[i], OUTPUT);
  }
  digitalWrite(PSU_PIN, LOW);
  pinMode(PSU_PIN, OUTPUT);
  relay_init(&core);
  apply_outputs();
  Serial.begin(115200);
  Serial.println(F("EVENT BOOT relay-controller 1 MASK 00"));
}

void loop() {
  while (Serial.available()) {
    int r = relay_feed(&core, (char)Serial.read());
    if (r == 1) {
      char reply[RELAY_REPLY_MAX];
      relay_exec(&core, core.line, millis(), reply, sizeof reply);
      apply_outputs();
      Serial.println(reply);
    } else if (r < 0) {
      Serial.println(F("ERR line too long"));
    }
  }
  uint8_t done = relay_tick(&core, millis());
  if (done) {
    apply_outputs();
    for (uint8_t i = 0; i < RELAY_CHANNELS; i++) {
      if (done & (1u << i)) {
        char ev[40];
        snprintf(ev, sizeof ev, "EVENT CYCLED %u MASK %02X", i, core.mask);
        Serial.println(ev);
      }
    }
  }
}
