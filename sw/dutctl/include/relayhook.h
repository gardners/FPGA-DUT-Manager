/* Output hooks around relay power switching (issue 0056).
 *
 * Before `dutctl relay TTY POWER N... OFF` (or ALL OFF, or CYCLE N MS) cuts
 * a DUT's power, the DUTs mapped to those channels in duts.conf (`relay =
 * TTY CHANNEL`) get out-policy 2 (all supervisor outputs off, JTAG
 * included), so the supervisor cannot back-power them. After POWER N ON
 * (or once a CYCLE has switched back on) they get out-policy 0 again.
 *
 * rh_plan only decides; main.c sends the MGMT sets and runs the relay.
 *
 * LGPL-2.1-or-later. */
#ifndef RELAYHOOK_H
#define RELAYHOOK_H

#include "dutconf.h"

#define RH_SETTLE_MS 500 /* after switching on, before out-policy 0 */

typedef struct {
  int npre, npost;
  int pre[DC_MAX_DUTS];  /* conf indices: out-policy 2 before the relay command */
  int post[DC_MAX_DUTS]; /* conf indices: out-policy 0 after it */
  long post_delay_ms;    /* wait between the relay reply and the post hooks */
} rh_plan_t;

/* Same relay controller port: equal strings, or both resolve (realpath) to
 * the same device. */
int rh_same_tty(const char *a, const char *b);

/* Plan the hooks for relay command argv[0..argc-1] (case-insensitive, as
 * the controller parses it) on tty. Commands that do not switch power
 * (STATUS, PING, ...) or malformed ones give an empty plan. Returns the
 * number of hooked DUTs (npre + npost). */
int rh_plan(const dc_conf_t *c, const char *tty, int argc, char **argv, rh_plan_t *p);

#endif
