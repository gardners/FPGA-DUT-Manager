/* Re-apply decision for `dutctl keeper` (issue 0066). LGPL-2.1-or-later. */
#include "keeper.h"

#include <string.h>

void kp_init(kp_t *k, double min_interval, double max_backoff)
{
  memset(k, 0, sizeof *k);
  k->min_interval = min_interval;
  k->max_backoff = max_backoff > min_interval ? max_backoff : min_interval;
}

static kp_board_t *find(kp_t *k, unsigned long long dna)
{
  for (int i = 0; i < k->n; i++)
    if (k->b[i].dna == dna)
      return &k->b[i];
  return NULL;
}

const kp_board_t *kp_find(const kp_t *k, unsigned long long dna)
{
  return find((kp_t *)k, dna);
}

kp_reason_t kp_heartbeat(kp_t *k, unsigned long long dna, uint32_t boot, double now)
{
  kp_board_t *e = find(k, dna);
  if (!e) {
    if (k->n == KP_MAX_BOARDS)
      return KP_NONE;
    e = &k->b[k->n++];
    memset(e, 0, sizeof *e);
    e->dna = dna;
    e->boot = boot;
    e->pending = KP_FIRST;
    e->last_try = -1e300;
  } else if (e->boot != boot) {
    e->old_boot = e->boot;
    e->boot = boot;
    e->applied = 0;
    e->fails = 0;
    e->pending = KP_REBOOT;
  }
  if (e->applied)
    return KP_NONE;
  double wait = k->min_interval;
  for (int i = 0; i < e->fails && wait < k->max_backoff; i++)
    wait *= 2;
  if (wait > k->max_backoff)
    wait = k->max_backoff;
  if (now - e->last_try < wait)
    return KP_NONE;
  e->last_try = now;
  return e->fails ? KP_RETRY : e->pending;
}

void kp_done(kp_t *k, unsigned long long dna, uint32_t boot, int ok)
{
  kp_board_t *e = find(k, dna);
  if (!e || e->boot != boot)
    return;
  if (ok) {
    e->applied = 1;
    e->fails = 0;
  } else
    e->fails++;
}

void kp_invalidate_all(kp_t *k)
{
  for (int i = 0; i < k->n; i++) {
    kp_board_t *e = &k->b[i];
    e->applied = 0;
    e->fails = 0;
    e->pending = KP_RELOAD;
    e->last_try = -1e300; /* a deliberate reload is not rate-limited */
  }
}

void kp_forget(kp_t *k, unsigned long long dna)
{
  kp_board_t *e = find(k, dna);
  if (!e)
    return;
  *e = k->b[--k->n];
}

const char *kp_reason_name(kp_reason_t r)
{
  switch (r) {
  case KP_FIRST: return "first seen";
  case KP_REBOOT: return "boot id changed";
  case KP_RELOAD: return "configuration re-read";
  case KP_RETRY: return "retry";
  default: return "none";
  }
}
