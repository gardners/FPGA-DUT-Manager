/* Unit tests for dutctl: protocol vectors, UART merging, XVC parsing, per-DUT
 * config, JTAG speed probe (on a simulated chain) and USB adaptor discovery
 * (on a fake sysfs tree). */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <ftw.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "dutproto.h"
#include "uartstream.h"
#include "xvc.h"
#include "rasterframe.h"
#include "pngwrite.h"
#include "screenshot.h"
#include "dutconf.h"
#include "jtagdisc.h"
#include "jtagspeed.h"

static int failures, checks;
#define CHECK(c)                                                                   \
  do {                                                                             \
    checks++;                                                                      \
    if (!(c)) {                                                                    \
      failures++;                                                                  \
      fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #c);      \
    }                                                                              \
  } while (0)

/* ------------------------------------------------------------ vectors */
typedef struct {
  char name[32];
  uint8_t data[DP_RASTER_MAX_PACKET];
  size_t len;
} vec_t;
static vec_t vecs[32];
static int nvecs;

static void load_vectors(const char *path)
{
  FILE *f = fopen(path, "r");
  if (!f) {
    perror(path);
    exit(1);
  }
  static char hex[2 * DP_RASTER_MAX_PACKET + 8];
  while (nvecs < 32 && fscanf(f, "%31s %6240s", vecs[nvecs].name, hex) == 2) {
    size_t l = strlen(hex) / 2;
    for (size_t i = 0; i < l; i++) {
      unsigned b;
      sscanf(hex + 2 * i, "%2x", &b);
      vecs[nvecs].data[i] = (uint8_t)b;
    }
    vecs[nvecs].len = l;
    nvecs++;
  }
  fclose(f);
}

static const vec_t *vec(const char *name)
{
  for (int i = 0; i < nvecs; i++)
    if (!strcmp(vecs[i].name, name))
      return &vecs[i];
  fprintf(stderr, "missing vector %s\n", name);
  exit(1);
}

static void check_bytes(const char *name, const uint8_t *buf, size_t n)
{
  const vec_t *v = vec(name);
  CHECK(n == v->len);
  if (n == v->len && memcmp(buf, v->data, n)) {
    failures++;
    fprintf(stderr, "vector %s differs\n", name);
  }
}

static void test_encoders(void)
{
  uint8_t b[DP_MAX_PACKET];
  uint8_t v[4];
  dp_put32(v, 68719477);
  check_bytes("mgmt_baud", b, dp_encode_mgmt_set(b, 0, 0x1234, DP_K_UART_BAUD, v, 4));
  uint8_t ip[4] = {10, 1, 2, 3};
  check_bytes("mgmt_ip", b, dp_encode_mgmt_set(b, DP_DUT_ANY, 7, DP_K_IP, ip, 4));
  uint8_t bm[10] = {0};
  bm[10 / 8] |= 1 << (10 % 8);
  bm[63 / 8] |= 1 << (63 % 8);
  bm[79 / 8] |= 1 << (79 % 8);
  check_bytes("kbd_wild", b, dp_encode_kbd_set(b, DP_DUT_ANY, bm));
  check_bytes("uart_hello_clear", b,
              dp_encode_uart_tx(b, 1, 0xFFFFFFFEu, 9, 1, (const uint8_t *)"HELLO", 5));
  const char *s = "111110100" "0000000000000000000000000000000" "1";
  uint8_t tms[6] = {0}, tdi[6] = {0};
  for (size_t i = 0; i < strlen(s); i++)
    if (s[i] == '1')
      tms[i / 8] |= (uint8_t)(1u << (i % 8));
  check_bytes("jtag_41", b, dp_encode_jtag_req(b, 0, 0xDEADBEEF, 6, 0, 0, 41, tms, tdi));
  uint8_t one = 1, zero = 0;
  check_bytes("jtag_kbd_reset", b,
              dp_encode_jtag_req(b, DP_DUT_ANY, 7, 6, 0, DP_JF_ABORT | DP_JF_KBD, 1, &one, &zero));
  CHECK(dp_encode_jtag_req(b, 0, 0, 6, 0, 0, 0, tms, tdi) == 0);
  CHECK(dp_encode_jtag_req(b, 0, 0, 6, 0, 0, 8193, tms, tdi) == 0);
  CHECK(dp_baud_nco(2e6) == 0x04189375);
  CHECK(dp_key_by_name("return") == 1 && dp_key_by_name("A") == 10 && dp_key_by_name("space") == 60);
  CHECK(dp_key_by_name("nonsense") == -1);
}

