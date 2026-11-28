/* Per-DUT host configuration (issue 0053) and per-board bench settings
 * (issue 0066); the file format is described in include/dutconf.h.
 * LGPL-2.1-or-later. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "dutconf.h"
#include "dutset.h"

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void errf(char *err, size_t cap, int line, const char *fmt, ...)
{
  if (!err || !cap)
    return;
  size_t l = strlen(err);
  if (l + 1 >= cap)
    return;
  int k = snprintf(err + l, cap - l, "%d: ", line);
  if (k < 0 || (size_t)k >= cap - l)
    return;
  l += (size_t)k;
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(err + l, cap - l, fmt, ap);
  va_end(ap);
  l = strlen(err);
  if (l + 1 < cap) {
    err[l] = '\n';
    err[l + 1] = 0;
  }
}

/* Trim [s, e) in place; returns the start. */
static char *trim(char *s)
{
  while (*s && isspace((unsigned char)*s))
    s++;
  char *e = s + strlen(s);
  while (e > s && isspace((unsigned char)e[-1]))
    *--e = 0;
  return s;
}

static int copy_str(char *dst, size_t cap, const char *v)
{
  if (strlen(v) >= cap)
    return -1;
  memcpy(dst, v, strlen(v) + 1);
  return 0;
}

static int parse_long(const char *v, int base, long lo, long hi, long *out)
{
  char *end;
  errno = 0;
  long x = strtol(v, &end, base);
  if (errno || end == v || *end || x < lo || x > hi)
    return -1;
  *out = x;
  return 0;
}

static void dut_defaults(dc_dut_t *d)
{
  memset(d, 0, sizeof *d);
  d->dut = -1;
  d->ftdi_channel = -1;
  d->relay_ch = -1;
}

static int set_key(dc_dut_t *d, const char *k, const char *v)
{
  long x;
  if (!strcmp(k, "ip"))
    return copy_str(d->ip, sizeof d->ip, v);
  if (!strcmp(k, "dut")) {
    if (parse_long(v, 0, 0, 254, &x))
      return -1;
    d->dut = (int)x;
    return 0;
  }
  if (!strcmp(k, "jtag")) {
    if (!strcmp(v, "octopus"))
      d->jtag = DC_JTAG_OCTOPUS;
    else if (!strcmp(v, "usb"))
      d->jtag = DC_JTAG_USB;
    else
      return -1;
    return 0;
  }
  if (!strcmp(k, "tck_half") || !strcmp(k, "kbd_tck_half")) {
    if (parse_long(v, 0, 2, 1000000, &x))
      return -1;
    *(k[0] == 'k' ? &d->kbd_tck_half : &d->tck_half) = (int)x;
    return 0;
  }
  if (!strcmp(k, "usb_vid") || !strcmp(k, "usb_pid")) {
    const char *p = v;
    if (!strncasecmp(p, "0x", 2))
      p += 2;
    if (parse_long(p, 16, 1, 0xFFFF, &x))
      return -1;
    *(k[4] == 'v' ? &d->usb_vid : &d->usb_pid) = (unsigned)x;
    return 0;
  }
  if (!strcmp(k, "usb_serial"))
    return copy_str(d->usb_serial, sizeof d->usb_serial, v);
  if (!strcmp(k, "ftdi_channel")) {
    if (parse_long(v, 0, 0, 3, &x))
      return -1;
    d->ftdi_channel = (int)x;
    return 0;
  }
  if (!strcmp(k, "usb_path"))
    return copy_str(d->usb_path, sizeof d->usb_path, v);
  if (!strcmp(k, "tty"))
    return copy_str(d->tty, sizeof d->tty, v);
  if (!strcmp(k, "cable"))
    return copy_str(d->cable, sizeof d->cable, v);
  if (!strcmp(k, "usb_freq")) {
    if (parse_long(v, 0, 1, 100000000, &x))
      return -1;
    d->usb_freq = x;
    return 0;
  }
  if (!strcmp(k, "relay")) {
    char tty[128];
    int ch, n = 0;
    if (sscanf(v, "%127s %d %n", tty, &ch, &n) != 2 || v[n] || ch < 0 || ch > 255)
      return -1;
    copy_str(d->relay_tty, sizeof d->relay_tty, tty);
    d->relay_ch = ch;
    return 0;
  }
  return -2;
}

