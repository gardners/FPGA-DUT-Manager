// Native unit test for relay_core.h (g++ -o t test_relay_core.cpp && ./t)
#include "../relay_core.h"
#include <assert.h>

static int checks, fails;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); } } while (0)

static RelayCore r;
static char out[RELAY_REPLY_MAX];

static const char *ex(const char *cmd, uint32_t now = 0) {
  relay_exec(&r, cmd, now, out, sizeof out);
  return out;
}

int main() {
  relay_init(&r);
  CHECK(!strcmp(ex("status"), "OK STATUS 00 PSU 0 UPTIME 0"));
  CHECK(!strcmp(ex("POWER 3 1"), "OK POWER 3 1 MASK 08"));
  CHECK(!strcmp(ex("power 3 1"), "OK POWER 3 1 MASK 08"));  // idempotent
  CHECK(!strcmp(ex("POWER 0 1"), "OK POWER 0 1 MASK 09"));
  CHECK(!strcmp(ex("POWER 8 1"), "ERR unknown command"));
  CHECK(!strcmp(ex("POWER 1 2"), "ERR unknown command"));
  CHECK(!strcmp(ex("POWER x 1"), "ERR unknown command"));
  CHECK(!strcmp(ex("bogus"), "ERR unknown command"));
  CHECK(!strcmp(ex(""), "ERR empty"));
  // cycle with duplicate protection
  CHECK(!strcmp(ex("#17 CYCLE 3 2000", 1000), "#17 OK CYCLE 3 2000"));
  CHECK(r.mask == 0x01);
  CHECK(relay_tick(&r, 2999) == 0 && r.mask == 0x01);
  CHECK(!strcmp(ex("#17 CYCLE 3 2000", 2500), "#17 OK CYCLE 3 2000"));  // cached, not re-run
  CHECK(r.cycle_until[3] == 3000);
  CHECK(relay_tick(&r, 3000) == 0x08 && r.mask == 0x09);
  // minimum off time enforced
  CHECK(!strcmp(ex("CYCLE 1 10", 5000), "OK CYCLE 1 500"));
  // explicit power cancels a cycle
  CHECK(!strcmp(ex("POWER 1 0", 5100), "OK POWER 1 0 MASK 09"));
  CHECK(relay_tick(&r, 6000) == 0 && r.mask == 0x09);
  // millis() wraparound
  CHECK(!strcmp(ex("CYCLE 2 1000", 0xFFFFFF00u), "OK CYCLE 2 1000"));
  CHECK(relay_tick(&r, 0x100) == 0);
  CHECK(relay_tick(&r, 0x2E8) == 0x04);
  CHECK(!strcmp(ex("ALL OFF"), "OK ALL OFF MASK 00") && r.mask == 0);
  CHECK(!strcmp(ex("PSU 1"), "OK PSU 1") && r.psu == 1);
  CHECK(!strcmp(ex("#5 VERSION"), "#5 OK VERSION relay-controller 2 LIMIT 5"));
  CHECK(!strcmp(ex("#abc STATUS"), "ERR bad id"));
  // at most RELAY_MAX_ON (5) relays on, counting pending cycles
  relay_init(&r);
  for (int i = 0; i < 5; i++) {
    char c[16], want[40];
    snprintf(c, sizeof c, "POWER %d 1", i);
    snprintf(want, sizeof want, "OK POWER %d 1 MASK %02X", i, (1 << (i + 1)) - 1);
    CHECK(!strcmp(ex(c), want));
  }
  CHECK(!strcmp(ex("POWER 5 1"), "ERR LIMIT 5 ON") && r.mask == 0x1F);
  CHECK(!strcmp(ex("POWER 2 1"), "OK POWER 2 1 MASK 1F"));   // already on: fine
  CHECK(!strcmp(ex("POWER 5 0"), "OK POWER 5 0 MASK 1F"));   // off always allowed
  CHECK(!strcmp(ex("CYCLE 5 1000", 100), "ERR LIMIT 5 ON"));  // would end on
  CHECK(!strcmp(ex("CYCLE 4 1000", 100), "OK CYCLE 4 1000") && r.mask == 0x0F);
  CHECK(!strcmp(ex("POWER 6 1", 200), "ERR LIMIT 5 ON"));    // 4 is coming back
  CHECK(relay_tick(&r, 1100) == 0x10 && r.mask == 0x1F);
  CHECK(!strcmp(ex("POWER 0 0", 1200), "OK POWER 0 0 MASK 1E"));
  CHECK(!strcmp(ex("POWER 7 1", 1300), "OK POWER 7 1 MASK 9E"));
  CHECK(!strcmp(ex("POWER 1 0", 1400), "OK POWER 1 0 MASK 9C"));
  CHECK(!strcmp(ex("CYCLE 4 600", 1500), "OK CYCLE 4 600"));  // already committed
  // line assembly
  relay_init(&r);
  const char *in = "STATUS\r\nPOWER 1 1\n";
  int lines = 0;
  for (const char *p = in; *p; p++)
    if (relay_feed(&r, *p) == 1) lines++;
  CHECK(lines == 2);
  for (int i = 0; i < 100; i++) relay_feed(&r, 'x');
  CHECK(relay_feed(&r, '\n') == -1);
  printf("relay_core tests: %d checks, %d failures\n", checks, fails);
  return fails ? 1 : 0;
}