static void test_decoders(void)
{
  const vec_t *v = vec("heartbeat");
  dp_hdr_t h;
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0);
  CHECK(h.type == DP_T_HEARTBEAT && h.dut == 1 && h.length == 100);
  dp_heartbeat_t hb;
  CHECK(dp_decode_heartbeat(v->data + 8, h.length, &hb) == 0);
  CHECK(hb.hb_seq == 42 && hb.boot_id == 0x11223344 && hb.build_id == 0xC0DE0001);
  CHECK(hb.dna == 0x0123456789ABCDEFull && hb.topo_count == 2 && hb.dip == 5);
  CHECK(hb.caps == 7 && hb.cfg_gen == 9 && hb.target_flags == 0x0F && hb.selected == 0x10);
  CHECK(hb.kbd_eff[1] == 0x04 && hb.kbd_eff[9] == 0x80 && hb.kbd_udp[1] == 0x04);
  CHECK(hb.kbd_phys[7] == 0x10);
  CHECK(hb.phys_change == 3 && hb.phys_type == 2 && hb.jtag_status == 2);
  CHECK(hb.jtag_next_seq == 77 && hb.uart_rx_seq == 1000 && hb.uart_tx_acc == 55);
  CHECK(hb.rx_rejects == 4 && hb.tx_drops == 1 && hb.dut_leds[11] == 11);
  CHECK(hb.addr_src == 1 && hb.dut_id == 7 && !hb.has_video);

  v = vec("heartbeat_video");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && h.length == 124 && h.dut == 0);
  CHECK(dp_decode_heartbeat(v->data + 8, h.length, &hb) == 0);
  CHECK(hb.hb_seq == 42 && hb.dut_id == 7 && hb.has_video && hb.video_flags == 7);
  CHECK(hb.console_screen == DP_CON_PASSTHROUGH);
  CHECK(strcmp(dp_con_shown_name(DP_CON_PASSTHROUGH), "passthrough") == 0);
  CHECK(strcmp(dp_con_shown_name(DP_CON_SELECT), "select") == 0);
  CHECK(strcmp(dp_con_shown_name(9), "?") == 0);
  CHECK(hb.h_total == 864 && hb.v_total == 625 && hb.h_active == 720 && hb.v_active == 576);
  CHECK(hb.pixel_clock_hz == 27000000 && hb.frames_captured == 0x01020304);
  CHECK(hb.raster_lines_dropped == 5 && hb.tmds_decode_errors == 6);
  CHECK(!hb.has_link);

  v = vec("heartbeat_link");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && h.length == 132 && h.dut == 1);
  CHECK(dp_decode_heartbeat(v->data + 8, h.length, &hb) == 0);
  CHECK(hb.has_video && hb.video_flags == 7 && hb.tmds_decode_errors == 6);
  CHECK(hb.has_link && hb.rx_phase_pos == 3 && hb.rx_eye_width == 24);
  CHECK(hb.rx_hunts == 2 && hb.rx_bad_frames == 300 && hb.rx_link_flags == 2);
  CHECK(!hb.has_mem);

  v = vec("heartbeat_mem");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && h.length == 144 && h.dut == 0);
  CHECK(dp_decode_heartbeat(v->data + 8, h.length, &hb) == 0);
  CHECK(hb.has_link && hb.rx_bad_frames == 300 && hb.has_mem);
  CHECK(hb.mem_flags == (DP_MEM_CALIBRATED | DP_MEM_ST_DONE) && hb.mem_errors == 513);
  CHECK(hb.mem_dq_fail == 0x8001 && hb.mem_test_kib == 1024 && hb.mem_first_err == 0x00ABCDEF);

  v = vec("snapshot");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && h.type == DP_T_UART_SNAP);
  static dp_snapshot_t sn;
  CHECK(dp_decode_snapshot(v->data + 8, h.length, &sn) == 0);
  CHECK(sn.rx_seq == 5 && sn.tx_free == 2043 && sn.framing_errors == 1 && sn.tx_rejects == 2);
  CHECK(sn.baud_nco == 68719477 && !memcmp(sn.rx_history + 507, "HELLO", 5));
  CHECK(!memcmp(sn.tx_history + 123, "HELLO", 5));

  v = vec("jtag_resp");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && h.type == DP_T_JTAG_RESP);
  static dp_jtag_resp_t jr;
  CHECK(dp_decode_jtag_resp(v->data + 8, h.length, &jr) == 0);
  CHECK(jr.seq == 0xDEADBEEF && jr.next_seq == 0xDEADBEF0 && jr.bit_count == 41 && jr.tdo_bytes == 6);
  uint64_t t = 0;
  for (int i = 5; i >= 0; i--)
    t = t << 8 | jr.tdo[i];
  CHECK((uint32_t)(t >> 9) == 0x0362C093);
  CHECK(jr.target == DP_JT_DUT);

  v = vec("jtag_resp_kbd");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && h.type == DP_T_JTAG_RESP && h.dut == 1);
  CHECK(dp_decode_jtag_resp(v->data + 8, h.length, &jr) == 0);
  CHECK(jr.target == DP_JT_KBD && jr.status == DP_JS_DONE && jr.seq == 3 && jr.next_seq == 4);
  t = 0;
  for (int i = 5; i >= 0; i--)
    t = t << 8 | jr.tdo[i];
  CHECK((uint32_t)(t >> 9) == 0x012BA043); /* LCMXO2-1200HC */

  v = vec("ack");
  dp_ack_t a;
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && dp_decode_ack(v->data + 8, h.length, &a) == 0);
  CHECK(a.cmd_id == 0x1234 && a.key == 0x10 && a.status == 0 && a.cfg_gen == 9);

  static uint8_t px[3 * DP_RASTER_MAX_PX];
  dp_raster_t r;
  v = vec("raster_active");
  CHECK(v->len == 2212 && dp_parse_hdr(v->data, v->len, &h) == 0 && h.type == DP_T_RASTER);
  CHECK(dp_decode_raster(v->data + 8, h.length, &r) == 0);
  CHECK(r.frame == 0x89ABCDEF && r.line == 5 && r.h_total == 864 && r.v_total == 625);
  CHECK(r.version == 1 && r.active_count == 720 && r.v_active == 576);
  CHECK(r.hs_start == 732 && r.hs_end == 796);
  CHECK(r.flags == (DP_RF_ACTIVE | DP_RF_LOCKED | DP_RF_HSYNC_POL) && r.encoding == DP_ENC_RAW);
  CHECK(r.payload_bytes == 2160 && r.uart_rx_seq == 1000);
  CHECK(!memcmp(r.uart_rx_history + 8, "READY.\r\n", 8) && r.uart_rx_history[7] == 0);
  CHECK(dp_raster_pixels(&r, px, sizeof px) == 720);
  int pxok = 1;
  for (int x = 0; x < 720; x++)
    pxok &= px[3 * x] == (x & 0xFF) && px[3 * x + 1] == ((x >> 8) ^ 5) && px[3 * x + 2] == ((3 * x) & 0xFF);
  CHECK(pxok);
  CHECK(dp_decode_raster(v->data + 8, h.length - 1, &r) < 0); /* truncated */

  v = vec("raster_blank");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0 && h.length == 44 && h.dut == 1);
  CHECK(dp_decode_raster(v->data + 8, h.length, &r) == 0);
  CHECK(r.frame == 7 && r.line == 600 && r.active_count == 0 && r.payload_bytes == 0);
  CHECK(r.flags == (DP_RF_VSYNC | DP_RF_LOCKED | DP_RF_DROPPED) && r.uart_rx_seq == 0xFFFFFFFFu);

  v = vec("raster_rle");
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0);
  CHECK(dp_decode_raster(v->data + 8, h.length, &r) == 0);
  CHECK(r.encoding == DP_ENC_RLE24 && r.active_count == 320 && r.payload_bytes == 12);
  CHECK(r.flags == (DP_RF_ACTIVE | DP_RF_FIRST | DP_RF_LOCKED) && r.line == 0 && r.frame == 8);
  CHECK(dp_raster_pixels(&r, px, sizeof px) == 320);
  CHECK(px[0] == 0x10 && px[899 * 1] == 0x30 && px[900] == 1 && px[959] == 3);

  v = vec("raster_badver"); /* unknown raster format version is rejected */
  CHECK(dp_parse_hdr(v->data, v->len, &h) == 0);
  CHECK(dp_decode_raster(v->data + 8, h.length, &r) < 0);

  /* malformed */
  uint8_t bad[16] = {0x4D, 0x36, 1, 1, 0, 9, 0, 0};
  CHECK(dp_parse_hdr(bad, 16, &h) < 0); /* length mismatch */
  bad[5] = 8;
  bad[0] = 0;
  CHECK(dp_parse_hdr(bad, 16, &h) < 0); /* magic */
}

/* ------------------------------------------------------------ UART merge */
static dp_snapshot_t mk_snap(uint32_t boot, uint32_t rx_seq, uint32_t clear_at, uint8_t (*byte_at)(uint32_t))
{
  dp_snapshot_t s;
  memset(&s, 0, sizeof s);
  s.boot_id = boot;
  s.rx_seq = rx_seq;
  s.rx_seq_at_clear = clear_at;
  s.tx_free = 2048;
  uint32_t since = rx_seq - clear_at, valid = since < 512 ? since : 512;
  for (uint32_t p = 512 - valid; p < 512; p++)
    s.rx_history[p] = byte_at(rx_seq - 512 + p);
  return s;
}
static uint8_t pattern(uint32_t off) { return (uint8_t)(off * 7 + 3); }

static void test_uart_merge(void)
{
  us_state_t us;
  uint8_t out[1024];
  uint32_t lost;
  us_init(&us);
  /* first snapshot, from start */
  dp_snapshot_t s = mk_snap(1, 100, 0, pattern);
  size_t n = us_rx_snapshot(&us, &s, out, sizeof out, 0, &lost);
  CHECK(n == 100 && lost == 0 && out[0] == pattern(0) && out[99] == pattern(99));
  /* overlapping snapshot: only the new bytes */
  s = mk_snap(1, 150, 0, pattern);
  n = us_rx_snapshot(&us, &s, out, sizeof out, 0, &lost);
  CHECK(n == 50 && out[0] == pattern(100) && lost == 0);
  /* duplicate / stale snapshot */
  n = us_rx_snapshot(&us, &s, out, sizeof out, 0, &lost);
  CHECK(n == 0);
  s = mk_snap(1, 120, 0, pattern);
  CHECK(us_rx_snapshot(&us, &s, out, sizeof out, 0, &lost) == 0);
  /* gap larger than history */
  s = mk_snap(1, 1000, 0, pattern);
  n = us_rx_snapshot(&us, &s, out, sizeof out, 0, &lost);
  CHECK(lost == 1000 - 512 - 150 && n == 512 && out[0] == pattern(488));
  /* wrap around 2^32 */
  us_init(&us);
  s = mk_snap(2, 0xFFFFFFF0u, 0xFFFFF000u, pattern);
  n = us_rx_snapshot(&us, &s, out, sizeof out, 1, &lost); /* start at end */
  CHECK(n == 0);
  s = mk_snap(2, 0x10, 0xFFFFF000u, pattern);
  n = us_rx_snapshot(&us, &s, out, sizeof out, 1, &lost);
  CHECK(n == 0x20 && out[0] == pattern(0xFFFFFFF0u) && out[0x1F] == pattern(0xF) && lost == 0);
  /* reboot resets */
  s = mk_snap(3, 10, 0, pattern);
  n = us_rx_snapshot(&us, &s, out, sizeof out, 0, &lost);
  CHECK(us.reboots == 1 && n == 10 && out[0] == pattern(0));
  /* clear: bytes before rx_seq_at_clear are padding, not data */
  us_init(&us);
  s = mk_snap(4, 300, 290, pattern);
  n = us_rx_snapshot(&us, &s, out, sizeof out, 0, &lost);
  CHECK(n == 10 && out[0] == pattern(290));
  /* TX accounting */
  us.tx_acked = 100;
  us.tx_sent = 110;
  CHECK(us_tx_unaccepted(&us) == 10);
  us.tx_acked = 110;
  CHECK(us_tx_unaccepted(&us) == 0);
}