/* "[board DNA]": 1..16 hex digits (optional 0x). Returns 0 and the DNA. */
static int parse_dna(const char *s, unsigned long long *dna)
{
  if (!strncasecmp(s, "0x", 2))
    s += 2;
  size_t n = strlen(s);
  if (n < 1 || n > 16 || strspn(s, "0123456789abcdefABCDEF") != n)
    return -1;
  *dna = strtoull(s, NULL, 16);
  return 0;
}

/* One "set = NAME VALUE" line of a [board] section. */
static int board_key(dc_board_t *b, const char *k, const char *v, char *err, size_t errcap, int lineno)
{
  if (strcmp(k, "set")) {
    errf(err, errcap, lineno, "unknown key '%s' in a [board] section (only set = NAME VALUE)", k);
    return 1;
  }
  char name[64];
  size_t nl = strcspn(v, " \t");
  const char *val = v + nl;
  while (*val == ' ' || *val == '\t')
    val++;
  if (!nl || !*val || nl >= sizeof name) {
    errf(err, errcap, lineno, "expected set = NAME VALUE");
    return 1;
  }
  memcpy(name, v, nl);
  name[nl] = 0;
  uint16_t key, vlen;
  uint8_t buf[DS_MAX_VALUE];
  const char *why;
  int r = ds_encode(name, val, &key, buf, &vlen, &why);
  if (r == DS_UNKNOWN_NAME) {
    errf(err, errcap, lineno, "unknown setting '%s' (see dutctl set)", name);
    return 1;
  }
  if (r != DS_OK) {
    errf(err, errcap, lineno, "bad value for setting %s: '%s' (%s)", name, val, why);
    return 1;
  }
  if (b->nset == DC_MAX_SETS) {
    errf(err, errcap, lineno, "too many settings for one board (max %d)", DC_MAX_SETS);
    return 1;
  }
  if (strlen(name) >= sizeof b->set[0].name || strlen(val) >= sizeof b->set[0].value) {
    errf(err, errcap, lineno, "setting too long");
    return 1;
  }
  dc_set_t *e = &b->set[b->nset++];
  snprintf(e->name, sizeof e->name, "%s", name);
  snprintf(e->value, sizeof e->value, "%s", val);
  return 0;
}

