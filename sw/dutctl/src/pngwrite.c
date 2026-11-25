/* pngwrite: minimal PNG encoder (issue 0042). See pngwrite.h.
 * Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
 */
#include "pngwrite.h"

#include <stdlib.h>
#include <string.h>

#define STORED_MAX 65535u

uint32_t pw_crc32(uint32_t crc, const uint8_t *p, size_t n)
{
  static uint32_t tab[256];
  static int init;
  if (!init) {
    for (uint32_t i = 0; i < 256; i++) {
      uint32_t c = i;
      for (int k = 0; k < 8; k++)
        c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
      tab[i] = c;
    }
    init = 1;
  }
  crc = ~crc;
  while (n--)
    crc = tab[(crc ^ *p++) & 0xFF] ^ (crc >> 8);
  return ~crc;
}

uint32_t pw_adler32(uint32_t adler, const uint8_t *p, size_t n)
{
  uint32_t a = adler & 0xFFFF, b = adler >> 16;
  while (n) {
    size_t k = n < 5552 ? n : 5552; /* largest run without 32-bit overflow */
    n -= k;
    while (k--) {
      a += *p++;
      b += a;
    }
    a %= 65521;
    b %= 65521;
  }
  return b << 16 | a;
}

static size_t raw_len(unsigned w, unsigned h) { return (size_t)h * (1 + 3 * (size_t)w); }

static size_t zlib_len(size_t raw)
{
  size_t blocks = raw ? (raw + STORED_MAX - 1) / STORED_MAX : 1;
  return 2 + raw + 5 * blocks + 4;
}

size_t pw_png_size(unsigned width, unsigned height)
{
  if (!width || !height || width > 0x7FFFFFFFu || height > 0x7FFFFFFFu)
    return 0;
  return 8 + (12 + 13) + (12 + zlib_len(raw_len(width, height))) + 12;
}

static void put32(uint8_t *p, uint32_t v)
{
  p[0] = (uint8_t)(v >> 24);
  p[1] = (uint8_t)(v >> 16);
  p[2] = (uint8_t)(v >> 8);
  p[3] = (uint8_t)v;
}

/* chunk at p: length, type, data (already written at p + 8), CRC */
static size_t finish_chunk(uint8_t *p, const char *type, size_t len)
{
  put32(p, (uint32_t)len);
  memcpy(p + 4, type, 4);
  put32(p + 8 + len, pw_crc32(0, p + 4, 4 + len));
  return 12 + len;
}

size_t pw_png_encode(uint8_t *out, size_t cap, const uint8_t *rgb, unsigned width, unsigned height)
{
  size_t total = pw_png_size(width, height);
  if (!total || cap < total)
    return 0;
  uint8_t *p = out;
  memcpy(p, "\x89PNG\r\n\x1a\n", 8);
  p += 8;

  uint8_t *d = p + 8; /* IHDR */
  put32(d, width);
  put32(d + 4, height);
  d[8] = 8;  /* bit depth */
  d[9] = 2;  /* colour type: RGB */
  d[10] = 0; /* compression: deflate */
  d[11] = 0; /* filter method 0 */
  d[12] = 0; /* no interlace */
  p += finish_chunk(p, "IHDR", 13);

  /* IDAT: zlib header (CM 8, CINFO 7, FLEVEL 0, FCHECK so 0x7801 % 31 == 0),
   * stored deflate blocks of at most 65535 bytes, Adler-32 of the raw data */
  size_t raw = raw_len(width, height), stride = 3 * (size_t)width;
  d = p + 8;
  uint8_t *z = d;
  *z++ = 0x78;
  *z++ = 0x01;
  uint32_t adler = 1;
  size_t left = raw, row = 0, col = 0; /* col: position in the row incl. the filter byte */
  do {
    size_t blk = left < STORED_MAX ? left : STORED_MAX;
    left -= blk;
    *z++ = left ? 0 : 1; /* BFINAL, BTYPE 00 (stored), padding to the byte */
    *z++ = (uint8_t)blk;
    *z++ = (uint8_t)(blk >> 8);
    *z++ = (uint8_t)~blk;
    *z++ = (uint8_t)(~blk >> 8);
    uint8_t *start = z;
    while (blk) {
      if (col == 0) {
        *z++ = 0; /* filter type None */
        col = 1;
        blk--;
        continue;
      }
      size_t k = stride - (col - 1);
      if (k > blk)
        k = blk;
      memcpy(z, rgb + row * stride + (col - 1), k);
      z += k;
      blk -= k;
      col += k;
      if (col == stride + 1) {
        col = 0;
        row++;
      }
    }
    adler = pw_adler32(adler, start, (size_t)(z - start));
  } while (left);
  put32(z, adler);
  z += 4;
  p += finish_chunk(p, "IDAT", (size_t)(z - d));
  p += finish_chunk(p, "IEND", 0);
  return (size_t)(p - out);
}

int pw_write_png_fp(FILE *fp, const uint8_t *rgb, unsigned width, unsigned height)
{
  size_t n = pw_png_size(width, height);
  if (!n)
    return -1;
  uint8_t *buf = malloc(n);
  if (!buf)
    return -1;
  int ret = -1;
  if (pw_png_encode(buf, n, rgb, width, height) == n && fwrite(buf, 1, n, fp) == n)
    ret = 0;
  free(buf);
  return ret;
}

int pw_write_png(const char *path, const uint8_t *rgb, unsigned width, unsigned height)
{
  FILE *fp = fopen(path, "wb");
  if (!fp)
    return -1;
  int ok = pw_write_png_fp(fp, rgb, width, height) == 0;
  return (fclose(fp) == 0 && ok) ? 0 : -1;
}
