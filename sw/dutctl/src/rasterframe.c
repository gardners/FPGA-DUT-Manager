/* rasterframe: raster line packets -> frames (issue 0024). See rasterframe.h.
 * Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
 */
#include "rasterframe.h"

#include <stdio.h>
#include <string.h>

void rf_init(rf_asm_t *a)
{
  a->active = 0;
  a->emitted = 0;
  a->late = 0;
}

static void start_frame(rf_asm_t *a, const dp_raster_t *r)
{
  a->active = 1;
  a->emitted = 0;
  a->frame = r->frame;
  a->width = 0;
  a->height = r->v_active > RF_MAX_LINES ? RF_MAX_LINES : r->v_active;
  a->lines_received = a->duplicates = 0;
  a->width_mismatch = a->dropped_flag = 0;
  memset(a->have, 0, sizeof a->have);
}

static void emit(rf_asm_t *a, rf_frame_t *out)
{
  size_t stride = 3u * a->width;
  /* copy into the output buffer, black for missing lines */
  for (unsigned y = 0; y < a->height; y++) {
    uint8_t *dst = a->out + y * stride;
    if (a->have[y])
      memcpy(dst, a->rgb + (size_t)y * 3u * DP_RASTER_MAX_PX, stride);
    else
      memset(dst, 0, stride);
  }
  out->frame = a->frame;
  out->width = a->width;
  out->height = a->height;
  out->rgb = a->out;
  out->lines_received = a->lines_received;
  out->duplicates = a->duplicates;
  out->width_mismatch = a->width_mismatch;
  out->dropped_flag = a->dropped_flag;
  out->complete = a->height > 0 && a->lines_received == a->height && !a->width_mismatch;
  a->emitted = 1;
}

int rf_flush(rf_asm_t *a, rf_frame_t *out)
{
  if (!a->active || a->emitted)
    return 0;
  emit(a, out);
  return 1;
}

int rf_feed(rf_asm_t *a, const dp_raster_t *r, rf_frame_t *out)
{
  int ret = 0;
  if (a->active && r->frame != a->frame) {
    if ((int32_t)(r->frame - a->frame) < 0) { /* older frame: late packet */
      a->late++;
      return 0;
    }
    if (!a->emitted) { /* newer frame started before this one completed */
      emit(a, out);
      ret = 1;
    }
    a->active = 0;
  }
  if (!a->active)
    start_frame(a, r);
  else if (a->emitted) { /* frame already emitted complete: duplicates are late */
    a->late++;
    return ret;
  }
  if (r->flags & DP_RF_DROPPED)
    a->dropped_flag = 1;
  if (r->v_active && a->height == 0)
    a->height = r->v_active > RF_MAX_LINES ? RF_MAX_LINES : r->v_active;
  if (!(r->flags & DP_RF_ACTIVE) || r->active_count == 0 || r->line >= RF_MAX_LINES)
    return ret; /* blanking line: geometry only */

  if (a->width == 0)
    a->width = r->active_count;
  else if (r->active_count != a->width)
    a->width_mismatch = 1;
  uint8_t *dst = a->rgb + (size_t)r->line * 3u * DP_RASTER_MAX_PX;
  if (dp_raster_pixels(r, dst, 3u * DP_RASTER_MAX_PX) != (int)r->active_count)
    return -1;
  if (a->have[r->line])
    a->duplicates++;
  else {
    a->have[r->line] = 1;
    a->lines_received++;
  }
  if (!ret && a->height && a->lines_received == a->height) {
    emit(a, out);
    ret = 1;
  }
  return ret;
}

int rf_write_ppm(const char *path, const rf_frame_t *f)
{
  FILE *fp = fopen(path, "wb");
  if (!fp)
    return -1;
  fprintf(fp, "P6\n%u %u\n255\n", f->width, f->height);
  size_t n = 3u * f->width * f->height;
  int ok = fwrite(f->rgb, 1, n, fp) == n;
  return (fclose(fp) == 0 && ok) ? 0 : -1;
}
