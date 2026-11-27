/* USB JTAG adaptor discovery (issue 0053). LGPL-2.1-or-later. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "jtagdisc.h"

/* sysfs names and paths are short; truncating an absurd one is harmless */
#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic ignored "-Wformat-truncation"
#endif

#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

const char *jd_classify(unsigned vid, unsigned pid, const char *manufacturer, const char *product,
                        const char **cable)
{
  const char *m = manufacturer ? manufacturer : "", *p = product ? product : "";
  *cable = NULL;
  if (vid == 0x2a19) /* Numato: the Mimas supervisors themselves */
    return NULL;
  if (vid == 0x1443) /* Digilent's own VID (Adept-only firmware) */
    return "Digilent (Adept; not supported by openFPGALoader)";
  if (vid != 0x0403)
    return NULL;
  const char *chip;
  switch (pid) {
  case 0x6010: chip = "FTDI FT2232H"; *cable = "ft2232"; break;
  case 0x6011: chip = "FTDI FT4232H"; *cable = "ft4232"; break;
  case 0x6014: chip = "FTDI FT232H"; *cable = "ft232"; break;
  case 0x6001: chip = "FTDI FT232R"; *cable = "ft232RL"; break;
  default: return NULL;
  }
  if (strcasestr(p, "Arrow USB Blaster")) { /* FT2232H with Intel-specific firmware use */
    *cable = NULL;
    return "Arrow USB Blaster (FT2232H, Intel tools; not scanned)";
  }
  if (strcasestr(p, "TE0790"))
    return "Trenz TE0790 (FT2232H)";
  if (strcasestr(m, "Digilent")) {
    if (pid == 0x6014)
      *cable = "digilent_hs2";
    else if (pid == 0x6010)
      *cable = "digilent";
    return pid == 0x6014 ? "Digilent JTAG-HS2/HS3 (FT232H)" : "Digilent (FTDI)";
  }
  return chip;
}

static int read_line(const char *dir, const char *name, char *out, size_t cap)
{
  char path[PATH_MAX];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  out[0] = 0;
  FILE *f = fopen(path, "r");
  if (!f)
    return -1;
  if (!fgets(out, (int)cap, f))
    out[0] = 0;
  fclose(f);
  out[strcspn(out, "\r\n")] = 0;
  return 0;
}

static int cmp_path(const void *a, const void *b)
{
  return strverscmp(((const jd_adaptor_t *)a)->path, ((const jd_adaptor_t *)b)->path);
}

static int cmp_if(const void *a, const void *b)
{
  return ((const jd_iface_t *)a)->num - ((const jd_iface_t *)b)->num;
}

/* tty under an interface: "ttyUSB*" directly (ftdi_sio) or tty/NAME (cdc_acm) */
static void find_tty(const char *ifdir, char *out, size_t cap)
{
  out[0] = 0;
  DIR *d = opendir(ifdir);
  if (!d)
    return;
  struct dirent *e;
  while ((e = readdir(d)))
    if (!strncmp(e->d_name, "ttyUSB", 6) || !strncmp(e->d_name, "ttyACM", 6)) {
      snprintf(out, cap, "%s", e->d_name);
      break;
    }
  closedir(d);
  if (out[0])
    return;
  char sub[PATH_MAX];
  snprintf(sub, sizeof sub, "%s/tty", ifdir);
  d = opendir(sub);
  if (!d)
    return;
  while ((e = readdir(d)))
    if (e->d_name[0] != '.') {
      snprintf(out, cap, "%s", e->d_name);
      break;
    }
  closedir(d);
}