int dc_parse(const char *text, dc_conf_t *c, char *err, size_t errcap)
{
  memset(c, 0, sizeof *c);
  if (err && errcap)
    err[0] = 0;
  int problems = 0, lineno = 0;
  dc_dut_t *cur = NULL;
  dc_board_t *curb = NULL;
  const char *p = text;
  while (*p) {
    const char *nl = strchr(p, '\n');
    size_t len = nl ? (size_t)(nl - p) : strlen(p);
    char buf[512];
    lineno++;
    if (len >= sizeof buf) {
      errf(err, errcap, lineno, "line too long");
      problems++;
      p += len + (nl ? 1 : 0);
      continue;
    }
    memcpy(buf, p, len);
    buf[len] = 0;
    p += len + (nl ? 1 : 0);
    char *s = trim(buf);
    if (!*s || *s == '#' || *s == ';')
      continue;
    if (*s == '[') {
      char *e = strchr(s, ']');
      if (!e || trim(e + 1)[0]) {
        errf(err, errcap, lineno, "bad section header");
        problems++;
        cur = NULL;
        curb = NULL;
        continue;
      }
      *e = 0;
      char *name = trim(s + 1);
      cur = NULL;
      curb = NULL;
      if (!strncmp(name, "board", 5) && (name[5] == ' ' || name[5] == '\t')) {
        unsigned long long dna;
        if (parse_dna(trim(name + 5), &dna)) {
          errf(err, errcap, lineno, "bad board DNA (expected [board 00124c296998c854])");
          problems++;
          continue;
        }
        if (dc_find_board(c, dna)) {
          errf(err, errcap, lineno, "duplicate section [board %016llx]", dna);
          problems++;
          continue;
        }
        if (c->nboards == DC_MAX_BOARDS) {
          errf(err, errcap, lineno, "too many boards (max %d)", DC_MAX_BOARDS);
          problems++;
          continue;
        }
        curb = &c->b[c->nboards++];
        memset(curb, 0, sizeof *curb);
        curb->dna = dna;
        curb->line = lineno;
        continue;
      }
      if (!*name || strlen(name) >= sizeof cur->name || strpbrk(name, " \t[]=")) {
        errf(err, errcap, lineno, "bad section name");
        problems++;
        cur = NULL;
        continue;
      }
      if (dc_find_name(c, name)) {
        errf(err, errcap, lineno, "duplicate section [%s]", name);
        problems++;
        cur = NULL;
        continue;
      }
      if (c->n == DC_MAX_DUTS) {
        errf(err, errcap, lineno, "too many DUTs (max %d)", DC_MAX_DUTS);
        problems++;
        cur = NULL;
        continue;
      }
      cur = &c->d[c->n++];
      dut_defaults(cur);
      copy_str(cur->name, sizeof cur->name, name);
      cur->line = lineno;
      continue;
    }
    char *eq = strchr(s, '=');
    if (!eq) {
      errf(err, errcap, lineno, "expected key = value");
      problems++;
      continue;
    }
    *eq = 0;
    char *k = trim(s), *v = trim(eq + 1);
    if (curb) {
      problems += board_key(curb, k, v, err, errcap, lineno);
      continue;
    }
    if (!cur) {
      errf(err, errcap, lineno, "key '%s' outside a [section]", k);
      problems++;
      continue;
    }
    int r = set_key(cur, k, v);
    if (r == -2) {
      errf(err, errcap, lineno, "unknown key '%s' (ignored)", k);
      problems++;
    } else if (r < 0) {
      errf(err, errcap, lineno, "bad value for %s: '%s'", k, v);
      problems++;
    }
  }
  return problems;
}

int dc_load(const char *path, dc_conf_t *c, char *err, size_t errcap, int *missing)
{
  if (missing)
    *missing = 0;
  FILE *f = fopen(path, "r");
  if (!f) {
    memset(c, 0, sizeof *c);
    if (err && errcap)
      err[0] = 0;
    if (errno == ENOENT) {
      if (missing)
        *missing = 1;
      return 0;
    }
    return -1;
  }
  size_t cap = 4096, len = 0;
  char *text = malloc(cap);
  if (!text) {
    fclose(f);
    return -1;
  }
  size_t r;
  while ((r = fread(text + len, 1, cap - len - 1, f)) > 0) {
    len += r;
    if (cap - len < 2) {
      char *t = realloc(text, cap * 2);
      if (!t) {
        free(text);
        fclose(f);
        return -1;
      }
      text = t;
      cap *= 2;
    }
  }
  text[len] = 0;
  fclose(f);
  int n = dc_parse(text, c, err, errcap);
  free(text);
  return n;
}

const char *dc_default_path(char *buf, size_t cap)
{
  const char *x = getenv("XDG_CONFIG_HOME");
  if (x && *x)
    snprintf(buf, cap, "%s/dutctl/duts.conf", x);
  else
    snprintf(buf, cap, "%s/.config/dutctl/duts.conf", getenv("HOME") ? getenv("HOME") : ".");
  return buf;
}

const dc_dut_t *dc_find_name(const dc_conf_t *c, const char *name)
{
  for (int i = 0; i < c->n; i++)
    if (!strcmp(c->d[i].name, name))
      return &c->d[i];
  return NULL;
}

