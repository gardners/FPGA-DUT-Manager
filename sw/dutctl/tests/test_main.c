/* Unit tests for dutctl: protocol vectors, UART merging, XVC parsing. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dutproto.h"
#include "uartstream.h"
#include "xvc.h"

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
  uint8_t data[DP_MAX_PACKET];
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
  static char hex[4608];
  while (nvecs < 32 && fscanf(f, "%31s %4500s", vecs[nvecs].name, hex) == 2) {
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

int main(int argc, char **argv)
{
  load_vectors(argc > 1 ? argv[1] : "vectors.txt");
  test_encoders();
  test_decoders();
  test_uart_merge();
  test_xvc();
  printf("dutctl tests: %d checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