/* ------------------------------------------------------------ XVC */
static void test_xvc(void)
{
  static xvc_parser_t p;
  xvc_init(&p);
  const uint8_t msg[] = "getinfo:settck:\x64\x00\x00\x00shift:\x0b\x00\x00\x00\xff\x07\x01\x02";
  size_t len = sizeof msg - 1;
  /* feed one byte at a time to exercise TCP segmentation */
  int seen[4] = {0};
  for (size_t i = 0; i < len; i++) {
    CHECK(xvc_feed(&p, msg + i, 1) == 0);
    xvc_cmd_t c;
    while ((c = xvc_next(&p)) != XVC_NONE) {
      if (c == XVC_GETINFO)
        seen[0]++;
      if (c == XVC_SETTCK) {
        seen[1]++;
        CHECK(p.settck_period_ns == 100);
      }
      if (c == XVC_SHIFT) {
        seen[2]++;
        CHECK(p.shift_bits == 11 && p.tms[0] == 0xff && p.tms[1] == 0x07 && p.tdi[0] == 1 && p.tdi[1] == 2);
      }
      if (c == XVC_ERROR)
        seen[3]++;
      xvc_consume(&p);
    }
  }
  CHECK(seen[0] == 1 && seen[1] == 1 && seen[2] == 1 && seen[3] == 0 && p.len == 0);
  /* coalesced in one buffer */
  xvc_init(&p);
  xvc_feed(&p, msg, len);
  int count = 0;
  while (xvc_next(&p) != XVC_NONE) {
    count++;
    xvc_consume(&p);
  }
  CHECK(count == 3);
  /* garbage */
  xvc_init(&p);
  xvc_feed(&p, (const uint8_t *)"bogus", 5);
  CHECK(xvc_next(&p) == XVC_ERROR);
  /* bit copying across byte boundaries */
  uint8_t src[4] = {0xA5, 0x3C, 0xFF, 0x01}, dst[4];
  xvc_copy_bits(dst, src, 4, 12);
  CHECK(dst[0] == 0xCA && dst[1] == 0x03);
  xvc_copy_bits(dst, src, 0, 25);
  CHECK(dst[0] == 0xA5 && dst[1] == 0x3C && dst[2] == 0xFF && dst[3] == 0x01);
}


/* ------------------------------------------------ raster frame assembler */
static uint8_t g_px[3 * 16];
static dp_raster_t mk_line(uint32_t frame, uint16_t line, uint16_t w, uint16_t vact, uint8_t flags)
{
  dp_raster_t r;
  memset(&r, 0, sizeof r);
  r.version = DP_RASTER_VERSION;
  r.frame = frame;
  r.line = line;
  r.v_active = vact;
  r.active_count = (flags & DP_RF_ACTIVE) ? w : 0;
  r.flags = flags;
  r.encoding = DP_ENC_RAW;
  for (int i = 0; i < 3 * w; i++)
    g_px[i] = (uint8_t)(line * 16 + i);
  r.payload = g_px;
  r.payload_bytes = (uint16_t)(3 * r.active_count);
  return r;
}

static void test_rasterframe(void)
{
  static rf_asm_t a;
  rf_frame_t f;
  dp_raster_t r;
  rf_init(&a);
  /* complete 4-line frame, out of order, plus a blanking line */
  int got = 0;
  uint16_t order[] = {0, 2, 1, 3};
  for (int i = 0; i < 4; i++) {
    r = mk_line(10, order[i], 5, 4, DP_RF_ACTIVE | (order[i] == 0 ? DP_RF_FIRST : 0));
    got += rf_feed(&a, &r, &f);
  }
  CHECK(got == 1 && f.complete && f.frame == 10 && f.width == 5 && f.height == 4);
  CHECK(f.lines_received == 4 && f.duplicates == 0);
  CHECK(f.rgb[3 * 5 * 2] == 2 * 16 && f.rgb[3 * 5 * 3 + 14] == 3 * 16 + 14);
  r = mk_line(10, 4, 5, 4, 0); /* blanking line of an emitted frame: late */
  CHECK(rf_feed(&a, &r, &f) == 0 && a.late == 1);

  /* missing line: newer frame arrives -> previous emitted incomplete */
  r = mk_line(11, 0, 5, 4, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 0);
  r = mk_line(11, 1, 5, 4, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 0);
  r = mk_line(11, 1, 5, 4, DP_RF_ACTIVE | DP_RF_DROPPED); /* duplicate */
  CHECK(rf_feed(&a, &r, &f) == 0);
  r = mk_line(11, 3, 5, 4, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 0);
  r = mk_line(12, 0, 5, 4, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 1);
  CHECK(!f.complete && f.frame == 11 && f.lines_received == 3 && f.duplicates == 1 && f.dropped_flag);
  CHECK(f.rgb[3 * 5 * 2] == 0); /* missing line 2 is black */
  /* the frame-12 packet was kept: finish frame 12 */
  for (uint16_t l = 1; l < 4; l++) {
    r = mk_line(12, l, 5, 4, DP_RF_ACTIVE);
    got = rf_feed(&a, &r, &f);
  }
  CHECK(got == 1 && f.complete && f.frame == 12);

  /* late packet of an older frame is ignored */
  r = mk_line(11, 2, 5, 4, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 0 && a.late == 2);

  /* width mismatch -> incomplete; frame number wrap 0xFFFFFFFF -> 0
   * (from 12, 0xFFFFFFFF would count as older, so restart the assembler) */
  rf_init(&a);
  r = mk_line(0xFFFFFFFFu, 0, 5, 2, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 0);
  r = mk_line(0xFFFFFFFFu, 1, 4, 2, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 1 && !f.complete && f.width_mismatch);
  r = mk_line(0, 0, 5, 2, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 0 && a.late == 0); /* 0 is newer than 0xFFFFFFFF */
  r = mk_line(0, 1, 5, 2, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 1 && f.complete && f.frame == 0);

  /* flush emits a partial frame once */
  r = mk_line(1, 0, 5, 3, DP_RF_ACTIVE);
  CHECK(rf_feed(&a, &r, &f) == 0);
  CHECK(rf_flush(&a, &f) == 1 && !f.complete && f.lines_received == 1);
  CHECK(rf_flush(&a, &f) == 0);
}

