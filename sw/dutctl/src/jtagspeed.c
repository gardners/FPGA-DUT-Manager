/* JTAG TCK speed probe (issue 0054). LGPL-2.1-or-later. */
#include "jtagspeed.h"

#include <string.h>

const int js_steps[] = {50, 40, 32, 24, 20, 16, 12, 10, 8, 7, 6, 5, 4, 3, 2};
const int js_nsteps = (int)(sizeof js_steps / sizeof js_steps[0]);

double js_freq_hz(int half) { return 125e6 / (2.0 * half); }

static int getb(const uint8_t *v, uint32_t i) { return (v[i / 8] >> (i % 8)) & 1; }

static void push(js_probe_t *p, int tms, int tdi)
{
  uint32_t i = p->bits++;
  if (tms)
    p->tms[i / 8] |= (uint8_t)(1u << (i % 8));
  if (tdi)
    p->tdi[i / 8] |= (uint8_t)(1u << (i % 8));
}

void js_build(js_probe_t *p, uint32_t seed)
{
  memset(p, 0, sizeof *p);
  uint32_t x = seed ? seed : 0x2545F491u;
  for (int i = 0; i < 5; i++) /* Test-Logic-Reset from any state */
    push(p, 1, 1);
  push(p, 0, 1); /* Run-Test/Idle */
  push(p, 1, 1); /* Select-DR */
  push(p, 0, 1); /* Capture-DR */
  push(p, 0, 1); /* Shift-DR */
  p->id_at = p->bits;
  for (int i = 0; i < JS_ID_BITS; i++) /* IDCODE / BYPASS registers after reset */
    push(p, i == JS_ID_BITS - 1, 1);   /* last: Exit1-DR */
  push(p, 1, 1); /* Update-DR */
  push(p, 1, 1); /* Select-DR */
  push(p, 1, 1); /* Select-IR */
  push(p, 0, 1); /* Capture-IR */
  push(p, 0, 1); /* Shift-IR */
  for (int i = 0; i < JS_IR_BITS; i++) /* all ones = BYPASS in every IR */
    push(p, i == JS_IR_BITS - 1, 1);
  push(p, 1, 1); /* Update-IR */
  push(p, 1, 1); /* Select-DR */
  push(p, 0, 1); /* Capture-DR */
  push(p, 0, 1); /* Shift-DR */
  p->dr_at = p->bits;
  p->dr_bits = JS_RAND_BITS + 2 * JS_FILL_BITS;
  for (uint32_t i = 0; i < p->dr_bits; i++) {
    int b;
    if (i < JS_RAND_BITS) {
      x ^= x << 13;
      x ^= x >> 17;
      x ^= x << 5;
      b = (int)(x >> 31);
    } else
      b = i >= JS_RAND_BITS + JS_FILL_BITS;
    push(p, i == p->dr_bits - 1, b);
  }
  push(p, 1, 0); /* Update-DR */
  for (int i = 0; i < 5; i++) /* back to Test-Logic-Reset (IR = IDCODE again) */
    push(p, 1, 0);
}

int js_chain_len(const js_probe_t *p, const uint8_t *tdo, int max)
{
  for (int n = 0; n <= max && (uint32_t)n < p->dr_bits; n++) {
    int ok = 1;
    for (uint32_t i = 0; ok && i + (uint32_t)n < p->dr_bits; i++)
      ok = getb(tdo, p->dr_at + n + i) == getb(p->tdi, p->dr_at + i);
    if (ok)
      return n;
  }
  return -1;
}

uint32_t js_check(const js_probe_t *p, const uint8_t *tdo, const uint8_t *ref_tdo, int n, js_errs_t *e)
{
  memset(e, 0, sizeof *e);
  for (uint32_t i = 0; i < JS_ID_BITS; i++)
    e->id_err += getb(tdo, p->id_at + i) != getb(ref_tdo, p->id_at + i);
  for (uint32_t i = 0; i + (uint32_t)n < p->dr_bits; i++) {
    if (getb(tdo, p->dr_at + n + i) == getb(p->tdi, p->dr_at + i))
      continue;
    if (i < JS_RAND_BITS)
      e->rand_err++;
    else if (i < JS_RAND_BITS + JS_FILL_BITS)
      e->zero_err++;
    else
      e->one_err++;
  }
  return e->id_err + e->rand_err + e->zero_err + e->one_err;
}

int js_idcodes(const js_probe_t *p, const uint8_t *tdo, uint32_t *ids, int max)
{
  int n = 0;
  uint32_t i = 0;
  while (i < JS_ID_BITS && n < max) {
    if (!getb(tdo, p->id_at + i)) {
      ids[n++] = 0;
      i++;
      continue;
    }
    if (i + 32 > JS_ID_BITS)
      break;
    uint32_t v = 0;
    for (int b = 0; b < 32; b++)
      v |= (uint32_t)getb(tdo, p->id_at + i + b) << b;
    if (v == 0xFFFFFFFFu)
      break;
    ids[n++] = v;
    i += 32;
  }
  return n;
}

int js_recommend(const int *steps, const int *pass, int n, int *fmax_idx)
{
  int k = -1;
  for (int i = 0; i < n && pass[i]; i++)
    k = i;
  if (fmax_idx)
    *fmax_idx = k;
  if (k < 0)
    return 0;
  int want = 2 * steps[k];
  int best = 0;
  for (int i = 0; i < k; i++) /* smallest slower step >= 2 * f_max half */
    if (steps[i] >= want && (!best || steps[i] < best))
      best = steps[i];
  return best ? best : want;
}