const dc_board_t *dc_find_board(const dc_conf_t *c, unsigned long long dna)
{
  for (int i = 0; i < c->nboards; i++)
    if (c->b[i].dna == dna)
      return &c->b[i];
  return NULL;
}

const dc_dut_t *dc_find_ip(const dc_conf_t *c, const char *ip, int dut)
{
  const dc_dut_t *wild = NULL;
  for (int i = 0; i < c->n; i++) {
    const dc_dut_t *d = &c->d[i];
    if (strcmp(d->ip, ip))
      continue;
    if (dut >= 0 && d->dut == dut)
      return d;
    if ((dut < 0 || d->dut < 0) && !wild)
      wild = d;
  }
  return wild;
}

/* ------------------------------------------------------------- writer */
typedef struct {
  char *s;
  size_t len, cap;
} sbuf_t;

static int sb_add(sbuf_t *b, const char *s, size_t n)
{
  if (b->len + n + 1 > b->cap) {
    size_t nc = (b->cap ? b->cap : 256);
    while (nc < b->len + n + 1)
      nc *= 2;
    char *t = realloc(b->s, nc);
    if (!t)
      return -1;
    b->s = t;
    b->cap = nc;
  }
  memcpy(b->s + b->len, s, n);
  b->len += n;
  b->s[b->len] = 0;
  return 0;
}

static int sb_kv(sbuf_t *b, const char *key, const char *value)
{
  return sb_add(b, key, strlen(key)) | sb_add(b, " = ", 3) | sb_add(b, value, strlen(value)) |
         sb_add(b, "\n", 1);
}

/* Classify one line: 1 = section header (name copied), 2 = key (copied), 0 other. */
static int classify(const char *line, size_t len, char *name, size_t cap)
{
  char buf[512];
  if (len >= sizeof buf)
    return 0;
  memcpy(buf, line, len);
  buf[len] = 0;
  char *s = trim(buf);
  if (!*s || *s == '#' || *s == ';')
    return 0;
  if (*s == '[') {
    char *e = strchr(s, ']');
    if (!e)
      return 0;
    *e = 0;
    snprintf(name, cap, "%s", trim(s + 1));
    return 1;
  }
  char *eq = strchr(s, '=');
  if (!eq)
    return 0;
  *eq = 0;
  snprintf(name, cap, "%s", trim(s));
  return 2;
}

char *dc_text_set(const char *text, const char *section, const char *key, const char *value)
{
  sbuf_t b = {0};
  if (sb_add(&b, "", 0))
    return NULL;
  const char *p = text ? text : "";
  int in_sec = 0, found_sec = 0, done = 0;
  size_t insert_at = 0; /* after the section's last key line (offset in b) */
  while (*p) {
    const char *nl = strchr(p, '\n');
    size_t len = nl ? (size_t)(nl - p) : strlen(p);
    char name[128];
    int kind = classify(p, len, name, sizeof name);
    if (kind == 1) {
      if (in_sec && !done && value) { /* leaving our section: insert the key here */
        sbuf_t tail = {0};
        if (sb_add(&tail, b.s + insert_at, b.len - insert_at)) {
          free(b.s);
          return NULL;
        }
        b.len = insert_at;
        if (sb_kv(&b, key, value) || sb_add(&b, tail.s, tail.len)) {
          free(tail.s);
          free(b.s);
          return NULL;
        }
        free(tail.s);
        done = 1;
      }
      in_sec = !strcmp(name, section);
      if (in_sec) {
        found_sec = 1;
        done = 0;
      }
    }
    int skip = 0;
    if (in_sec && kind == 2 && !strcmp(name, key)) {
      if (!done && value) {
        if (sb_kv(&b, key, value)) {
          free(b.s);
          return NULL;
        }
      }
      done = 1;
      skip = 1;
    }
    if (!skip && (sb_add(&b, p, len) || sb_add(&b, "\n", 1))) {
      free(b.s);
      return NULL;
    }
    if (in_sec && (kind == 1 || kind == 2))
      insert_at = b.len;
    p += len + (nl ? 1 : 0);
  }
  if (in_sec && !done && value) {
    sbuf_t tail = {0};
    if (sb_add(&tail, b.s + insert_at, b.len - insert_at)) {
      free(b.s);
      return NULL;
    }
    b.len = insert_at;
    int bad = sb_kv(&b, key, value) || sb_add(&b, tail.s, tail.len);
    free(tail.s);
    if (bad) {
      free(b.s);
      return NULL;
    }
    done = 1;
  }
  if (!found_sec && value) {
    if ((b.len && b.s[b.len - 1] != '\n' && sb_add(&b, "\n", 1)) || (b.len && sb_add(&b, "\n", 1)) ||
        sb_add(&b, "[", 1) || sb_add(&b, section, strlen(section)) || sb_add(&b, "]\n", 2) ||
        sb_kv(&b, key, value)) {
      free(b.s);
      return NULL;
    }
  }
  return b.s;
}