/* ------------------------------------------------------------ thumbnails */
static void test_thumbs(void)
{
  const vec_t *v;
  dp_thumb_t t;
  static uint8_t px[3 * DP_TH_MAX_W * 8];
  uint8_t req[8];
  v = vec("thumb_req");
  CHECK(v->len == 22 && dp_get16(v->data + 12) == DP_ETH_THUMB);
  CHECK(!memcmp(v->data, "\xff\xff\xff\xff\xff\xff", 6));
  CHECK(dp_encode_thumb_request(req, DP_TH_SCALE_QUARTER, 3) == 8 && !memcmp(req, v->data + 14, 8));
  CHECK(dp_decode_thumb(v->data + 14, v->len - 14, &t) == 0);
  CHECK(t.subtype == DP_TH_SUB_REQ && t.scale == 2 && t.div == 3);

  v = vec("thumb_raw");
  CHECK(dp_decode_thumb(v->data + 14, v->len - 14, &t) == 0);
  CHECK(t.subtype == DP_TH_SUB_LINES && t.machine == 3 && t.frame == 0x01020304 && t.row == 10);
  CHECK(t.nlines == 2 && t.width == 160 && t.height == 100 && t.scale == DP_TH_SCALE_QUARTER);
  CHECK(t.encoding == DP_ENC_RAW && t.payload_bytes == 960 && t.flags == DP_TH_FLAG_PRESENT);
  CHECK(dp_thumb_lines(&t, px, sizeof px) == 2);
  int ok = 1;
  for (int y = 0; y < 2; y++)
    for (int x = 0; x < 480; x++)
      ok &= px[480 * y + x] == ((x * 5 + y) & 255);
  CHECK(ok);
  CHECK(dp_decode_thumb(v->data + 14, v->len - 15, &t) < 0); /* truncated */

  v = vec("thumb_rle");
  CHECK(dp_decode_thumb(v->data + 14, v->len - 14, &t) == 0);
  CHECK(t.machine == 31 && t.row == 197 && t.nlines == 3 && t.width == 320 && t.height == 200);
  CHECK(t.encoding == DP_ENC_RLE24 && t.flags == (DP_TH_FLAG_PRESENT | DP_TH_FLAG_LAST));
  CHECK(t.payload_bytes == 3 * 4 * 3); /* 255 + 45 + 20 per line */
  CHECK(dp_thumb_lines(&t, px, sizeof px) == 3);
  CHECK(px[0] == 9 && px[3 * 299 + 2] == 7 && px[3 * 300] == 1 && px[3 * 960 - 1] == 3);
  CHECK(px[3 * 320 * 2 + 3 * 319 + 2] == 3);

  v = vec("thumb_nosrc");
  CHECK(dp_decode_thumb(v->data + 14, v->len - 14, &t) == 0);
  CHECK(t.subtype == DP_TH_SUB_NOSRC && t.machine == 12 && t.payload_bytes == 0);
  CHECK(dp_thumb_lines(&t, px, sizeof px) < 0);

  v = vec("thumb_badver");
  CHECK(dp_decode_thumb(v->data + 14, v->len - 14, &t) < 0);
}

/* ------------------------------------------------------------ PNG writer */
static uint32_t rd32(const uint8_t *p) { return dp_get32(p); }

/* Parse a PNG written by pw_png_encode: check signature, chunk CRCs, IHDR,
 * the stored-block zlib stream and its Adler-32; inflate into raw. Returns
 * the number of stored blocks, -1 on any error. */
static int png_check(const uint8_t *png, size_t n, unsigned w, unsigned h, uint8_t *raw, size_t rawcap)
{
  if (n < 8 || memcmp(png, "\x89PNG\r\n\x1a\n", 8))
    return -1;
  size_t pos = 8, rl = 0;
  int blocks = 0, seen_end = 0, chunk = 0;
  while (pos + 12 <= n) {
    uint32_t len = rd32(png + pos);
    const uint8_t *type = png + pos + 4, *d = png + pos + 8;
    if (pos + 12 + len > n || rd32(d + len) != pw_crc32(0, type, 4 + len))
      return -1;
    if (chunk == 0) {
      if (memcmp(type, "IHDR", 4) || len != 13 || rd32(d) != w || rd32(d + 4) != h || d[8] != 8 || d[9] != 2 ||
          d[10] || d[11] || d[12])
        return -1;
    } else if (!memcmp(type, "IDAT", 4)) {
      if (len < 6 || d[0] != 0x78 || ((d[0] << 8) | d[1]) % 31 || (d[1] & 0x20))
        return -1;
      size_t z = 2;
      int final = 0;
      while (!final) {
        if (z + 5 > len - 4 || (d[z] & 6))
          return -1; /* not a stored block */
        final = d[z] & 1;
        unsigned bl = d[z + 1] | d[z + 2] << 8, nl = d[z + 3] | d[z + 4] << 8;
        if ((bl ^ nl) != 0xFFFF || z + 5 + bl > len - 4 || rl + bl > rawcap)
          return -1;
        memcpy(raw + rl, d + z + 5, bl);
        rl += bl;
        z += 5 + bl;
        blocks++;
      }
      if (z + 4 != len || rd32(d + z) != pw_adler32(1, raw, rl))
        return -1;
    } else if (!memcmp(type, "IEND", 4)) {
      seen_end = len == 0 && pos + 12 == n;
    } else
      return -1;
    pos += 12 + len;
    chunk++;
  }
  if (!seen_end || rl != (size_t)h * (1 + 3 * w))
    return -1;
  return blocks;
}

static void test_png(const char *out_path)
{
  /* reference checksums */
  CHECK(pw_crc32(0, (const uint8_t *)"123456789", 9) == 0xCBF43926u);
  CHECK(pw_crc32(pw_crc32(0, (const uint8_t *)"1234", 4), (const uint8_t *)"56789", 5) == 0xCBF43926u);
  CHECK(pw_adler32(1, (const uint8_t *)"Wikipedia", 9) == 0x11E60398u);
  static uint8_t ones[100000];
  memset(ones, 0xFF, sizeof ones);
  /* long run: exercises the deferred modulo (zlib: adler32 of 100000 x 0xff) */
  uint32_t a = 1;
  for (size_t i = 0; i < sizeof ones; i++) {
    uint32_t lo = a & 0xFFFF, hi = a >> 16;
    lo = (lo + 0xFF) % 65521;
    hi = (hi + lo) % 65521;
    a = hi << 16 | lo;
  }
  CHECK(pw_adler32(1, ones, sizeof ones) == a);

  CHECK(pw_png_size(0, 5) == 0 && pw_png_size(5, 0) == 0);
  uint8_t tiny[3 * 3 * 2];
  for (int i = 0; i < 18; i++)
    tiny[i] = (uint8_t)(i * 13);
  uint8_t small[256], raw[64];
  size_t n = pw_png_encode(small, sizeof small, tiny, 3, 2);
  CHECK(n == pw_png_size(3, 2) && n == 8 + 25 + 12 + (2 + 5 + 20 + 4) + 12);
  CHECK(pw_png_encode(small, n - 1, tiny, 3, 2) == 0); /* too small */
  CHECK(png_check(small, n, 3, 2, raw, sizeof raw) == 1);
  CHECK(raw[0] == 0 && !memcmp(raw + 1, tiny, 9) && raw[10] == 0 && !memcmp(raw + 11, tiny + 9, 9));

  /* 720x480 (a real screenshot): 1038720 raw bytes = 16 stored blocks */
  enum { W = 720, H = 480 };
  static uint8_t img[3 * W * H], back[H * (1 + 3 * W)];
  for (int y = 0; y < H; y++)
    for (int x = 0; x < W; x++) {
      uint8_t *p = img + 3 * (W * y + x);
      p[0] = (uint8_t)x;
      p[1] = (uint8_t)y;
      p[2] = (uint8_t)(x ^ y);
    }
  size_t sz = pw_png_size(W, H);
  uint8_t *png = malloc(sz);
  CHECK(png && pw_png_encode(png, sz, img, W, H) == sz);
  int blocks = png ? png_check(png, sz, W, H, back, sizeof back) : -1;
  CHECK(blocks == (int)((sizeof back + 65534) / 65535));
  int ok = blocks > 0;
  for (int y = 0; ok && y < H; y++)
    ok = back[y * (1 + 3 * W)] == 0 && !memcmp(back + y * (1 + 3 * W) + 1, img + 3 * W * y, 3 * W);
  CHECK(ok);
  free(png);
  /* written file for the Python (zlib) cross-check in the Makefile */
  if (out_path)
    CHECK(pw_write_png(out_path, img, W, H) == 0);
}

