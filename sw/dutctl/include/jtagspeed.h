/* JTAG TCK speed probe (issue 0054): one read-only probe shift (IDCODE after
 * Test-Logic-Reset, then BYPASS with a random, an all-0 and an all-1 DR
 * pattern) and its checks, independent of the transport so they can be
 * tested against a simulated chain.
 *
 * Bit i of tms/tdi/tdo is TCK pulse i (LSB first, XVC semantics).
 *
 * LGPL-2.1-or-later. */
#ifndef JTAGSPEED_H
#define JTAGSPEED_H

#include <stdint.h>

#define JS_ID_BITS 256   /* IDCODE window after reset: up to 8 IDCODE devices */
#define JS_IR_BITS 256   /* ones shifted into the IRs (total IR length <= 256) */
#define JS_RAND_BITS 2048
#define JS_FILL_BITS 512 /* all-0 then all-1 segments */
#define JS_MAX_CHAIN 64  /* longest chain found by js_chain_len */
#define JS_MAX_BITS 4096

typedef struct {
  uint32_t bits;
  uint32_t id_at;   /* first TDO bit of the IDCODE window */
  uint32_t dr_at;   /* first TDO bit of the BYPASS DR shift */
  uint32_t dr_bits; /* JS_RAND_BITS + 2 * JS_FILL_BITS */
  uint8_t tms[JS_MAX_BITS / 8], tdi[JS_MAX_BITS / 8];
} js_probe_t;

typedef struct {
  uint32_t id_err;   /* IDCODE window bits differing from the reference */
  uint32_t rand_err; /* BYPASS random-pattern bits wrong */
  uint32_t zero_err; /* all-0 segment bits wrong */
  uint32_t one_err;  /* all-1 segment bits wrong */
} js_errs_t;

/* Build the probe; seed picks the random pattern (xorshift32, seed != 0). */
void js_build(js_probe_t *p, uint32_t seed);

/* Chain length (devices in BYPASS) from a probe's TDO: the delay N for which
 * the whole DR shift comes back exactly N bits late. -1 if none <= max. */
int js_chain_len(const js_probe_t *p, const uint8_t *tdo, int max);

/* Count errors against a reference IDCODE window (ref_tdo is the TDO of an
 * earlier, slow probe; only its IDCODE window is used) and chain length n.
 * Returns the total. */
uint32_t js_check(const js_probe_t *p, const uint8_t *tdo, const uint8_t *ref_tdo, int n, js_errs_t *e);

/* Device IDCODEs in the window after reset, nearest TDO first: a 1 bit
 * starts a 32-bit IDCODE, a 0 bit is a BYPASS-only device; stops at an
 * all-ones word (TDI fill) or the end of the window. Returns the number of
 * devices (bypass-only ones are reported as 0). */
int js_idcodes(const js_probe_t *p, const uint8_t *tdo, uint32_t *ids, int max);

/* Sweep steps (half periods), slow to fast, and helpers. */
extern const int js_steps[];
extern const int js_nsteps;
double js_freq_hz(int half); /* clk_sys 125 MHz: f = 125 MHz / (2 * half) */

/* Given steps[0..n) (half periods, slow to fast) and pass[i] for each, set
 * *fmax_idx to the fastest step reached without a failure on the way (-1 if
 * the first fails) and return the recommended half period: f_max / 2, i.e.
 * the smallest swept step >= 2 * steps[fmax] (2 * steps[fmax] if no swept
 * step is that slow), so always at least one step slower than f_max.
 * Returns 0 if nothing passed. */
int js_recommend(const int *steps, const int *pass, int n, int *fmax_idx);

#endif
