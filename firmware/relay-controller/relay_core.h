// relay_core.h - board-independent command logic for the relay controller
// (docs/adrs/0009-power-relay-controller.md). No Arduino dependencies, so the
// same code is unit-tested natively (test/test_relay_core.cpp).
// LGPL-2.1-or-later.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdlib.h>

#define RELAY_CHANNELS 8
#define RELAY_MIN_OFF_MS 500
#define RELAY_ID_CACHE 4
#define RELAY_LINE_MAX 64
#define RELAY_REPLY_MAX 128   // longest: "#id OK STATUS" for all 8 channels
#define RELAY_CACHED_MAX 40   // cached replies of state-changing commands
#define RELAY_TOKENS 10
// At most this many relays energised at once, counting channels whose
// power cycle will switch them back on. 8 = no limit (owner 2026-11-25: the
// 12 V coils run from VIN and draw little); the unit tests build with 5.
#ifndef RELAY_MAX_ON
#define RELAY_MAX_ON 8
#endif

struct RelayCore {
  uint8_t mask;                  // bit n = relay n energised (DUT n powered)
  uint8_t psu;                   // ATX PS_ON asserted
  uint32_t cycle_until[RELAY_CHANNELS]; // millis() when an off-cycle ends, 0 = none
  // duplicate protection: last few command ids and their replies
  long ids[RELAY_ID_CACHE];
  char replies[RELAY_ID_CACHE][RELAY_CACHED_MAX];
  uint8_t id_next;
  char line[RELAY_LINE_MAX];
  uint8_t line_len;
  uint8_t overflow;
};

static inline void relay_init(RelayCore *r) {
  memset(r, 0, sizeof *r);
  for (int i = 0; i < RELAY_ID_CACHE; i++) r->ids[i] = -1;
}

// Upper-case and split into at most RELAY_TOKENS tokens; returns
// RELAY_TOKENS + 1 if there are more.
static inline int relay_tokens(char *s, char *tok[RELAY_TOKENS]) {
  int n = 0;
  for (char *p = s; *p; p++) *p = (char)toupper((unsigned char)*p);
  char *save = s;
  while (1) {
    while (*save == ' ' || *save == '\t') save++;
    if (!*save) break;
    if (n == RELAY_TOKENS) return RELAY_TOKENS + 1;
    tok[n++] = save;
    while (*save && *save != ' ' && *save != '\t') save++;
    if (*save) *save++ = 0;
  }
  return n;
}

// ON / OFF (only these words: no 0/1 ambiguity)
static inline int relay_onoff(const char *s, long *out) {
  if (!strcmp(s, "ON")) { *out = 1; return 1; }
  if (!strcmp(s, "OFF")) { *out = 0; return 1; }
  return 0;
}

static inline int relay_num(const char *s, long lo, long hi, long *out) {
  char *end;
  long v = strtol(s, &end, 10);
  if (*end || v < lo || v > hi) return 0;
  *out = v;
  return 1;
}

// Channels that are on, or will be when their power cycle ends.
static inline uint8_t relay_committed(const RelayCore *r) {
  uint8_t m = r->mask;
  for (int i = 0; i < RELAY_CHANNELS; i++)
    if (r->cycle_until[i]) m |= (uint8_t)(1u << i);
  return m;
}

// Would switching channel ch on exceed RELAY_MAX_ON?
static inline int relay_over_limit(const RelayCore *r, long ch) {
  uint8_t m = relay_committed(r);
  if (m & (1u << ch)) return 0;
  int n = 0;
  for (; m; m &= (uint8_t)(m - 1)) n++;
  return n >= RELAY_MAX_ON;
}