/* ------------------------------------------------------------ screenshot targets */
static void test_screenshot_targets(void)
{
  /* console digits: box "1" is machine 0 ... box "0" is machine 9 */
  const char *digits = "1234567890";
  for (int m = 0; m < 10; m++) {
    CHECK(ss_digit_machine(digits[m]) == m);
    CHECK(ss_machine_digit(m) == digits[m]);
  }
  CHECK(ss_digit_machine('a') < 0 && ss_digit_machine('/') < 0 && ss_machine_digit(10) < 0);
  /* supervisor_core: m0 = id0(3:0) & '0', m1 = id1(3:0) & '1' */
  CHECK(ss_machine_of(0x00) == 0 && ss_machine_of(0x10) == 1);
  CHECK(ss_machine_of(0x03) == 6 && ss_machine_of(0x14) == 9 && ss_machine_of(0x1F) == 31);

  /* board A (DNA 1): dut0 0x00 (m0), dut1 0x10 (m1), video target dut1, locked;
   * board B (DNA 2): dut0 0x01 (m2), dut1 0x11 (m3), video target dut0, no video */
  ss_ep_t eps[4] = {
    {.addr = 1, .ep = 0, .dut_id = 0x00, .selected = 0x11, .dna = 1, .caps = 0x1F, .has_video = 1, .video_flags = 3},
    {.addr = 2, .ep = 1, .dut_id = 0x10, .selected = 0x11, .dna = 1, .caps = 0x1F, .has_video = 1, .video_flags = 3},
    {.addr = 3, .ep = 0, .dut_id = 0x01, .selected = 0x00, .dna = 2, .caps = 0x1F, .has_video = 1, .video_flags = 0},
    {.addr = 4, .ep = 1, .dut_id = 0x11, .selected = 0x00, .dna = 2, .caps = 0x1F, .has_video = 1, .video_flags = 0},
  };
  int cnt;
  CHECK(ss_find_machine(eps, 4, ss_digit_machine('2'), &cnt) == 1 && cnt == 1);
  CHECK(ss_find_machine(eps, 4, 3, &cnt) == 3 && cnt == 1);
  CHECK(ss_find_machine(eps, 4, 7, &cnt) == -1 && cnt == 0);
  CHECK(ss_find_addr(eps, 4, 3) == 2 && ss_find_addr(eps, 4, 9) == -1);
  CHECK(!ss_is_video_target(&eps[0]) && ss_is_video_target(&eps[1]));
  CHECK(ss_is_video_target(&eps[2]) && !ss_is_video_target(&eps[3]));
  CHECK(ss_sibling(eps, 4, 0) == 1 && ss_sibling(eps, 4, 3) == 2);
  CHECK(ss_can_capture(&eps[1]) && !ss_can_capture(&eps[2])); /* B: not locked */
  int idx[4];
  CHECK(ss_capturable(eps, 4, idx, 4) == 1 && idx[0] == 1);
  eps[2].video_flags = 3; /* B locks: two candidates */
  CHECK(ss_capturable(eps, 4, idx, 4) == 2 && idx[0] == 1 && idx[1] == 2);
  eps[1].caps = 0x0F; /* no HDMI capture capability */
  CHECK(ss_capturable(eps, 4, idx, 4) == 1 && idx[0] == 2);
  eps[2].selected = 0xF0; /* video target elsewhere / none */
  CHECK(ss_board_video_target(&eps[2]) == -1 && ss_capturable(eps, 4, idx, 4) == 0);
}

/* ------------------------------------------------------------ per-DUT config (0053) */
static void test_dutconf(void)
{
  static const char *text =
      "# comment\n"
      "; another\n"
      "[m65-r6]\n"
      "ip = 192.168.1.50\n"
      "dut = 1\n"
      "jtag = octopus\n"
      "tck_half = 12\n"
      "kbd_tck_half = 64\n"
      "relay = /dev/ttyACM0 3\n"
      "\n"
      "[nexys]   \n"
      "  jtag=usb\n"
      "usb_vid = 0x0403\n"
      "usb_pid = 6010\n"
      "usb_serial = FT12 AB\n"
      "ftdi_channel = 1\n"
      "usb_path = 1-2.3\n"
      "tty = /dev/ttyUSB3\n"
      "usb_freq = 6000000\n"
      "[other]\n"
      "ip = 192.168.1.50\n"
      "[wild]\n"
      "ip = 10.0.0.9\n";
  static dc_conf_t c;
  char err[1024];
  CHECK(dc_parse(text, &c, err, sizeof err) == 0);
  CHECK(err[0] == 0);
  CHECK(c.n == 4);
  const dc_dut_t *a = dc_find_name(&c, "m65-r6"), *b = dc_find_name(&c, "nexys");
  CHECK(a && b && !dc_find_name(&c, "nope"));
  if (!a || !b)
    return;
  CHECK(!strcmp(a->ip, "192.168.1.50") && a->dut == 1 && a->jtag == DC_JTAG_OCTOPUS);
  CHECK(a->tck_half == 12 && a->kbd_tck_half == 64 && a->ftdi_channel == -1);
  CHECK(!strcmp(a->relay_tty, "/dev/ttyACM0") && a->relay_ch == 3 && a->line == 3);
  CHECK(b->jtag == DC_JTAG_USB && b->usb_vid == 0x0403 && b->usb_pid == 0x6010);
  CHECK(!strcmp(b->usb_serial, "FT12 AB") && b->ftdi_channel == 1 && !strcmp(b->usb_path, "1-2.3"));
  CHECK(!strcmp(b->tty, "/dev/ttyUSB3") && b->usb_freq == 6000000 && b->dut == -1 && b->tck_half == 0);
  /* lookup by endpoint: exact index wins over a wildcard entry */
  CHECK(dc_find_ip(&c, "192.168.1.50", 1) == a);
  CHECK(dc_find_ip(&c, "192.168.1.50", 0) == dc_find_name(&c, "other"));
  CHECK(dc_find_ip(&c, "192.168.1.50", -1) == a);
  CHECK(dc_find_ip(&c, "10.0.0.9", 0) == dc_find_name(&c, "wild"));
  CHECK(dc_find_ip(&c, "10.0.0.8", -1) == NULL);

  /* problems are reported with line numbers, good keys still kept */
  CHECK(dc_parse("x = 1\n[a]\njtag = jtagger\ntck_half = 1\nfoo = bar\nnovalue\n[a]\n[b c]\n[ok]\nip = 1.2.3.4\n",
                 &c, err, sizeof err) == 7);
  CHECK(strstr(err, "1: key 'x' outside") && strstr(err, "3: bad value for jtag") &&
        strstr(err, "4: bad value for tck_half") && strstr(err, "5: unknown key 'foo'") &&
        strstr(err, "6: expected key") && strstr(err, "7: duplicate section") && strstr(err, "8: bad section"));
  CHECK(c.n == 2 && dc_find_name(&c, "ok") && !strcmp(dc_find_name(&c, "ok")->ip, "1.2.3.4"));
  CHECK(dc_parse("[r]\nrelay = /dev/ttyACM0\n", &c, NULL, 0) == 1);
  CHECK(dc_parse("", &c, NULL, 0) == 0 && c.n == 0);

  /* writer: replace in place, insert after the last key, new section, remove */
  char *t = dc_text_set(text, "m65-r6", "tck_half", "24");
  CHECK(t && strstr(t, "kbd_tck_half = 64\n") && strstr(t, "\ntck_half = 24\nkbd_tck_half"));
  CHECK(t && !strstr(t, "tck_half = 12"));
  char *t2 = dc_text_set(t, "nexys", "cable", "ft2232");
  CHECK(t2 && strstr(t2, "usb_freq = 6000000\ncable = ft2232\n[other]"));
  char *t3 = dc_text_set(t2, "new/0", "ip", "1.1.1.1");
  CHECK(t3 && strstr(t3, "ip = 10.0.0.9\n\n[new/0]\nip = 1.1.1.1\n"));
  char *t4 = dc_text_set(t3, "m65-r6", "relay", NULL);
  CHECK(t4 && !strstr(t4, "relay"));
  char *t5 = dc_text_set(t4, "m65-r6", "dut", "0"); /* section followed by a blank line */
  CHECK(t5 && strstr(t5, "kbd_tck_half = 64\n\n[nexys]") && strstr(t5, "dut = 0\njtag"));
  char *t6 = dc_text_set(t5, "wild", "dut", "1"); /* last section, file ends with a key */
  CHECK(t6 && strstr(t6, "[wild]\nip = 10.0.0.9\ndut = 1\n\n[new/0]"));
  CHECK(dc_parse(t6, &c, err, sizeof err) == 0 && c.n == 5);
  CHECK(dc_find_name(&c, "m65-r6")->tck_half == 24 && dc_find_name(&c, "m65-r6")->relay_ch == -1);
  CHECK(dc_find_name(&c, "m65-r6")->dut == 0 && dc_find_name(&c, "wild")->dut == 1);
  CHECK(!strcmp(dc_find_name(&c, "nexys")->cable, "ft2232") && strstr(t6, "# comment\n; another\n[m65-r6]"));
  char *t7 = dc_text_set("", "a", "k", "v");
  CHECK(t7 && !strcmp(t7, "[a]\nk = v\n"));
  char *t8 = dc_text_set("[a]\nk = v", "a", "k", "w"); /* no final newline */
  CHECK(t8 && !strcmp(t8, "[a]\nk = w\n"));
  char *t9 = dc_text_set("[a]\nk = v\n", "b", "k", NULL); /* remove from a missing section: no-op */
  CHECK(t9 && !strcmp(t9, "[a]\nk = v\n"));
  free(t), free(t2), free(t3), free(t4), free(t5), free(t6), free(t7), free(t8), free(t9);

  char nm[64];
  dc_auto_name(nm, sizeof nm, "10.1.2.3", 1);
  CHECK(!strcmp(nm, "10.1.2.3/1"));
  dc_auto_name(nm, sizeof nm, "10.1.2.3", -1);
  CHECK(!strcmp(nm, "10.1.2.3"));
  CHECK(!strcmp(dc_default_cable(0x0403, 0x6010), "ft2232") && dc_default_cable(0x2a19, 0x1009) == NULL);
}

