/* xvc.h - Xilinx Virtual Cable 1.0 command parser (TCP side of the proxy).
 * Incremental: feed whatever recv() returned; complete commands come out.
 * LGPL-2.1-or-later. */
#ifndef XVC_H
#define XVC_H

#include <stddef.h>
#include <stdint.h>

#define XVC_MAX_BYTES 65536 /* per shift: up to 524288 bits */
/* getinfo answer: TMS + TDI bytes, i.e. 8192 bytes = 65536 bits per
 * vector (openFPGALoader uint16_t limits, see main.c) */
#define XVC_ADVERTISED_BYTES 16384

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

/* One bounded shift: clock exactly n bits (n <= max_bits of the split). */
typedef int (*xvc_shift_fn)(void *ctx, uint32_t n, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo);

#define XVC_SPLIT_MAX_BITS 65536 /* upper bound for max_bits (chunk buffers) */

/* Shift `bits` as consecutive chunks of at most max_bits (the last one
 * shorter), each passed to fn: chunk k covers bits [k*max_bits, ...) of
 * tms/tdi, so the concatenation is exactly the original TMS/TDI sequence,
 * no TCK edges are added or lost, and the chunks' TDO is reassembled into
 * tdo (ceil(bits/8) bytes, unused high bits zero). Returns 0, or -1 as soon
 * as fn fails (later chunks are not sent) or max_bits is 0 / too large. */
int xvc_split_shift(uint32_t bits, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo, uint32_t max_bits,
                    xvc_shift_fn fn, void *ctx);

#endif