int jd_scan(const char *root, jd_adaptor_t *out, int max)
{
  DIR *d = opendir(root);
  if (!d)
    return -1;
  int n = 0;
  struct dirent *e;
  while ((e = readdir(d)) && n < max) {
    if (e->d_name[0] == '.' || strchr(e->d_name, ':'))
      continue; /* interfaces are "<path>:<config>.<n>" */
    char dir[PATH_MAX], v[64];
    snprintf(dir, sizeof dir, "%s/%s", root, e->d_name);
    if (read_line(dir, "idVendor", v, sizeof v) < 0)
      continue;
    jd_adaptor_t *a = &out[n];
    memset(a, 0, sizeof *a);
    a->vid = (unsigned)strtoul(v, NULL, 16);
    read_line(dir, "idProduct", v, sizeof v);
    a->pid = (unsigned)strtoul(v, NULL, 16);
    read_line(dir, "serial", a->serial, sizeof a->serial);
    read_line(dir, "manufacturer", a->manufacturer, sizeof a->manufacturer);
    read_line(dir, "product", a->product, sizeof a->product);
    if (read_line(dir, "busnum", v, sizeof v) == 0)
      a->busnum = atoi(v);
    if (read_line(dir, "devnum", v, sizeof v) == 0)
      a->devnum = atoi(v);
    a->kind = jd_classify(a->vid, a->pid, a->manufacturer, a->product, &a->cable);
    if (!a->kind)
      continue;
    snprintf(a->path, sizeof a->path, "%s", e->d_name);
    n++;
  }
  closedir(d);
  /* interfaces: second pass over the same directory */
  d = opendir(root);
  if (d) {
    while ((e = readdir(d))) {
      const char *colon = strchr(e->d_name, ':');
      if (!colon)
        continue;
      size_t pl = (size_t)(colon - e->d_name);
      for (int i = 0; i < n; i++) {
        jd_adaptor_t *a = &out[i];
        if (strlen(a->path) != pl || strncmp(a->path, e->d_name, pl) || a->nif == JD_MAX_IFS)
          continue;
        char dir[PATH_MAX], v[64], link[PATH_MAX];
        snprintf(dir, sizeof dir, "%s/%s", root, e->d_name);
        jd_iface_t *f = &a->ifs[a->nif];
        memset(f, 0, sizeof *f);
        if (read_line(dir, "bInterfaceNumber", v, sizeof v) == 0)
          f->num = (int)strtol(v, NULL, 16);
        else {
          const char *dot = strrchr(e->d_name, '.');
          f->num = dot ? atoi(dot + 1) : 0;
        }
        char drv[PATH_MAX];
        snprintf(drv, sizeof drv, "%s/driver", dir);
        ssize_t l = readlink(drv, link, sizeof link - 1);
        if (l > 0) {
          link[l] = 0;
          const char *b = strrchr(link, '/');
          snprintf(f->driver, sizeof f->driver, "%s", b ? b + 1 : link);
        }
        find_tty(dir, f->tty, sizeof f->tty);
        a->nif++;
      }
    }
    closedir(d);
  }
  qsort(out, (size_t)n, sizeof *out, cmp_path);
  for (int i = 0; i < n; i++)
    qsort(out[i].ifs, (size_t)out[i].nif, sizeof out[i].ifs[0], cmp_if);
  return n;
}

const char *jd_tty(const jd_adaptor_t *a, int num)
{
  for (int i = 0; i < a->nif; i++)
    if (a->ifs[i].num == num)
      return a->ifs[i].tty;
  return "";
}

int jd_parse_detect(const char *out, uint32_t *ids, int max)
{
  int n = 0;
  const char *p = out;
  while (n < max && (p = strstr(p, "idcode"))) {
    p += 6;
    while (*p == ' ' || *p == '\t' || *p == ':')
      p++;
    char *end;
    unsigned long v = strtoul(p, &end, 16);
    if (end == p)
      continue;
    p = end;
    if (v == 0 || v == 0xFFFFFFFFul)
      continue;
    ids[n++] = (uint32_t)v;
  }
  return n;
}

static void add(jd_cmd_t *c, const char *s)
{
  if (c->argc >= 23)
    return;
  snprintf(c->store[c->argc], sizeof c->store[0], "%s", s);
  c->argv[c->argc] = c->store[c->argc];
  c->argc++;
  c->argv[c->argc] = NULL;
}

int jd_ofl_cmd(jd_cmd_t *c, const char *ofl, const char *cable, unsigned vid, unsigned pid,
               const char *serial, const char *busdev, int channel, long freq, const char *mode, int port)
{
  memset(c, 0, sizeof *c);
  if (!cable || !*cable)
    return -1;
  char b[32];
  add(c, ofl);
  add(c, "-c");
  add(c, cable);
  if (serial && *serial) {
    add(c, "--ftdi-serial");
    add(c, serial);
  } else if (busdev && *busdev) {
    add(c, "--busdev-num");
    add(c, busdev);
  } else if (vid && pid) {
    snprintf(b, sizeof b, "0x%04x", vid);
    add(c, "--vid");
    add(c, b);
    snprintf(b, sizeof b, "0x%04x", pid);
    add(c, "--pid");
    add(c, b);
  }
  if (channel >= 0) {
    snprintf(b, sizeof b, "%d", channel);
    add(c, "--ftdi-channel");
    add(c, b);
  }
  if (freq > 0) {
    snprintf(b, sizeof b, "%ld", freq);
    add(c, "--freq");
    add(c, b);
  }
  if (!strcmp(mode, "xvc")) {
    add(c, "--xvc");
    snprintf(b, sizeof b, "%d", port);
    add(c, "--port");
    add(c, b);
  } else
    add(c, "--detect");
  return 0;
}

void jd_cmd_str(const jd_cmd_t *c, char *buf, unsigned cap)
{
  size_t l = 0;
  buf[0] = 0;
  for (int i = 0; i < c->argc && l + 1 < cap; i++) {
    const char *a = c->argv[i];
    int plain = *a && strspn(a, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=+,@") ==
                          strlen(a);
    int k;
    if (plain)
      k = snprintf(buf + l, cap - l, "%s%s", i ? " " : "", a);
    else {
      k = snprintf(buf + l, cap - l, "%s'", i ? " " : "");
      if (k < 0 || (size_t)k >= cap - l)
        return;
      l += (size_t)k;
      for (const char *s = a; *s && l + 5 < cap; s++) {
        if (*s == '\'')
          l += (size_t)snprintf(buf + l, cap - l, "'\\''");
        else
          buf[l++] = *s, buf[l] = 0;
      }
      k = snprintf(buf + l, cap - l, "'");
    }
    if (k < 0 || (size_t)k >= cap - l)
      return;
    l += (size_t)k;
  }
}