/* file round trip in a scratch directory (created by test_dirs) */
static char g_tmp[256];

static int rm_cb(const char *p, const struct stat *sb, int flag, struct FTW *f)
{
  (void)sb, (void)flag, (void)f;
  return remove(p);
}

static void test_dutconf_file(void)
{
  char path[512];
  snprintf(path, sizeof path, "%s/cfg/sub/duts.conf", g_tmp);
  static dc_conf_t c;
  int missing = 0;
  CHECK(dc_load(path, &c, NULL, 0, &missing) == 0 && missing && c.n == 0);
  const char *s[3] = {"a", "a", "10.0.0.1/0"}, *k[3] = {"ip", "tck_half", "tck_half"},
             *v[3] = {"10.0.0.1", "8", "16"};
  CHECK(dc_update_file(path, 3, s, k, v) == 0);
  CHECK(dc_load(path, &c, NULL, 0, &missing) == 0 && !missing && c.n == 2);
  CHECK(dc_find_name(&c, "a") && dc_find_name(&c, "a")->tck_half == 8);
  CHECK(dc_find_name(&c, "10.0.0.1/0") && dc_find_name(&c, "10.0.0.1/0")->tck_half == 16);
  const char *k2[1] = {"tck_half"}, *v2[1] = {"10"};
  CHECK(dc_update_file(path, 1, s, k2, v2) == 0);
  CHECK(dc_load(path, &c, NULL, 0, &missing) == 0 && dc_find_name(&c, "a")->tck_half == 10);
  FILE *f = fopen(path, "r");
  char buf[512] = "";
  if (f) {
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    buf[n] = 0;
    fclose(f);
  }
  CHECK(!strncmp(buf, "# dutctl per-DUT configuration", 30) && strstr(buf, "[a]\nip = 10.0.0.1\ntck_half = 10\n"));
}

/* ------------------------------------------------------------ JTAG speed probe (0054) */
/* A JTAG chain simulator: IEEE 1149.1 TAP per device, IR all ones = BYPASS,
 * IR after reset = IDCODE (or BYPASS for devices without one). */
enum { S_TLR, S_RTI, S_SDR, S_CDR, S_SHDR, S_E1DR, S_PDR, S_E2DR, S_UDR, S_SIR, S_CIR, S_SHIR, S_E1IR, S_PIR,
       S_E2IR, S_UIR };
static const uint8_t tap_next[16][2] = {
  [S_TLR] = {S_RTI, S_TLR},   [S_RTI] = {S_RTI, S_SDR},   [S_SDR] = {S_CDR, S_SIR},  [S_CDR] = {S_SHDR, S_E1DR},
  [S_SHDR] = {S_SHDR, S_E1DR}, [S_E1DR] = {S_PDR, S_UDR}, [S_PDR] = {S_PDR, S_E2DR}, [S_E2DR] = {S_SHDR, S_UDR},
  [S_UDR] = {S_RTI, S_SDR},   [S_SIR] = {S_CIR, S_TLR},   [S_CIR] = {S_SHIR, S_E1IR}, [S_SHIR] = {S_SHIR, S_E1IR},
  [S_E1IR] = {S_PIR, S_UIR},  [S_PIR] = {S_PIR, S_E2IR},  [S_E2IR] = {S_SHIR, S_UIR}, [S_UIR] = {S_RTI, S_SDR},
};
typedef struct {
  int irlen;
  uint32_t idcode; /* 0 = no IDCODE register */
  uint32_t idcode_ir;
  uint32_t ir;
  uint64_t sr;
  int srlen;
} sim_dev_t;

static void sim_reset_ir(sim_dev_t *d, int n)
{
  for (int k = 0; k < n; k++)
    d[k].ir = d[k].idcode ? d[k].idcode_ir : (1u << d[k].irlen) - 1;
}

static void sim_run(sim_dev_t *d, int n, const js_probe_t *p, uint8_t *tdo, int delay)
{
  int st = S_TLR;
  static uint8_t raw[JS_MAX_BITS / 8];
  memset(raw, 0, sizeof raw);
  sim_reset_ir(d, n);
  for (uint32_t i = 0; i < p->bits; i++) {
    int tms = (p->tms[i / 8] >> (i % 8)) & 1, tdi = (p->tdi[i / 8] >> (i % 8)) & 1;
    int out = 1; /* TDO tri-stated outside the shift states: pull-up */
    if (st == S_SHDR || st == S_SHIR)
      out = (int)(d[n - 1].sr & 1);
    if (out)
      raw[i / 8] |= (uint8_t)(1u << (i % 8));
    if (st == S_CDR || st == S_CIR)
      for (int k = 0; k < n; k++) {
        int idr = st == S_CDR && d[k].idcode && d[k].ir == d[k].idcode_ir;
        d[k].srlen = st == S_CIR ? d[k].irlen : idr ? 32 : 1;
        d[k].sr = st == S_CIR ? 1 : idr ? d[k].idcode : 0;
      }
    if (st == S_SHDR || st == S_SHIR) {
      int in = tdi;
      for (int k = 0; k < n; k++) {
        int o = (int)(d[k].sr & 1);
        d[k].sr = (d[k].sr >> 1) | ((uint64_t)in << (d[k].srlen - 1));
        in = o;
      }
    }
    st = tap_next[st][tms];
    if (st == S_UIR)
      for (int k = 0; k < n; k++)
        d[k].ir = (uint32_t)d[k].sr;
    if (st == S_TLR)
      sim_reset_ir(d, n);
  }
  /* delay > 0: TDO sampled `delay` pulses late (a long cable at too high a TCK) */
  memset(tdo, 0, JS_MAX_BITS / 8);
  for (uint32_t i = 0; i < p->bits; i++) {
    int b = i >= (uint32_t)delay ? (raw[(i - delay) / 8] >> ((i - delay) % 8)) & 1 : 1;
    if (b)
      tdo[i / 8] |= (uint8_t)(1u << (i % 8));
  }
}

