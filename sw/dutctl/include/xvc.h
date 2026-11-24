/* xvc.h - Xilinx Virtual Cable 1.0 command parser (TCP side of the proxy).
 * Incremental: feed whatever recv() returned; complete commands come out.
 * LGPL-2.1-or-later. */
#ifndef XVC_H
#define XVC_H

#include <stddef.h>
#include <stdint.h>

#define XVC_MAX_BYTES 65536 /* per shift: up to 524288 bits */

typedef enum { XVC_NONE = 0, XVC_GETINFO, XVC_SETTCK, XVC_SHIFT, XVC_ERROR } xvc_cmd_t;

typedef struct {
  uint8_t buf[2 * XVC_MAX_BYTES + 32];
  size_t len;
  /* decoded command */
  xvc_cmd_t cmd;
  uint32_t settck_period_ns;
  uint32_t shift_bits;
  const uint8_t *tms, *tdi; /* point into buf until the next xvc_consume */
  size_t cmd_len;
} xvc_parser_t;

void xvc_init(xvc_parser_t *p);
/* Append received bytes; returns -1 if the buffer would overflow. */
int xvc_feed(xvc_parser_t *p, const uint8_t *data, size_t n);
/* Try to decode the next complete command; returns its type or XVC_NONE. */
xvc_cmd_t xvc_next(xvc_parser_t *p);
/* Drop the command returned by xvc_next. */
void xvc_consume(xvc_parser_t *p);

/* Split a shift of `bits` into chunks of at most max_bits, preserving bit
 * order exactly (no extra TCK edges). Copies bits [start, start+n) of src
 * (LSB-first packing) into dst starting at bit 0. */
void xvc_copy_bits(uint8_t *dst, const uint8_t *src, uint32_t start, uint32_t n);

#endif
