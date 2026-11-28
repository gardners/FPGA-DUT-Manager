/* Re-apply decision for `dutctl keeper` (issue 0066).
 *
 * The keeper hears heartbeats; for a board with a [board DNA] section in
 * duts.conf it asks kp_heartbeat whether to send the settings now. They
 * are sent when the board is first seen, when its boot id changes (the
 * supervisor was reloaded / reconfigured: all MGMT keys are back at their
 * build defaults) and after kp_invalidate_all (duts.conf re-read on
 * SIGHUP). Sends to one board are at least min_interval apart (a board
 * stuck in a reload loop is not flooded); a failed send is retried with
 * exponential backoff up to max_backoff. No network here, so it is
 * unit-testable: main.c sends and reports the result with kp_done.
 *
 * LGPL-2.1-or-later. */
#ifndef KEEPER_H
#define KEEPER_H

#include <stdint.h>

#define KP_MAX_BOARDS 64

typedef enum {
  KP_NONE = 0, /* nothing to do now */
  KP_FIRST,    /* first heartbeat from this board */
  KP_REBOOT,   /* boot id changed */
  KP_RELOAD,   /* configuration re-read */
  KP_RETRY,    /* an earlier attempt for this boot failed */
} kp_reason_t;

typedef struct {
  unsigned long long dna;
  uint32_t boot;
  uint32_t old_boot;   /* boot id before the last change (KP_REBOOT) */
  int applied;         /* settings applied for this boot */
  int fails;           /* consecutive failed attempts for this boot */
  kp_reason_t pending; /* why the next attempt is due */
  double last_try;     /* time of the last attempt (-1e300 = never) */
} kp_board_t;

typedef struct {
  double min_interval, max_backoff;
  int n;
  kp_board_t b[KP_MAX_BOARDS];
} kp_t;

void kp_init(kp_t *k, double min_interval, double max_backoff);

/* A heartbeat from board dna (configured) with boot id boot at time now
 * (seconds, monotonic). Returns why to apply its settings now, or KP_NONE.
 * A non-NONE return counts as an attempt: report it with kp_done. */
kp_reason_t kp_heartbeat(kp_t *k, unsigned long long dna, uint32_t boot, double now);

/* Outcome of the attempt for (dna, boot). */
void kp_done(kp_t *k, unsigned long long dna, uint32_t boot, int ok);

/* Settings changed: apply again to every known board (next heartbeat). */
void kp_invalidate_all(kp_t *k);

/* Forget a board (its section was removed from duts.conf). */
void kp_forget(kp_t *k, unsigned long long dna);

const kp_board_t *kp_find(const kp_t *k, unsigned long long dna);
const char *kp_reason_name(kp_reason_t r);

#endif