static void test_jtagspeed(void)
{
  static js_probe_t p, p2;
  static uint8_t ref[JS_MAX_BITS / 8], tdo[JS_MAX_BITS / 8];
  js_build(&p, 1);
  CHECK(p.bits <= JS_MAX_BITS && p.bits == 9 + JS_ID_BITS + 5 + JS_IR_BITS + 4 + p.dr_bits + 6);
  CHECK(p.id_at == 9 && p.dr_at == 9 + JS_ID_BITS + 5 + JS_IR_BITS + 4);
  js_build(&p2, 2);
  CHECK(memcmp(p.tdi, p2.tdi, sizeof p.tdi) != 0); /* seed changes the pattern */
  CHECK(!memcmp(p.tms, p2.tms, sizeof p.tms));    /* but not the TAP walk */

  /* the keyboard CPLD alone (XC2C64A-like, 8-bit IR) */
  sim_dev_t one[1] = {{.irlen = 8, .idcode = 0x012ba043, .idcode_ir = 0x01}};
  sim_run(one, 1, &p, ref, 0);
  CHECK(js_chain_len(&p, ref, JS_MAX_CHAIN) == 1);
  uint32_t ids[8];
  CHECK(js_idcodes(&p, ref, ids, 8) == 1 && ids[0] == 0x012ba043);
  js_errs_t e;
  sim_run(one, 1, &p2, tdo, 0);
  CHECK(js_check(&p2, tdo, ref, 1, &e) == 0);

  /* a chain: FPGA (IDCODE), a bypass-only device, a second IDCODE device */
  sim_dev_t three[3] = {{.irlen = 6, .idcode = 0x0362c093, .idcode_ir = 0x09},
                        {.irlen = 4, .idcode = 0},
                        {.irlen = 8, .idcode = 0x012ba043, .idcode_ir = 0x01}};
  sim_run(three, 3, &p, ref, 0);
  CHECK(js_chain_len(&p, ref, JS_MAX_CHAIN) == 3);
  int nid = js_idcodes(&p, ref, ids, 8); /* nearest TDO first */
  CHECK(nid == 3 && ids[0] == 0x012ba043 && ids[1] == 0 && ids[2] == 0x0362c093);
  sim_run(three, 3, &p2, tdo, 0);
  CHECK(js_check(&p2, tdo, ref, 3, &e) == 0);
  /* TDO one pulse late: the IDCODE window and the BYPASS shift both break */
  sim_run(three, 3, &p2, tdo, 1);
  CHECK(js_check(&p2, tdo, ref, 3, &e) > 0 && e.id_err > 0 && e.rand_err > 0);
  CHECK(e.zero_err <= 1 && e.one_err <= 1); /* constant runs only break at their edges */
  /* single flipped bits are found in each segment */
  sim_run(three, 3, &p2, tdo, 0);
  uint32_t flips[4] = {p2.id_at + 40, p2.dr_at + 3 + 100, p2.dr_at + 3 + JS_RAND_BITS + 7,
                       p2.dr_at + 3 + JS_RAND_BITS + JS_FILL_BITS + 9};
  for (int f = 0; f < 4; f++)
    tdo[flips[f] / 8] ^= (uint8_t)(1u << (flips[f] % 8));
  CHECK(js_check(&p2, tdo, ref, 3, &e) == 4 && e.id_err == 1 && e.rand_err == 1 && e.zero_err == 1 &&
        e.one_err == 1);
  /* TDO stuck: no chain length */
  memset(tdo, 0xFF, sizeof tdo);
  CHECK(js_chain_len(&p2, tdo, JS_MAX_CHAIN) < 0 && js_idcodes(&p2, tdo, ids, 8) == 0);
  memset(tdo, 0, sizeof tdo);
  CHECK(js_chain_len(&p2, tdo, JS_MAX_CHAIN) < 0);
  /* TDO wired to TDI: chain length 0 */
  memcpy(tdo, p2.tdi, sizeof tdo);
  CHECK(js_chain_len(&p2, tdo, JS_MAX_CHAIN) == 0);

  /* recommendation */
  CHECK(js_nsteps >= 10 && js_steps[0] == 50 && js_steps[js_nsteps - 1] == 2);
  CHECK(js_freq_hz(6) > 10.41e6 && js_freq_hz(6) < 10.42e6 && js_freq_hz(2) == 31.25e6);
  int pass[32], fm;
  for (int i = 0; i < js_nsteps; i++)
    pass[i] = 1;
  CHECK(js_recommend(js_steps, pass, js_nsteps, &fm) == 4 && fm == js_nsteps - 1); /* all ok: 2 -> 4 */
  for (int i = 0; i < js_nsteps; i++)
    pass[i] = js_steps[i] >= 6; /* 6 is the fastest that passes */
  CHECK(js_recommend(js_steps, pass, js_nsteps, &fm) == 12 && js_steps[fm] == 6);
  for (int i = 0; i < js_nsteps; i++)
    pass[i] = js_steps[i] >= 7; /* 2 * 7 = 14: next slower step on the list is 16 */
  CHECK(js_recommend(js_steps, pass, js_nsteps, &fm) == 16 && js_steps[fm] == 7);
  pass[3] = 0; /* a failure on the way (24) caps f_max even if faster steps pass */
  for (int i = 4; i < js_nsteps; i++)
    pass[i] = 1;
  CHECK(js_recommend(js_steps, pass, js_nsteps, &fm) == 64 && js_steps[fm] == 32);
  pass[0] = 0;
  CHECK(js_recommend(js_steps, pass, js_nsteps, &fm) == 0 && fm == -1);
  pass[0] = 1, pass[1] = 0;
  CHECK(js_recommend(js_steps, pass, js_nsteps, &fm) == 100 && fm == 0);
}

/* ------------------------------------------------------------ USB adaptor discovery (0053) */
static void mkf(const char *dir, const char *name, const char *val)
{
  char p[600];
  snprintf(p, sizeof p, "%s/%s", dir, name);
  FILE *f = fopen(p, "w");
  if (f) {
    fprintf(f, "%s\n", val);
    fclose(f);
  }
}

/* one USB device dir and its interface dirs (driver symlink, ttyUSB child) */
static void mkdev(const char *root, const char *path, const char *vid, const char *pid, const char *serial,
                  const char *mfr, const char *prod, int nif, const char *const *ttys)
{
  char d[600];
  snprintf(d, sizeof d, "%s/%s", root, path);
  mkdir(d, 0755);
  mkf(d, "idVendor", vid);
  mkf(d, "idProduct", pid);
  if (serial)
    mkf(d, "serial", serial);
  mkf(d, "manufacturer", mfr);
  mkf(d, "product", prod);
  mkf(d, "busnum", "1");
  mkf(d, "devnum", "7");
  for (int i = 0; i < nif; i++) {
    char ifd[700], num[8], t[800];
    snprintf(ifd, sizeof ifd, "%s/%s:1.%d", root, path, i);
    mkdir(ifd, 0755);
    snprintf(num, sizeof num, "%02x", i);
    mkf(ifd, "bInterfaceNumber", num);
    if (ttys && ttys[i]) {
      snprintf(t, sizeof t, "%s/%s", ifd, ttys[i]);
      mkdir(t, 0755);
      snprintf(t, sizeof t, "%s/driver", ifd);
      if (symlink("../../../bus/usb-serial/drivers/ftdi_sio", t) < 0)
        perror("symlink");
    }
  }
}

