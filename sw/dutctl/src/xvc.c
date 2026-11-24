/* xvc.c - XVC 1.0 parser. LGPL-2.1-or-later. */
#include "xvc.h"

#include <string.h>

void xvc_init(xvc_parser_t *p)
{
  memset(p, 0, sizeof *p);
}

int xvc_feed(xvc_parser_t *p, const uint8_t *data, size_t n)
{
  if (p->len + n > sizeof p->buf)
    return -1;
  memcpy(p->buf + p->len, data, n);
  p->len += n;
  return 0;
}

static uint32_t le32(const uint8_t *b)
{
  return (uint32_t)b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
}

xvc_cmd_t xvc_next(xvc_parser_t *p)
{
  p->cmd = XVC_NONE;
  if (p->len >= 8 && memcmp(p->buf, "getinfo:", 8) == 0) {
    p->cmd = XVC_GETINFO;
    p->cmd_len = 8;
  } else if (p->len >= 7 && memcmp(p->buf, "settck:", 7) == 0) {
    if (p->len >= 11) {
      p->cmd = XVC_SETTCK;
      p->settck_period_ns = le32(p->buf + 7);
      p->cmd_len = 11;
    }
  } else if (p->len >= 6 && memcmp(p->buf, "shift:", 6) == 0) {
    if (p->len >= 10) {
      uint32_t bits = le32(p->buf + 6);
      size_t nb = (bits + 7) / 8;
      if (nb > XVC_MAX_BYTES) {
        p->cmd = XVC_ERROR;
        p->cmd_len = p->len;
      } else if (p->len >= 10 + 2 * nb) {
        p->cmd = XVC_SHIFT;
        p->shift_bits = bits;
        p->tms = p->buf + 10;
        p->tdi = p->buf + 10 + nb;
        p->cmd_len = 10 + 2 * nb;
      }
    }
  } else if (p->len >= 8) {
    /* no valid prefix fits: protocol error */
    p->cmd = XVC_ERROR;
    p->cmd_len = p->len;
  } else {
    /* could still be a prefix of a valid command */
    static const char *const pfx[] = {"getinfo:", "settck:", "shift:"};
    int possible = 0;
    for (int i = 0; i < 3; i++)
      if (memcmp(p->buf, pfx[i], p->len < strlen(pfx[i]) ? p->len : strlen(pfx[i])) == 0)
        possible = 1;
    if (!possible && p->len) {
      p->cmd = XVC_ERROR;
      p->cmd_len = p->len;
    }
  }
  return p->cmd;
}

void xvc_consume(xvc_parser_t *p)
{
  if (p->cmd == XVC_NONE)
    return;
  memmove(p->buf, p->buf + p->cmd_len, p->len - p->cmd_len);
  p->len -= p->cmd_len;
  p->cmd = XVC_NONE;
  p->tms = p->tdi = NULL;
}

void xvc_copy_bits(uint8_t *dst, const uint8_t *src, uint32_t start, uint32_t n)
{
  memset(dst, 0, (n + 7) / 8);
  for (uint32_t i = 0; i < n; i++) {
    uint32_t s = start + i;
    if (src[s / 8] & (1u << (s % 8)))
      dst[i / 8] |= (uint8_t)(1u << (i % 8));
  }
}
