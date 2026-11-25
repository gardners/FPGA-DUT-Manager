/* Unit tests for dutctl: protocol vectors, UART merging, XVC parsing. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dutproto.h"
#include "uartstream.h"
#include "xvc.h"
#include "rasterframe.h"

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
  CHECK(hb.console_screen == 2);
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

int main(int argc, char **argv)
{
  load_vectors(argc > 1 ? argv[1] : "vectors.txt");
  test_encoders();
  test_decoders();
  test_uart_merge();
  test_xvc();
  test_rasterframe();
  printf("dutctl tests: %d checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