static void test_jtagdisc(void)
{
  const char *cable;
  CHECK(jd_classify(0x2a19, 0x1009, "Numato", "Mimas", &cable) == NULL); /* the supervisors */
  CHECK(jd_classify(0x1d6b, 0x0002, "Linux", "hub", &cable) == NULL);
  CHECK(!strcmp(jd_classify(0x0403, 0x6010, "FTDI", "Dual RS232-HS", &cable), "FTDI FT2232H") &&
        !strcmp(cable, "ft2232"));
  CHECK(strstr(jd_classify(0x0403, 0x6010, "Trenz Electronic", "TE0790 JTAG", &cable), "TE0790") &&
        !strcmp(cable, "ft2232"));
  CHECK(strstr(jd_classify(0x0403, 0x6014, "Digilent", "Digilent USB Device", &cable), "HS2") &&
        !strcmp(cable, "digilent_hs2"));
  CHECK(jd_classify(0x1443, 0x0007, "Digilent", "", &cable) && cable == NULL);
  CHECK(jd_classify(0x0403, 0x6015, "FTDI", "FT-X", &cable) == NULL);

  char root[300];
  snprintf(root, sizeof root, "%s/sys", g_tmp);
  mkdir(root, 0755);
  static const char *const te[] = {"ttyUSB4", "ttyUSB5"}, *const mim[] = {"ttyUSB0", NULL},
                           *const ard[] = {"ttyUSB9"};
  mkdev(root, "usb1", "1d6b", "0002", "0000:00:14.0", "Linux", "xHCI Host Controller", 0, NULL);
  mkdev(root, "1-2.10", "0403", "6010", "251633000123", "Trenz Electronic", "TE0790", 2, te);
  mkdev(root, "1-2.9", "0403", "6014", "210249A1B2C3", "Digilent", "Digilent USB Device", 1, NULL);
  mkdev(root, "1-3", "2a19", "1009", "A1B2", "Numato", "Mimas A7", 2, mim);
  mkdev(root, "1-4", "0403", "6010", NULL, "FTDI", "Dual RS232-HS", 2, NULL);
  mkdev(root, "1-5", "0403", "6001", "A9XYZ", "FTDI", "FT232R USB UART", 1, ard);
  static jd_adaptor_t a[8];
  int n = jd_scan(root, a, 8);
  CHECK(n == 4);
  if (n != 4)
    return;
  /* sorted by port path, version order (1-2.9 before 1-2.10) */
  CHECK(!strcmp(a[0].path, "1-2.9") && !strcmp(a[1].path, "1-2.10") && !strcmp(a[2].path, "1-4") &&
        !strcmp(a[3].path, "1-5"));
  CHECK(a[1].vid == 0x0403 && a[1].pid == 0x6010 && !strcmp(a[1].serial, "251633000123"));
  CHECK(strstr(a[1].kind, "TE0790") && a[1].nif == 2 && a[1].ifs[0].num == 0 && a[1].ifs[1].num == 1);
  CHECK(!strcmp(a[1].ifs[0].tty, "ttyUSB4") && !strcmp(jd_tty(&a[1], 1), "ttyUSB5") &&
        !strcmp(a[1].ifs[1].driver, "ftdi_sio"));
  CHECK(!strcmp(a[0].cable, "digilent_hs2") && a[0].nif == 1 && a[0].ifs[0].tty[0] == 0 &&
        a[0].ifs[0].driver[0] == 0);
  CHECK(a[2].serial[0] == 0 && a[2].busnum == 1 && a[2].devnum == 7 && !strcmp(jd_tty(&a[2], 0), ""));
  CHECK(!strcmp(a[3].cable, "ft232RL") && !strcmp(jd_tty(&a[3], 0), "ttyUSB9"));
  CHECK(jd_scan("/nonexistent/sysfs", a, 8) < 0);
  CHECK(jd_scan(root, a, 2) == 2);

  /* openFPGALoader --detect output */
  uint32_t ids[8];
  const char *det = "empty\nJtag frequency : requested 1.00MHz  -> real 1.00MHz\nindex 0:\n"
                    "\tidcode 0x362c093\n\tmanufacturer xilinx\n\tfamily artix a7 50t\nindex 1:\n"
                    "\tidcode 0x12ba043\n";
  CHECK(jd_parse_detect(det, ids, 8) == 2 && ids[0] == 0x0362c093 && ids[1] == 0x012ba043);
  CHECK(jd_parse_detect("index 0:\n\tidcode 0xffffffff\n", ids, 8) == 0);
  CHECK(jd_parse_detect("JTAG init failed with: no device found\n", ids, 8) == 0);
  CHECK(jd_parse_detect(det, ids, 1) == 1);

  /* command lines */
  jd_cmd_t c;
  char line[1024];
  CHECK(jd_ofl_cmd(&c, "/opt/ofl", "ft2232", 0x0403, 0x6010, "2516", "001:007", 0, 6000000, "detect", 0) == 0);
  jd_cmd_str(&c, line, sizeof line);
  CHECK(!strcmp(line, "/opt/ofl -c ft2232 --ftdi-serial 2516 --ftdi-channel 0 --freq 6000000 --detect"));
  CHECK(c.argc == 10 && c.argv[10] == NULL && !strcmp(c.argv[4], "2516"));
  CHECK(jd_ofl_cmd(&c, "ofl", "ft2232", 0x0403, 0x6010, "", "001:007", -1, 0, "detect", 0) == 0);
  jd_cmd_str(&c, line, sizeof line);
  CHECK(!strcmp(line, "ofl -c ft2232 --busdev-num 001:007 --detect"));
  CHECK(jd_ofl_cmd(&c, "ofl", "ft232", 0x0403, 0x6014, NULL, NULL, 1, 0, "xvc", 2543) == 0);
  jd_cmd_str(&c, line, sizeof line);
  CHECK(!strcmp(line, "ofl -c ft232 --vid 0x0403 --pid 0x6014 --ftdi-channel 1 --xvc --port 2543"));
  CHECK(jd_ofl_cmd(&c, "ofl", NULL, 0x1443, 7, "x", NULL, 0, 0, "detect", 0) < 0);
  CHECK(jd_ofl_cmd(&c, "my ofl", "ft2232", 0, 0, "it's", NULL, -1, 0, "detect", 0) == 0);
  jd_cmd_str(&c, line, sizeof line);
  CHECK(!strcmp(line, "'my ofl' -c ft2232 --ftdi-serial 'it'\\''s' --detect"));
}

static void test_dirs(void)
{
  const char *t = getenv("TMPDIR");
  snprintf(g_tmp, sizeof g_tmp, "%s/dutctl-test-XXXXXX", t && *t ? t : "/tmp");
  if (!mkdtemp(g_tmp)) {
    perror("mkdtemp");
    exit(1);
  }
  test_dutconf_file();
  test_jtagdisc();
  nftw(g_tmp, rm_cb, 16, FTW_DEPTH | FTW_PHYS);
}

int main(int argc, char **argv)
{
  load_vectors(argc > 1 ? argv[1] : "vectors.txt");
  test_encoders();
  test_decoders();
  test_uart_merge();
  test_xvc();
  test_rasterframe();
  test_thumbs();
  test_png(argc > 2 ? argv[2] : NULL);
  test_screenshot_targets();
  test_dutconf();
  test_jtagspeed();
  test_dirs();
  printf("dutctl tests: %d checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
