/* pngwrite: minimal PNG encoder for dutctl screenshots (issue 0042).
 *
 * 8-bit RGB (colour type 2), no interlace, filter type 0 ("None") on every
 * row, zlib stream made of stored (uncompressed) deflate blocks. No library
 * dependency; the files are about as large as a PPM but open everywhere.
 *
 * Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
 */
#ifndef PNGWRITE_H
#define PNGWRITE_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/* CRC-32 (ISO 3309 / PNG / zlib). Start with crc = 0; chain calls by
 * passing the previous result. */
uint32_t pw_crc32(uint32_t crc, const uint8_t *p, size_t n);
/* Adler-32 (zlib). Start with adler = 1. */
uint32_t pw_adler32(uint32_t adler, const uint8_t *p, size_t n);

/* Exact encoded size of a width x height image (0 for an empty image). */
size_t pw_png_size(unsigned width, unsigned height);
/* Encode rgb (width * height * 3 bytes, rows top to bottom) into out.
 * Returns the number of bytes written, 0 if cap is too small or the image
 * is empty. */
size_t pw_png_encode(uint8_t *out, size_t cap, const uint8_t *rgb, unsigned width, unsigned height);
/* Encode and write to an open stream (not closed). Returns 0 on success. */
int pw_write_png_fp(FILE *fp, const uint8_t *rgb, unsigned width, unsigned height);
/* Encode and write to path. Returns 0 on success. */
int pw_write_png(const char *path, const uint8_t *rgb, unsigned width, unsigned height);

#endif
