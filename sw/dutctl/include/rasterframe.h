/* rasterframe: assemble raster line packets (ADR 0005 section 8, format v1)
 * into frames and report completeness (issue 0024).
 *
 * Feed decoded packets in arrival order. A frame is emitted
 *   - as soon as lines 0..v_active-1 have all arrived (complete, unless the
 *     line widths disagree), or
 *   - when a packet of a newer frame arrives first (then incomplete).
 * Packets of an already emitted / older frame are counted as late and
 * ignored. Duplicate lines are counted (the newest copy wins).
 *
 * Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
 */
#ifndef RASTERFRAME_H
#define RASTERFRAME_H

#include <stddef.h>
#include <stdint.h>

#include "dutproto.h"

#define RF_MAX_LINES 1024

typedef struct {
  uint32_t frame;
  uint16_t width, height;   /* width = active_count of line 0 (or first line seen) */
  const uint8_t *rgb;       /* width * height * 3 bytes; missing lines are black */
  int complete;             /* all lines present with equal width */
  uint16_t lines_received;  /* distinct active lines */
  uint16_t duplicates;
  int width_mismatch;
  int dropped_flag;         /* some packet of this frame had RF_DROPPED */
} rf_frame_t;

typedef struct {
  int active;               /* a frame is being assembled */
  int emitted;              /* current frame number already emitted */
  uint32_t frame;
  uint16_t width, height;
  uint16_t lines_received, duplicates;
  int width_mismatch, dropped_flag;
  uint8_t have[RF_MAX_LINES];
  uint8_t rgb[3u * DP_RASTER_MAX_PX * RF_MAX_LINES];
  uint8_t out[3u * DP_RASTER_MAX_PX * RF_MAX_LINES];
  uint32_t late;            /* packets for frames already emitted / older */
} rf_asm_t;

void rf_init(rf_asm_t *a);

/* Feed one decoded packet. Returns 1 and fills *out when a frame is emitted
 * (out->rgb stays valid until the next rf_feed / rf_flush), 0 otherwise,
 * -1 for a packet that cannot be used (bad pixels). A packet that emits the
 * previous frame as incomplete is itself kept for the next frame. */
int rf_feed(rf_asm_t *a, const dp_raster_t *r, rf_frame_t *out);

/* Emit the frame being assembled (incomplete unless all lines arrived). */
int rf_flush(rf_asm_t *a, rf_frame_t *out);

/* Write a frame as binary PPM (P6). Returns 0 on success. */
int rf_write_ppm(const char *path, const rf_frame_t *f);

#endif