static int mkdir_p(const char *dir)
{
  char tmp[1024];
  if (snprintf(tmp, sizeof tmp, "%s", dir) >= (int)sizeof tmp)
    return -1;
  for (char *s = tmp + 1; *s; s++)
    if (*s == '/') {
      *s = 0;
      if (mkdir(tmp, 0755) < 0 && errno != EEXIST)
        return -1;
      *s = '/';
    }
  return (mkdir(tmp, 0755) < 0 && errno != EEXIST) ? -1 : 0;
}

int dc_update_file(const char *path, int n, const char *const *section, const char *const *key,
                   const char *const *value)
{
  char *text = NULL;
  FILE *f = fopen(path, "r");
  if (f) {
    sbuf_t b = {0};
    char chunk[4096];
    size_t r;
    sb_add(&b, "", 0);
    while ((r = fread(chunk, 1, sizeof chunk, f)) > 0)
      if (sb_add(&b, chunk, r)) {
        fclose(f);
        free(b.s);
        return -1;
      }
    fclose(f);
    text = b.s;
  } else if (errno != ENOENT)
    return -1;
  else {
    const char *hdr = "# dutctl per-DUT configuration (issue 0053); see `dutctl duts --help`\n";
    text = strdup(hdr);
    if (!text)
      return -1;
  }
  for (int i = 0; i < n; i++) {
    char *t = dc_text_set(text, section[i], key[i], value[i]);
    free(text);
    if (!t)
      return -1;
    text = t;
  }
  char dir[1024];
  snprintf(dir, sizeof dir, "%s", path);
  char *slash = strrchr(dir, '/');
  if (slash && slash != dir) {
    *slash = 0;
    if (mkdir_p(dir) < 0) {
      free(text);
      return -1;
    }
  }
  char tmp[1100];
  snprintf(tmp, sizeof tmp, "%s.tmp.%d", path, (int)getpid());
  f = fopen(tmp, "w");
  if (!f) {
    free(text);
    return -1;
  }
  size_t len = strlen(text);
  int bad = fwrite(text, 1, len, f) != len;
  bad |= fclose(f) != 0;
  free(text);
  if (bad || rename(tmp, path) < 0) {
    unlink(tmp);
    return -1;
  }
  return 0;
}

void dc_auto_name(char *buf, size_t cap, const char *ip, int dut)
{
  if (dut >= 0)
    snprintf(buf, cap, "%s/%d", ip, dut);
  else
    snprintf(buf, cap, "%s", ip);
}

const char *dc_default_cable(unsigned vid, unsigned pid)
{
  if (vid == 0x0403) {
    switch (pid) {
    case 0x6010: return "ft2232";
    case 0x6011: return "ft4232";
    case 0x6014: return "ft232";
    case 0x6001: return "ft232RL";
    }
  }
  return NULL;
}
