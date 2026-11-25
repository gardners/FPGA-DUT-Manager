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
  const char *ALLOFF = "OK STATUS 0 OFF 1 OFF 2 OFF 3 OFF 4 OFF 5 OFF 6 OFF 7 OFF PSU OFF UPTIME 0";
  CHECK(!strcmp(ex("status"), ALLOFF));
  CHECK(!strcmp(ex("POWER 3 ON"), "OK POWER 3 ON") && r.mask == 0x08);
  CHECK(!strcmp(ex("power 3 on"), "OK POWER 3 ON") && r.mask == 0x08);  // idempotent
  CHECK(!strcmp(ex("POWER 0 ON"), "OK POWER 0 ON") && r.mask == 0x09);
  CHECK(!strcmp(ex("POWER 8 ON"), "ERR usage: POWER <0-7> [...] ON|OFF"));
  CHECK(!strcmp(ex("POWER 1 1"), "ERR usage: POWER <0-7> [...] ON|OFF"));  // no 0/1
  CHECK(!strcmp(ex("POWER x ON"), "ERR usage: POWER <0-7> [...] ON|OFF"));
  CHECK(!strcmp(ex("POWER ON"), "ERR unknown command"));
  CHECK(!strcmp(ex("bogus"), "ERR unknown command"));
  CHECK(!strcmp(ex(""), "ERR empty"));
  CHECK(!strcmp(ex("STATUS 3 0", 7), "OK STATUS 0 ON 3 ON PSU OFF UPTIME 7"));
  CHECK(!strcmp(ex("STATUS 1"), "OK STATUS 1 OFF PSU OFF UPTIME 0"));
  CHECK(!strcmp(ex("STATUS 9"), "ERR bad channel"));
  // several channels at once, all or nothing
  CHECK(!strcmp(ex("POWER 5 6 7 ON"), "OK POWER 5 6 7 ON") && r.mask == 0xE9);
  CHECK(!strcmp(ex("POWER 7 5 OFF"), "OK POWER 5 7 OFF") && r.mask == 0x49);
  CHECK(!strcmp(ex("POWER 1 9 ON"), "ERR usage: POWER <0-7> [...] ON|OFF") && r.mask == 0x49);
  CHECK(!strcmp(ex("POWER 6 OFF"), "OK POWER 6 OFF") && r.mask == 0x09);
  // cycle with duplicate protection
  CHECK(!strcmp(ex("#17 CYCLE 3 2000", 1000), "#17 OK CYCLE 3 2000"));
  CHECK(r.mask == 0x01);
  CHECK(!strcmp(ex("STATUS 3", 1500), "OK STATUS 3 CYCLING PSU OFF UPTIME 1500"));
  CHECK(relay_tick(&r, 2999) == 0 && r.mask == 0x01);
  CHECK(!strcmp(ex("#17 CYCLE 3 2000", 2500), "#17 OK CYCLE 3 2000"));  // cached, not re-run
  CHECK(r.cycle_until[3] == 3000);
  CHECK(relay_tick(&r, 3000) == 0x08 && r.mask == 0x09);
  CHECK(!strcmp(ex("#18 STATUS 3", 3100), "#18 OK STATUS 3 ON PSU OFF UPTIME 3100"));
  CHECK(!strcmp(ex("#18 STATUS 3", 3200), "#18 OK STATUS 3 ON PSU OFF UPTIME 3200"));  // not cached
  // minimum off time enforced
  CHECK(!strcmp(ex("CYCLE 1 10", 5000), "OK CYCLE 1 500"));
  // explicit power cancels a cycle
  CHECK(!strcmp(ex("POWER 1 OFF", 5100), "OK POWER 1 OFF") && r.mask == 0x09);
  CHECK(relay_tick(&r, 6000) == 0 && r.mask == 0x09);
  // millis() wraparound
  CHECK(!strcmp(ex("CYCLE 2 1000", 0xFFFFFF00u), "OK CYCLE 2 1000"));
  CHECK(relay_tick(&r, 0x100) == 0);
  CHECK(relay_tick(&r, 0x2E8) == 0x04);
  CHECK(!strcmp(ex("ALL OFF"), "OK ALL OFF") && r.mask == 0);
  CHECK(!strcmp(ex("PSU ON"), "OK PSU ON") && r.psu == 1);
  CHECK(!strcmp(ex("PSU 1"), "ERR unknown command") && r.psu == 1);
  CHECK(!strcmp(ex("#5 VERSION"), "#5 OK VERSION relay-controller 3 LIMIT 5"));
  CHECK(!strcmp(ex("#abc STATUS"), "ERR bad id"));
  // the longest reply fits
  relay_init(&r);
  ex("POWER 0 1 2 3 4 ON");
  ex("CYCLE 0 1000", 0); ex("CYCLE 1 1000", 0); ex("CYCLE 2 1000", 0); ex("CYCLE 3 1000", 0);
  CHECK(!strcmp(ex("#99999999 STATUS", 0xFFFFFFFFu),
                "#99999999 OK STATUS 0 CYCLING 1 CYCLING 2 CYCLING 3 CYCLING 4 ON 5 OFF 6 OFF 7 OFF PSU OFF UPTIME 4294967295"));
  // at most RELAY_MAX_ON (5) relays on, counting pending cycles
  relay_init(&r);
  CHECK(!strcmp(ex("POWER 0 1 2 3 4 5 ON"), "ERR LIMIT 5 ON") && r.mask == 0);   // all or nothing
  CHECK(!strcmp(ex("POWER 0 1 2 3 4 ON"), "OK POWER 0 1 2 3 4 ON") && r.mask == 0x1F);
  CHECK(!strcmp(ex("POWER 5 ON"), "ERR LIMIT 5 ON") && r.mask == 0x1F);
  CHECK(!strcmp(ex("POWER 2 ON"), "OK POWER 2 ON"));    // already on: fine
  CHECK(!strcmp(ex("POWER 5 OFF"), "OK POWER 5 OFF"));  // off always allowed
  CHECK(!strcmp(ex("CYCLE 5 1000", 100), "ERR LIMIT 5 ON"));  // would end on
  CHECK(!strcmp(ex("CYCLE 4 1000", 100), "OK CYCLE 4 1000") && r.mask == 0x0F);
  CHECK(!strcmp(ex("POWER 6 ON", 200), "ERR LIMIT 5 ON"));    // 4 is coming back
  CHECK(relay_tick(&r, 1100) == 0x10 && r.mask == 0x1F);
  CHECK(!strcmp(ex("POWER 0 OFF", 1200), "OK POWER 0 OFF") && r.mask == 0x1E);
  CHECK(!strcmp(ex("POWER 7 ON", 1300), "OK POWER 7 ON") && r.mask == 0x9E);
  CHECK(!strcmp(ex("CYCLE 4 600", 1500), "OK CYCLE 4 600"));  // already committed
  // line assembly
  relay_init(&r);
  const char *in = "STATUS\r\nPOWER 1 ON\n";
  int lines = 0;
  for (const char *p = in; *p; p++)
    if (relay_feed(&r, *p) == 1) lines++;
  CHECK(lines == 2);
  for (int i = 0; i < 100; i++) relay_feed(&r, 'x');
  CHECK(relay_feed(&r, '\n') == -1);
  printf("relay_core tests: %d checks, %d failures\n", checks, fails);
  return fails ? 1 : 0;
}
