/* Output hooks around relay power switching (issue 0056), see relayhook.h.
 * LGPL-2.1-or-later. */
#define _XOPEN_SOURCE 700 /* realpath, strcasecmp */
#include "relayhook.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>

int rh_same_tty(const char *a, const char *b)
{
  if (!strcmp(a, b))
    return 1;
  char *ra = realpath(a, NULL), *rb = realpath(b, NULL);
  int same = ra && rb && !strcmp(ra, rb);
  free(ra);
  free(rb);
  return same;
}

static int parse_num(const char *s, long lo, long hi, long *v)
{
  char *e;
  long x = strtol(s, &e, 10);
  if (!*s || *e || x < lo || x > hi)
    return -1;
  *v = x;
  return 0;
}

/* conf indices of the DUTs on tty and channel ch (-1 = any channel) */
static void add_channel(const dc_conf_t *c, const char *tty, long ch, int *list, int *n)
{
  for (int i = 0; i < c->n; i++) {
    const dc_dut_t *d = &c->d[i];
    if (!d->relay_tty[0] || (ch >= 0 && d->relay_ch != ch) || !rh_same_tty(d->relay_tty, tty))
      continue;
    int dup = 0;
    for (int k = 0; k < *n; k++)
      dup |= list[k] == i;
    if (!dup)
      list[(*n)++] = i;
  }
}

int rh_plan(const dc_conf_t *c, const char *tty, int argc, char **argv, rh_plan_t *p)
{
  memset(p, 0, sizeof *p);
  if (argc < 2)
    return 0;
  long ch, ms;
  if (!strcasecmp(argv[0], "POWER") && argc >= 3) {
    int on = !strcasecmp(argv[argc - 1], "ON"), off = !strcasecmp(argv[argc - 1], "OFF");
    if (!on && !off)
      return 0;
    for (int i = 1; i < argc - 1; i++)
      if (parse_num(argv[i], 0, 255, &ch))
        return 0;   /* the controller refuses the whole command */
    for (int i = 1; i < argc - 1; i++) {
      parse_num(argv[i], 0, 255, &ch);
      if (off)
        add_channel(c, tty, ch, p->pre, &p->npre);
      else
        add_channel(c, tty, ch, p->post, &p->npost);
    }
    if (on)
      p->post_delay_ms = RH_SETTLE_MS;
  } else if (!strcasecmp(argv[0], "CYCLE") && argc == 3) {
    if (parse_num(argv[1], 0, 255, &ch) || parse_num(argv[2], 1, 86400000L, &ms))
      return 0;
    add_channel(c, tty, ch, p->pre, &p->npre);
    add_channel(c, tty, ch, p->post, &p->npost);
    p->post_delay_ms = ms + RH_SETTLE_MS;
  } else if (!strcasecmp(argv[0], "ALL") && argc == 2 && !strcasecmp(argv[1], "OFF")) {
    add_channel(c, tty, -1, p->pre, &p->npre);
  }
  return p->npre + p->npost;
}