// Execute one command line (without the newline) at time `now` (ms).
// Writes the reply (without newline) to `out`.
static inline void relay_exec(RelayCore *r, const char *cmdline, uint32_t now, char *out, size_t cap) {
  char buf[RELAY_LINE_MAX];
  strncpy(buf, cmdline, sizeof buf - 1);
  buf[sizeof buf - 1] = 0;
  char *s = buf;
  long id = -1;
  char prefix[12] = "";
  if (s[0] == '#') {
    char *end;
    id = strtol(s + 1, &end, 10);
    if (end == s + 1 || id < 0 || id > 99999999L) { snprintf(out, cap, "ERR bad id"); return; }
    snprintf(prefix, sizeof prefix, "#%ld ", id);
    s = end;
    for (int i = 0; i < RELAY_ID_CACHE; i++)
      if (r->ids[i] == id) { snprintf(out, cap, "%s", r->replies[i]); return; }
  }
  char *t[RELAY_TOKENS];
  int n = relay_tokens(s, t);
  char body[RELAY_REPLY_MAX - 12];
  long ch, v;
  int cache = 1;            // state-changing commands are remembered by id
  if (n >= 1 && !strcmp(t[0], "STATUS")) {
    // STATUS [ch ...]: every channel, or only the listed ones
    cache = 0;
    uint8_t want = 0;
    int ok = n <= RELAY_TOKENS;
    for (int i = 1; ok && i < n; i++) {
      if (relay_num(t[i], 0, RELAY_CHANNELS - 1, &ch)) want |= (uint8_t)(1u << ch);
      else ok = 0;
    }
    if (n == 1) want = 0xFF;
    if (!ok) {
      snprintf(body, sizeof body, "ERR bad channel");
    } else {
      int l = snprintf(body, sizeof body, "OK STATUS");
      for (int i = 0; i < RELAY_CHANNELS; i++)
        if (want & (1u << i))
          l += snprintf(body + l, sizeof body - (size_t)l, " %d %s", i,
                        r->cycle_until[i] ? "CYCLING" : (r->mask & (1u << i)) ? "ON" : "OFF");
      snprintf(body + l, sizeof body - (size_t)l, " PSU %s UPTIME %lu", r->psu ? "ON" : "OFF",
               (unsigned long)now);
    }
  } else if (n == 1 && !strcmp(t[0], "VERSION")) {
    cache = 0;
    snprintf(body, sizeof body, "OK VERSION relay-controller 3 LIMIT %d", RELAY_MAX_ON);
  } else if (n >= 3 && n <= RELAY_TOKENS && !strcmp(t[0], "POWER")) {
    // POWER <ch> [<ch> ...] ON|OFF: all listed channels, or none on error
    uint8_t set = 0;
    int ok = relay_onoff(t[n - 1], &v);
    for (int i = 1; ok && i < n - 1; i++) {
      if (relay_num(t[i], 0, RELAY_CHANNELS - 1, &ch)) set |= (uint8_t)(1u << ch);
      else ok = 0;
    }
    uint8_t after = (uint8_t)(relay_committed(r) | set);
    int cnt = 0;
    for (uint8_t m = after; m; m &= (uint8_t)(m - 1)) cnt++;
    if (!ok) {
      snprintf(body, sizeof body, "ERR usage: POWER <0-%d> [...] ON|OFF", RELAY_CHANNELS - 1);
    } else if (v && cnt > RELAY_MAX_ON) {
      snprintf(body, sizeof body, "ERR LIMIT %d ON", RELAY_MAX_ON);
    } else {
      int l = snprintf(body, sizeof body, "OK POWER");
      for (int i = 0; i < RELAY_CHANNELS; i++) {
        if (!(set & (1u << i))) continue;
        r->cycle_until[i] = 0;  // explicit power cancels a pending cycle
        if (v) r->mask |= (uint8_t)(1u << i); else r->mask &= (uint8_t)~(1u << i);
        l += snprintf(body + l, sizeof body - (size_t)l, " %d", i);
      }
      snprintf(body + l, sizeof body - (size_t)l, " %s", v ? "ON" : "OFF");
    }
  } else if (n == 3 && !strcmp(t[0], "CYCLE") && relay_num(t[1], 0, RELAY_CHANNELS - 1, &ch) &&
             relay_num(t[2], 0, 600000, &v)) {
    if (relay_over_limit(r, ch)) {
      snprintf(body, sizeof body, "ERR LIMIT %d ON", RELAY_MAX_ON);   // the cycle ends with it on
    } else {
      if (v < RELAY_MIN_OFF_MS) v = RELAY_MIN_OFF_MS;
      r->mask &= (uint8_t)~(1u << ch);
      r->cycle_until[ch] = now + (uint32_t)v;
      if (r->cycle_until[ch] == 0) r->cycle_until[ch] = 1;
      snprintf(body, sizeof body, "OK CYCLE %ld %ld", ch, v);
    }
  } else if (n == 2 && !strcmp(t[0], "ALL") && !strcmp(t[1], "OFF")) {
    r->mask = 0;
    for (int i = 0; i < RELAY_CHANNELS; i++) r->cycle_until[i] = 0;
    snprintf(body, sizeof body, "OK ALL OFF");
  } else if (n == 2 && !strcmp(t[0], "PSU") && relay_onoff(t[1], &v)) {
    r->psu = (uint8_t)v;
    snprintf(body, sizeof body, "OK PSU %s", v ? "ON" : "OFF");
  } else if (n == 0) {
    cache = 0;
    snprintf(body, sizeof body, "ERR empty");
  } else {
    cache = 0;
    snprintf(body, sizeof body, "ERR unknown command");
  }
  snprintf(out, cap, "%s%s", prefix, body);
  if (id >= 0 && cache) {
    r->ids[r->id_next] = id;
    snprintf(r->replies[r->id_next], RELAY_CACHED_MAX, "%s", out);
    r->id_next = (uint8_t)((r->id_next + 1) % RELAY_ID_CACHE);
  }
}

// Advance timers; returns a bitmask of channels whose cycle just completed
// (they are switched back on).
static inline uint8_t relay_tick(RelayCore *r, uint32_t now) {
  uint8_t done = 0;
  for (int i = 0; i < RELAY_CHANNELS; i++) {
    if (r->cycle_until[i] && (int32_t)(now - r->cycle_until[i]) >= 0) {
      r->cycle_until[i] = 0;
      r->mask |= (uint8_t)(1u << i);
      done |= (uint8_t)(1u << i);
    }
  }
  return done;
}

// Feed one received character; returns 1 when a complete line is in r->line.
static inline int relay_feed(RelayCore *r, char c) {
  if (c == '\r') return 0;
  if (c == '\n') {
    r->line[r->line_len] = 0;
    int ok = !r->overflow;
    r->line_len = 0;
    r->overflow = 0;
    return ok ? 1 : -1;
  }
  if (r->line_len < RELAY_LINE_MAX - 1) r->line[r->line_len++] = c;
  else r->overflow = 1;
  return 0;
}
