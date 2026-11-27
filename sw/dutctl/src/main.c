/* dutctl - command line control of Mimas A7 DUT supervisors.
 *
 *   dutctl listen [-t SECONDS] [-n COUNT] [--kv]
 *                                              decode heartbeats (--kv: key=value)
 *   dutctl mgmt IP KEY [HEXVALUE] [--cmd-id N] [--dut N]
 *                                              raw MGMT_SET, prints the ack
 *   dutctl set IP NAME VALUE                   management (see `dutctl help`)
 *   dutctl kbd IP [KEY ...]                    hold keys (none = all up)
 *   dutctl uart IP [--baud N] [--clear] [--from-start]
 *                                              interactive UART bridge
 *   dutctl jtag-idcode IP [--kbd]              read JTAG IDCODE over UDP
 *   dutctl xvc IP [--port 2542] [--kbd]        XVC 1.0 server for Vivado
 *                                              (--kbd: the physical keyboard's
 *                                              CPLD instead of the DUT, ADR 0014)
 *   dutctl relay TTY COMMAND...                Arduino relay controller
 *   dutctl thumbs IFACE [--request] [--force IP] thumbnail relay -> PPM (AF_PACKET)
 *   dutctl screenshot [TARGET] [-o FILE]        one frame -> PNG/PPM (alias -S)
 *
 * LGPL-2.1-or-later. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <arpa/inet.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "dutproto.h"
#include "pngwrite.h"
#include "rasterframe.h"
#include "screenshot.h"
#include "uartstream.h"
#include "xvc.h"

static volatile sig_atomic_t g_stop;
static void on_sig(int s) { (void)s; g_stop = 1; }

static double now_s(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void die(const char *msg)
{
  perror(msg);
  exit(1);
}

/* ------------------------------------------------------------- UDP helpers */
static int udp_bind(uint16_t port)
{
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0)
    die("socket");
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one);
  setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, sizeof one);
  int rcv = 4 << 20;
  setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcv, sizeof rcv);
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = INADDR_ANY};
  if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0)
    die("bind");
  return fd;
}

static struct sockaddr_in parse_target(const char *ip, uint16_t port)
{
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port)};
  if (inet_pton(AF_INET, ip, &a.sin_addr) != 1) {
    fprintf(stderr, "bad IPv4 address: %s\n", ip);
    exit(2);
  }
  return a;
}

/* Receive one datagram with timeout; returns length or -1. Optionally
 * filter by source address and packet type. */
static int udp_recv(int fd, uint8_t *buf, size_t cap, int timeout_ms, const struct sockaddr_in *from_filter,
                    int type_filter, dp_hdr_t *h, struct sockaddr_in *from)
{
  double end = now_s() + timeout_ms / 1000.0;
  for (;;) {
    int left = (int)((end - now_s()) * 1000);
    if (left < 0)
      return -1;
    struct pollfd p = {.fd = fd, .events = POLLIN};
    if (poll(&p, 1, left) <= 0)
      return -1;
    struct sockaddr_in src;
    socklen_t sl = sizeof src;
    ssize_t n = recvfrom(fd, buf, cap, 0, (struct sockaddr *)&src, &sl);
    if (n < 0)
      continue;
    if (from_filter && src.sin_addr.s_addr != from_filter->sin_addr.s_addr)
      continue;
    dp_hdr_t hh;
    if (dp_parse_hdr(buf, (size_t)n, &hh) < 0)
      continue;
    if (type_filter >= 0 && hh.type != type_filter)
      continue;
    if (h)
      *h = hh;
    if (from)
      *from = src;
    return (int)n;
  }
}

/* ------------------------------------------------------------- management */
/* MGMT_SET with retries; prints the ack unless quiet. Returns 0 when the
 * key was applied (ok / duplicate), 1 otherwise. */
static int mgmt_set_q(const char *ip, uint16_t key, const uint8_t *val, uint16_t vlen, int quiet)
{
  int fd = udp_bind(0);
  struct sockaddr_in t = parse_target(ip, DP_PORT_MGMT);
  uint8_t pkt[64], rx[DP_MAX_PACKET];
  /* seed once: consecutive sets in one process need different cmd_ids (a
   * repeat of the last applied id is acked as a duplicate, not applied) */
  static int seeded;
  static uint16_t next_cmd;
  if (!seeded) {
    srand((unsigned)(time(NULL) ^ getpid()));
    next_cmd = (uint16_t)rand();
    seeded = 1;
  }
  uint16_t cmd = next_cmd++;
  size_t n = dp_encode_mgmt_set(pkt, DP_DUT_ANY, cmd, key, val, vlen);
  for (int attempt = 0; attempt < 5; attempt++) {
    sendto(fd, pkt, n, 0, (struct sockaddr *)&t, sizeof t);
    dp_hdr_t h;
    int r = udp_recv(fd, rx, sizeof rx, 200, &t, DP_T_MGMT_ACK, &h, NULL);
    if (r > 0) {
      dp_ack_t a;
      if (dp_decode_ack(rx + DP_HDR_LEN, h.length, &a) == 0 && a.cmd_id == cmd) {
        static const char *const st[] = {"ok", "bad key", "bad length", "bad value", "duplicate"};
        int good = a.status == DP_ACK_OK || a.status == DP_ACK_DUPLICATE;
        if (!quiet || !good)
          fprintf(quiet ? stderr : stdout, "dut%d key 0x%04x: %s (config generation %u)\n", h.dut, a.key,
                  a.status < 5 ? st[a.status] : "?", a.cfg_gen);
        close(fd);
        return good ? 0 : 1;
      }
    }
  }
  fprintf(stderr, "no MGMT_ACK from %s (key 0x%04x)\n", ip, key);
  close(fd);
  return 1;
}

static int mgmt_set(const char *ip, uint16_t key, const uint8_t *val, uint16_t vlen)
{
  return mgmt_set_q(ip, key, val, vlen, 0);
}

static int parse_mac(const char *s, uint8_t m[6])
{
  unsigned v[6];
  if (sscanf(s, "%x:%x:%x:%x:%x:%x", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6)
    return -1;
  for (int i = 0; i < 6; i++)
    m[i] = (uint8_t)v[i];
  return 0;
}

static int cmd_set(int argc, char **argv)
{
  if (argc < 3) {
    fprintf(stderr,
            "usage: dutctl set IP NAME VALUE\n"
            "  names: mac ip dhcp dest-ip dest-mac baud uart-fast uart-snap uart-period-us\n"
            "         kbd-policy kbd-override kbd-target video-target coupled capture\n"
            "         hb-period-ms out-policy (0 auto, 1 on, 2 off)\n"
            "         kbd-leds (physical keyboard LEDs: 0 status colour, 1 DUT's, 2 host)\n"
            "         console-screen (0 auto incl. passthrough, 1 editable, 2 no video, 3 select)\n"
            "         kbd-jtag (keyboard CPLD JTAG: 0 auto, 1 on, 2 off, 3 on with JTAGEN low)\n"
            "         power-ctl (shield power outputs CTRL0..7 bitmask, e.g. 0x05)\n"
            "         kbd-led-rgb RRGGBB,RRGGBB,RRGGBB,RRGGBB (LED0..3 for kbd-leds 2;\n"
            "                     LED0/1 = drive LED, LED2/3 = power LED)\n");
    return 2;
  }
  const char *ip = argv[0], *name = argv[1], *val = argv[2];
  uint8_t v[18];
  unsigned long u = strtoul(val, NULL, 0);
  struct {
    const char *name;
    uint16_t key;
    int len; /* 1, 2, 4 numeric; 6 mac; -4 ip */
  } tab[] = {
    {"mac", DP_K_MAC, 6}, {"ip", DP_K_IP, -4}, {"dhcp", DP_K_DHCP_EN, 1}, {"dest-ip", DP_K_DEST_IP, -4},
    {"dest-mac", DP_K_DEST_MAC, 6}, {"baud", DP_K_UART_BAUD, 4}, {"uart-fast", DP_K_UART_FAST, 1},
    {"uart-snap", DP_K_UART_SNAP_EN, 1}, {"uart-period-us", DP_K_UART_PERIOD, 2},
    {"kbd-policy", DP_K_KBD_POLICY, 1}, {"kbd-override", DP_K_KBD_OVERRIDE, 1},
    {"kbd-target", DP_K_KBD_TARGET, 1}, {"video-target", DP_K_VID_TARGET, 1},
    {"coupled", DP_K_COUPLED, 1}, {"capture", DP_K_CAPTURE_EN, 1},
    {"hb-period-ms", DP_K_HB_PERIOD, 2}, {"out-policy", DP_K_OUT_POLICY, 1},
    {"kbd-leds", DP_K_PK_LED_MODE, 1}, {"console-screen", DP_K_CON_SCREEN, 1},
    {"kbd-jtag", DP_K_PK_JTAG, 1}, {"power-ctl", DP_K_PWR_CTL, 1},
  };
  if (!strcmp(name, "kbd-led-rgb")) {
    unsigned c[4];
    if (sscanf(val, "%6x,%6x,%6x,%6x", &c[0], &c[1], &c[2], &c[3]) != 4)
      return fprintf(stderr, "kbd-led-rgb: expected RRGGBB,RRGGBB,RRGGBB,RRGGBB\n"), 2;
    for (int l = 0; l < 4; l++) {
      v[3 * l] = (uint8_t)(c[l] >> 16);     /* R */
      v[3 * l + 1] = (uint8_t)(c[l] >> 8);  /* G */
      v[3 * l + 2] = (uint8_t)c[l];         /* B */
    }
    return mgmt_set(ip, DP_K_PK_LED_HOST, v, 12);
  }
  for (size_t i = 0; i < sizeof tab / sizeof tab[0]; i++) {
    if (strcmp(name, tab[i].name))
      continue;
    int len = tab[i].len;
    if (tab[i].key == DP_K_UART_BAUD)
      u = dp_baud_nco((double)u);
    if (len == 6) {
      if (parse_mac(val, v) < 0)
        return fprintf(stderr, "bad MAC\n"), 2;
    } else if (len == -4) {
      if (inet_pton(AF_INET, val, v) != 1)
        return fprintf(stderr, "bad IP\n"), 2;
      len = 4;
    } else {
      for (int b = 0; b < len; b++)
        v[b] = (uint8_t)(u >> (8 * (len - 1 - b)));
    }
    return mgmt_set(ip, tab[i].key, v, (uint16_t)len);
  }
  fprintf(stderr, "unknown setting %s\n", name);
  return 2;
}

/* ------------------------------------------------------------- keyboard */
/* Raw MGMT_SET: any key, any value (hex, possibly empty), chosen cmd_id
 * and dut index; prints the ack as key=value. Used by scripts to check
 * rejections (bad key / length / value) and duplicate detection.
 * Exit 0 when an ack arrived (whatever its status), 1 when none did. */
static int cmd_mgmt(int argc, char **argv)
{
  if (argc < 2)
    return fprintf(stderr, "usage: dutctl mgmt IP KEY [HEXVALUE] [--cmd-id N] [--dut N] [--timeout-ms N]\n"
                           "  prints: dut=D key=K cmd_id=C status=S (0 ok 1 bad-key 2 bad-length\n"
                           "  3 bad-value 4 duplicate) cfg_gen=G, or 'noack' (exit 1)\n"), 2;
  const char *ip = argv[0];
  uint16_t key = (uint16_t)strtoul(argv[1], NULL, 0);
  const char *hex = "";
  long cmd = -1, dut = DP_DUT_ANY, tmo = 1000;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "--cmd-id") && i + 1 < argc) cmd = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--dut") && i + 1 < argc) dut = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--timeout-ms") && i + 1 < argc) tmo = strtol(argv[++i], NULL, 0);
    else if (i == 2) hex = argv[i];
    else return fprintf(stderr, "dutctl mgmt: unexpected %s\n", argv[i]), 2;
  }
  uint8_t v[256];
  size_t hl = strlen(hex);
  if (hl % 2 || hl / 2 > sizeof v)
    return fprintf(stderr, "dutctl mgmt: HEXVALUE must have an even number of hex characters\n"), 2;
  for (size_t i = 0; i < hl / 2; i++) {
    unsigned b;
    if (sscanf(hex + 2 * i, "%2x", &b) != 1)
      return fprintf(stderr, "dutctl mgmt: bad hex\n"), 2;
    v[i] = (uint8_t)b;
  }
  if (cmd < 0) {
    srand((unsigned)(time(NULL) ^ getpid()));
    cmd = rand() & 0xFFFF;
  }
  int fd = udp_bind(0);
  struct sockaddr_in t = parse_target(ip, DP_PORT_MGMT);
  uint8_t pkt[DP_MAX_PACKET], rx[DP_MAX_PACKET];
  size_t n = dp_encode_mgmt_set(pkt, (uint8_t)dut, (uint16_t)cmd, key, v, (uint16_t)(hl / 2));
  if (!n)
    return fprintf(stderr, "dutctl mgmt: encode failed\n"), 2;
  int tries = (int)(tmo / 200) > 0 ? (int)(tmo / 200) : 1;
  for (int attempt = 0; attempt < tries; attempt++) {
    sendto(fd, pkt, n, 0, (struct sockaddr *)&t, sizeof t);
    dp_hdr_t h;
    if (udp_recv(fd, rx, sizeof rx, 200, &t, DP_T_MGMT_ACK, &h, NULL) > 0) {
      dp_ack_t a;
      if (dp_decode_ack(rx + DP_HDR_LEN, h.length, &a) == 0 && a.cmd_id == (uint16_t)cmd) {
        printf("dut=%u key=0x%04x cmd_id=%u status=%u cfg_gen=%u\n", h.dut, a.key, a.cmd_id, a.status,
               a.cfg_gen);
        close(fd);
        return 0;
      }
    }
  }
  printf("noack\n");
  close(fd);
  return 1;
}

static int cmd_kbd(int argc, char **argv)
{
  if (argc < 1)
    return fprintf(stderr, "usage: dutctl kbd IP [KEY|NUMBER ...]\n"), 2;
  uint8_t bm[10] = {0};
  for (int i = 1; i < argc; i++) {
    char *end;
    long k = strtol(argv[i], &end, 0);
    if (*end)
      k = dp_key_by_name(argv[i]);
    if (k < 0 || k > 79)
      return fprintf(stderr, "unknown key %s\n", argv[i]), 2;
    bm[k / 8] |= (uint8_t)(1u << (k % 8));
  }
  int fd = udp_bind(0);
  struct sockaddr_in t = parse_target(argv[0], DP_PORT_KBD);
  uint8_t pkt[32];
  size_t n = dp_encode_kbd_set(pkt, DP_DUT_ANY, bm);
  /* KBD_SET has no ack; send a few copies (identical copies are harmless) */
  for (int i = 0; i < 3; i++)
    sendto(fd, pkt, n, 0, (struct sockaddr *)&t, sizeof t);
  close(fd);
  return 0;
}

/* ------------------------------------------------------------- listen */
/* One heartbeat as space-separated key=value pairs (for scripts such as
 * scripts/hwtest.sh). t = seconds since listen started (monotonic). Field
 * names follow ADR 0005 section 3; numbers decimal except the hex ids. */
static void print_hb_kv(const char *ip, const dp_hdr_t *h, const dp_heartbeat_t *hb, double t)
{
  printf("t=%.6f ip=%s dut=%u plen=%u seq=%u boot=%08x build=%08x dna=%016llx topo_index=%u "
         "topo_count=%u dip=%u link_flags=%u caps=%u cfg_gen=%u target_flags=%u kbd_owner=%u "
         "kbd_policy=%u selected=%u phys_change=%u phys_type=%u jtag_status=%u jtag_next_seq=%u "
         "uart_rx_seq=%u uart_tx_acc=%u rx_rejects=%u tx_drops=%u addr_src=%u dut_id=%u",
         t, ip, h->dut, h->length, hb->hb_seq, hb->boot_id, hb->build_id, (unsigned long long)hb->dna,
         hb->topo_index, hb->topo_count, hb->dip, hb->link_flags, hb->caps, hb->cfg_gen,
         hb->target_flags, hb->kbd_owner, hb->kbd_policy, hb->selected, hb->phys_change, hb->phys_type,
         hb->jtag_status, hb->jtag_next_seq, hb->uart_rx_seq, hb->uart_tx_acc, hb->rx_rejects,
         hb->tx_drops, hb->addr_src, hb->dut_id);
  printf(" has_video=%u", hb->has_video);
  if (hb->has_video)
    printf(" video_flags=%u console_screen=%u h_total=%u v_total=%u h_active=%u v_active=%u "
           "pixel_clock_hz=%u frames_captured=%u raster_lines_dropped=%u tmds_decode_errors=%u",
           hb->video_flags, hb->console_screen, hb->h_total, hb->v_total, hb->h_active, hb->v_active,
           hb->pixel_clock_hz, hb->frames_captured, hb->raster_lines_dropped, hb->tmds_decode_errors);
  printf(" has_link=%u", hb->has_link);
  if (hb->has_link)
    printf(" rx_phase_pos=%u rx_eye_width=%u rx_hunts=%u rx_bad_frames=%u rx_link_flags=%u",
           hb->rx_phase_pos, hb->rx_eye_width, hb->rx_hunts, hb->rx_bad_frames, hb->rx_link_flags);
  printf(" has_mem=%u", hb->has_mem);
  if (hb->has_mem)
    printf(" mem_flags=%u mem_errors=%u mem_dq_fail=%u mem_test_kib=%u mem_first_err=%u",
           hb->mem_flags, hb->mem_errors, hb->mem_dq_fail, hb->mem_test_kib, hb->mem_first_err);
  printf(" has_shield=%u", hb->has_shield);
  if (hb->has_shield)
    printf(" shd_flags=%u shd_revision=%u shd_features=%u shd_sense=%u shd_hdmi=%u shd_pwr=%u "
           "shd_i2c_errors=%u",
           hb->shd_flags, hb->shd_revision, hb->shd_features, hb->shd_sense, hb->shd_hdmi,
           hb->shd_pwr, hb->shd_i2c_errors);
  printf("\n");
  fflush(stdout);
}

static int cmd_listen(int argc, char **argv)
{
  double secs = 0;
  long count = 0, seen = 0;
  int kv = 0;
  for (int i = 0; i < argc; i++) {
    if (!strcmp(argv[i], "-t") && i + 1 < argc)
      secs = atof(argv[++i]);
    else if (!strcmp(argv[i], "-n") && i + 1 < argc)
      count = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--kv"))
      kv = 1;
    else
      return fprintf(stderr, "usage: dutctl listen [-t SECONDS] [-n COUNT] [--kv]\n"), 2;
  }
  int fd = udp_bind(DP_PORT_HB);
  signal(SIGINT, on_sig);
  signal(SIGTERM, on_sig);
  double t0 = now_s();
  double end = secs > 0 ? t0 + secs : 1e300;
  uint8_t buf[DP_MAX_PACKET];
  while (!g_stop && now_s() < end && (count <= 0 || seen < count)) {
    dp_hdr_t h;
    struct sockaddr_in src;
    int n = udp_recv(fd, buf, sizeof buf, 200, NULL, DP_T_HEARTBEAT, &h, &src);
    if (n < 0)
      continue;
    dp_heartbeat_t hb;
    if (dp_decode_heartbeat(buf + DP_HDR_LEN, h.length, &hb) < 0)
      continue;
    char ipb[32];
    inet_ntop(AF_INET, &src.sin_addr, ipb, sizeof ipb);
    seen++;
    if (kv) {
      print_hb_kv(ipb, &h, &hb, now_s() - t0);
      continue;
    }
    static const char *const src_names[] = {"none", "dhcp", "fallback", "static"};
    printf("[DUT %2u %-8s] ", hb.dut_id, hb.addr_src < 4 ? src_names[hb.addr_src] : "?");
    printf("%-15s dut%d seq %-8u boot %08x build %08x dna %016llx dip %02x link %02x "
           "power vio=%d kb=%d out=%d  uart rx %u tx %u  jtag next %u st %02x  rej %u  keys",
           ipb, h.dut, hb.hb_seq, hb.boot_id, hb.build_id, (unsigned long long)hb.dna, hb.dip,
           hb.link_flags, (hb.target_flags >> 1) & 1, hb.target_flags & 1, (hb.target_flags >> 2) & 1,
           hb.uart_rx_seq, hb.uart_tx_acc, hb.jtag_next_seq, hb.jtag_status, hb.rx_rejects);
    for (int k = 0; k < 80; k++)
      if (hb.kbd_eff[k / 8] & (1u << (k % 8)))
        printf(" %s", dp_key_name(k));
    static const char *const ktypes[] = {"none", "MK-I", "MK-II", "type3"};
    if (hb.has_link)
      printf("  kbd %s  rx phase %u eye %u hunts %u bad %u%s",
             hb.phys_type < 4 ? ktypes[hb.phys_type] : "?", hb.rx_phase_pos,
             hb.rx_eye_width, hb.rx_hunts, hb.rx_bad_frames,
             (hb.rx_link_flags & 1) ? " HUNTING" : "");
    if (hb.has_video) {
      if (hb.video_flags & DP_VF_CLOCK)
        printf("  video %s %ux%u of %ux%u %.3f MHz%s%s%s",
               (hb.video_flags & DP_VF_LOCKED) ? "locked" : "UNLOCKED",
               hb.h_active, hb.v_active, hb.h_total, hb.v_total, hb.pixel_clock_hz / 1e6,
               (hb.video_flags & DP_VF_LOCKED) ? ((hb.video_flags & DP_VF_HDMI) ? " HDMI" : " DVI") : "",
               (hb.video_flags & DP_VF_ISLANDS) ? "+islands" : "",
               (hb.video_flags & DP_VF_CAPTURE) ? " capture" : "");
      else
        printf("  video none");
      printf("  screen %s", dp_con_shown_name(hb.console_screen));
    }
    if (hb.has_mem) {
      if (!(hb.mem_flags & DP_MEM_CALIBRATED))
        printf("  ddr3 UNCALIBRATED");
      else if (hb.mem_flags & DP_MEM_ST_DONE) {
        if (hb.mem_flags & DP_MEM_ST_PASS)
          printf("  ddr3 ok (%u KiB tested)", hb.mem_test_kib);
        else
          printf("  ddr3 FAIL %u errors dq %04x first %06x", hb.mem_errors, hb.mem_dq_fail,
                 hb.mem_first_err);
      } else
        printf("  ddr3 %s", (hb.mem_flags & DP_MEM_ST_RUNNING) ? "testing" : "calibrated");
    }
    if (hb.phys_type) {
      printf("  phys");
      for (int k = 0; k < 80; k++)
        if (hb.kbd_phys[k / 8] & (1u << (k % 8)))
          printf(" %s", dp_key_name(k));
    }
    printf("\n");
    fflush(stdout);
  }
  close(fd);
  return 0;
}

/* ------------------------------------------------------------- UART */
static struct termios g_saved_tio;
static int g_tio_saved;
static void restore_tty(void)
{
  if (g_tio_saved)
    tcsetattr(0, TCSANOW, &g_saved_tio);
}

static int cmd_uart(int argc, char **argv)
{
  if (argc < 1)
    return fprintf(stderr, "usage: dutctl uart IP [--baud N] [--clear] [--from-start]\n"), 2;
  const char *ip = argv[0];
  int clear = 0, from_start = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--baud") && i + 1 < argc) {
      uint8_t v[4];
      uint32_t nco = dp_baud_nco(atof(argv[++i]));
      dp_put32(v, nco);
      if (mgmt_set(ip, DP_K_UART_BAUD, v, 4))
        return 1;
    } else if (!strcmp(argv[i], "--clear"))
      clear = 1;
    else if (!strcmp(argv[i], "--from-start"))
      from_start = 1;
  }
  struct sockaddr_in t = parse_target(ip, DP_PORT_UART);
  int sfd = udp_bind(DP_PORT_UART); /* snapshots (telemetry destination) */
  int tfd = udp_bind(0);            /* TX requests */
  us_state_t us;
  us_init(&us);
  if (isatty(0)) {
    struct termios tio;
    tcgetattr(0, &g_saved_tio);
    g_tio_saved = 1;
    atexit(restore_tty);
    tio = g_saved_tio;
    cfmakeraw(&tio);
    tcsetattr(0, TCSANOW, &tio);
    fprintf(stderr, "[dutctl uart: Ctrl-] to quit]\r\n");
  }
  signal(SIGINT, on_sig);
  uint8_t pending[DP_UART_TX_MAX * 8];
  size_t pend_len = 0;     /* bytes typed but not yet accepted, starting at us.tx_acked */
  double last_send = 0;
  int stdin_open = 1;
  uint8_t buf[DP_MAX_PACKET];

  if (clear) {
    uint8_t pkt[64];
    size_t n = dp_encode_uart_tx(pkt, DP_DUT_ANY, 0, (uint16_t)rand(), 1, NULL, 0);
    sendto(tfd, pkt, n, 0, (struct sockaddr *)&t, sizeof t);
  }

  while (!g_stop) {
    struct pollfd p[2] = {{.fd = sfd, .events = POLLIN}, {.fd = 0, .events = stdin_open ? POLLIN : 0}};
    poll(p, 2, 20);
    if (p[0].revents & POLLIN) {
      struct sockaddr_in src;
      socklen_t sl = sizeof src;
      ssize_t n = recvfrom(sfd, buf, sizeof buf, 0, (struct sockaddr *)&src, &sl);
      dp_hdr_t h;
      dp_snapshot_t s;
      if (n > 0 && src.sin_addr.s_addr == t.sin_addr.s_addr && dp_parse_hdr(buf, (size_t)n, &h) == 0 &&
          h.type == DP_T_UART_SNAP && dp_decode_snapshot(buf + DP_HDR_LEN, h.length, &s) == 0) {
        uint8_t out[512];
        uint32_t lost;
        uint32_t prev_acked = us.tx_acked;
        int was_synced = us.synced;
        size_t m = us_rx_snapshot(&us, &s, out, sizeof out, !from_start, &lost);
        if (lost)
          fprintf(stderr, "\r\n[dutctl: %u RX bytes lost]\r\n", lost);
        if (m)
          fwrite(out, 1, m, stdout), fflush(stdout);
        /* drop accepted bytes from the pending queue */
        if (was_synced) {
          int32_t adv = us_diff(us.tx_acked, prev_acked);
          if (adv > 0 && (size_t)adv <= pend_len) {
            memmove(pending, pending + adv, pend_len - (size_t)adv);
            pend_len -= (size_t)adv;
          }
        }
        us.tx_sent = us.tx_acked; /* anything unacknowledged gets re-sent */
      }
    }
    if (stdin_open && (p[1].revents & (POLLIN | POLLHUP))) {
      uint8_t in[256];
      ssize_t n = read(0, in, sizeof in);
      if (n <= 0)
        stdin_open = 0;
      for (ssize_t i = 0; i < n; i++) {
        if (in[i] == 0x1d && isatty(0)) /* Ctrl-] */
          g_stop = 1;
        else if (pend_len < sizeof pending)
          pending[pend_len++] = in[i];
      }
    }
    /* send pending bytes once we know the FPGA's offset; retry every 20 ms */
    if (us.synced && pend_len && now_s() - last_send > 0.02) {
      size_t chunk = pend_len;
      if (chunk > DP_UART_TX_MAX)
        chunk = DP_UART_TX_MAX;
      if (chunk > us.tx_free)
        chunk = us.tx_free;
      if (chunk) {
        uint8_t pkt[DP_MAX_PACKET];
        size_t n = dp_encode_uart_tx(pkt, DP_DUT_ANY, us.tx_acked, ++us.cmd_id, 0, pending, (uint16_t)chunk);
        sendto(tfd, pkt, n, 0, (struct sockaddr *)&t, sizeof t);
        us.tx_sent = us.tx_acked + (uint32_t)chunk;
      }
      last_send = now_s();
    }
    if (!stdin_open && pend_len == 0 && !isatty(0))
      break;
  }
  restore_tty();
  fprintf(stderr, "\n[dutctl uart: rx %llu bytes, lost %llu, reboots %u]\n",
          (unsigned long long)us.bytes_out, (unsigned long long)us.bytes_lost, us.reboots);
  return 0;
}

/* ------------------------------------------------------------- JTAG */
typedef struct {
  int fd;
  struct sockaddr_in t;
  uint32_t seq;
  uint32_t half;
  uint16_t target; /* 0 = the DUT, DP_JF_KBD = the physical keyboard's CPLD */
} jtag_ctx_t;

static int jtag_txn(jtag_ctx_t *j, uint32_t bits, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo,
                    uint16_t flags)
{
  uint8_t pkt[DP_MAX_PACKET], rx[DP_MAX_PACKET];
  size_t n = dp_encode_jtag_req(pkt, DP_DUT_ANY, j->seq, j->half, 0, (uint16_t)(flags | j->target),
                                bits, tms, tdi);
  uint8_t want_target = j->target ? DP_JT_KBD : DP_JT_DUT;
  if (!n)
    return -1;
  for (int attempt = 0; attempt < 50; attempt++) {
    sendto(j->fd, pkt, n, 0, (struct sockaddr *)&j->t, sizeof j->t);
    dp_hdr_t h;
    int r = udp_recv(j->fd, rx, sizeof rx, 100, &j->t, DP_T_JTAG_RESP, &h, NULL);
    if (r < 0)
      continue; /* lost request or response: resend the SAME seq (never re-clocked) */
    static dp_jtag_resp_t resp;
    if (dp_decode_jtag_resp(rx + DP_HDR_LEN, h.length, &resp) < 0 || resp.seq != j->seq ||
        resp.target != want_target)
      continue;
    switch (resp.status) {
    case DP_JS_DONE:
      if (flags & DP_JF_ABORT) { /* session reset */
        j->seq = resp.next_seq;
        return 0;
      }
      if (tdo)
        memcpy(tdo, resp.tdo, (bits + 7) / 8);
      j->seq = resp.next_seq;
      return 0;
    case DP_JS_BUSY:
      usleep(1000);
      continue;
    case DP_JS_BAD_SEQ:
      fprintf(stderr, "jtag: sequence mismatch (sent %u, expected %u); session lost\n", j->seq, resp.next_seq);
      return -1;
    case DP_JS_BAD_FMT:
      fprintf(stderr, "jtag: request rejected as malformed\n");
      return -1;
    default:
      if (j->target)
        fprintf(stderr, "jtag: keyboard JTAG off (no keyboard detected; `dutctl set IP kbd-jtag 1` "
                        "forces it on)\n");
      else
        fprintf(stderr, "jtag: target not powered\n");
      return -1;
    }
  }
  fprintf(stderr, "jtag: no response\n");
  return -1;
}

static int jtag_open(jtag_ctx_t *j, const char *ip, int kbd)
{
  j->fd = udp_bind(0);
  j->t = parse_target(ip, DP_PORT_JTAG);
  j->target = kbd ? DP_JF_KBD : 0;
  /* ~10.4 MHz to a DUT; ~2 MHz over the keyboard cable (jumper strips) */
  j->half = kbd ? 32 : 6;
  srand((unsigned)(time(NULL) ^ getpid()));
  j->seq = (uint32_t)rand();
  uint8_t z = 0;
  return jtag_txn(j, 1, &z, &z, NULL, DP_JF_ABORT); /* session reset: nothing clocked */
}

static int jtag_shift(jtag_ctx_t *j, uint32_t bits, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo)
{
  static uint8_t ctms[1024], ctdi[1024], ctdo[1024];
  memset(tdo, 0, (bits + 7) / 8);
  for (uint32_t done = 0; done < bits;) {
    uint32_t n = bits - done > DP_JTAG_MAX_BITS ? DP_JTAG_MAX_BITS : bits - done;
    xvc_copy_bits(ctms, tms, done, n);
    xvc_copy_bits(ctdi, tdi, done, n);
    if (jtag_txn(j, n, ctms, ctdi, ctdo, 0) < 0)
      return -1;
    for (uint32_t i = 0; i < n; i++)
      if (ctdo[i / 8] & (1u << (i % 8)))
        tdo[(done + i) / 8] |= (uint8_t)(1u << ((done + i) % 8));
    done += n;
  }
  return 0;
}

static int cmd_jtag_idcode(int argc, char **argv)
{
  if (argc < 1)
    return fprintf(stderr, "usage: dutctl jtag-idcode IP [--kbd]\n"), 2;
  int kbd = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--kbd"))
      kbd = 1;
    else
      return fprintf(stderr, "dutctl jtag-idcode: unknown option %s\n", argv[i]), 2;
  }
  jtag_ctx_t j;
  if (jtag_open(&j, argv[0], kbd) < 0)
    return 1;
  /* TLR (5x TMS=1), RTI, SELDR, CAPDR, SHDR, then 32 bits, exit on last */
  uint8_t tms[6] = {0}, tdi[6] = {0}, tdo[6];
  const char *s = "111110100" "0000000000000000000000000000000" "1";
  uint32_t bits = (uint32_t)strlen(s);
  for (uint32_t i = 0; i < bits; i++)
    if (s[i] == '1')
      tms[i / 8] |= (uint8_t)(1u << (i % 8));
  if (jtag_shift(&j, bits, tms, tdi, tdo) < 0)
    return 1;
  uint64_t v = 0;
  for (int i = 5; i >= 0; i--)
    v = v << 8 | tdo[i];
  printf("IDCODE 0x%08x\n", (uint32_t)(v >> 9));
  return 0;
}

static int cmd_xvc(int argc, char **argv)
{
  if (argc < 1)
    return fprintf(stderr, "usage: dutctl xvc IP [--port 2542] [--kbd]\n"), 2;
  int port = 2542, kbd = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--port") && i + 1 < argc)
      port = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--kbd"))
      kbd = 1;
    else
      return fprintf(stderr, "dutctl xvc: unknown option %s\n", argv[i]), 2;
  }
  int ls = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port), .sin_addr.s_addr = INADDR_ANY};
  if (bind(ls, (struct sockaddr *)&a, sizeof a) < 0 || listen(ls, 1) < 0)
    die("xvc listen");
  fprintf(stderr, "XVC server for %s%s on port %d (max %d bits per UDP shift)\n", argv[0],
          kbd ? " keyboard CPLD" : "", port, DP_JTAG_MAX_BITS);
  signal(SIGPIPE, SIG_IGN);
  static xvc_parser_t xp;
  static uint8_t tdo[XVC_MAX_BYTES];
  while (!g_stop) {
    int c = accept(ls, NULL, NULL);
    if (c < 0)
      continue;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    jtag_ctx_t j;
    if (jtag_open(&j, argv[0], kbd) < 0) { /* exclusive session per connection */
      close(c);
      continue;
    }
    xvc_init(&xp);
    fprintf(stderr, "xvc: client connected\n");
    for (;;) {
      uint8_t in[8192];
      ssize_t n = recv(c, in, sizeof in, 0);
      if (n <= 0 || xvc_feed(&xp, in, (size_t)n) < 0)
        break;
      xvc_cmd_t cmd;
      int fail = 0;
      while ((cmd = xvc_next(&xp)) != XVC_NONE) {
        if (cmd == XVC_GETINFO) {
          char info[64];
          int l = snprintf(info, sizeof info, "xvcServer_v1.0:%d\n", XVC_MAX_BYTES * 8);
          send(c, info, (size_t)l, 0);
        } else if (cmd == XVC_SETTCK) {
          uint32_t half = (xp.settck_period_ns + 8) / 16; /* ns -> half periods of 8 ns */
          if (half < 2)
            half = 2;
          j.half = half;
          uint32_t actual = half * 16;
          uint8_t r[4] = {(uint8_t)actual, (uint8_t)(actual >> 8), (uint8_t)(actual >> 16), (uint8_t)(actual >> 24)};
          send(c, r, 4, 0);
        } else if (cmd == XVC_SHIFT) {
          if (jtag_shift(&j, xp.shift_bits, xp.tms, xp.tdi, tdo) < 0) {
            fail = 1;
            break;
          }
          send(c, tdo, (xp.shift_bits + 7) / 8, 0);
        } else {
          fail = 1;
          break;
        }
        xvc_consume(&xp);
      }
      if (fail)
        break;
    }
    fprintf(stderr, "xvc: client disconnected\n");
    close(c);
    close(j.fd);
  }
  return 0;
}

/* ------------------------------------------------------------- relays */
static int cmd_relay(int argc, char **argv)
{
  if (argc < 2)
    return fprintf(stderr, "usage: dutctl relay TTY COMMAND...  (e.g. STATUS, STATUS 3, POWER 3 ON, POWER 1 2 OFF, CYCLE 2 3000, ALL OFF)\n"), 2;
  int fd = open(argv[0], O_RDWR | O_NOCTTY);
  if (fd < 0)
    die(argv[0]);
  struct termios tio;
  tcgetattr(fd, &tio);
  cfmakeraw(&tio);
  cfsetspeed(&tio, B115200);
  tio.c_cflag |= CLOCAL | CREAD;
  tio.c_cflag &= ~(tcflag_t)HUPCL; /* do not reset the Arduino on close */
  tcsetattr(fd, TCSANOW, &tio);
  char line[256] = "";
  /* request id: must differ between invocations, even several per second,
   * or the controller answers from its duplicate cache (ADR 0009) */
  struct timeval tv;
  gettimeofday(&tv, NULL);
  int id = (int)(((unsigned long)tv.tv_sec * 1000003UL + (unsigned long)tv.tv_usec * 7919UL +
                  (unsigned long)getpid() * 104729UL) % 99999UL) + 1;
  int l = snprintf(line, sizeof line, "#%d", id);
  for (int i = 1; i < argc; i++)
    l += snprintf(line + l, sizeof line - (size_t)l, " %s", argv[i]);
  line[l++] = '\n';
  /* An Uno resets when the port is first opened (DTR) and drops what
   * arrives during its bootloader: if nothing answers within 0.4 s, resend
   * the same line (same id, so a command that did run is answered from the
   * controller's duplicate cache, not executed twice) once it has booted
   * (EVENT BOOT) or every 0.7 s, for up to 4 s. */
  usleep(50000);
  if (write(fd, line, (size_t)l) != l)
    die("relay write");
  char resp[512];
  size_t rl = 0;
  double start = now_s(), end = start + 4.0, resend = start + 0.4;
  int rc = 1;
  while (now_s() < end && rl < sizeof resp - 1) {
    if (now_s() >= resend) {
      if (write(fd, line, (size_t)l) != l)
        die("relay write");
      resend = now_s() + 0.7;
    }
    struct pollfd p = {.fd = fd, .events = POLLIN};
    if (poll(&p, 1, 100) <= 0)
      continue;
    ssize_t n = read(fd, resp + rl, sizeof resp - 1 - rl);
    if (n > 0)
      rl += (size_t)n;
    resp[rl] = 0;
    char *nl;
    while ((nl = strchr(resp, '\n'))) {
      *nl = 0;
      char tag[16];
      snprintf(tag, sizeof tag, "#%d ", id);
      if (!strncmp(resp, "EVENT BOOT", 10))
        resend = now_s() + 0.05;   /* just booted: resend now */
      if (!strncmp(resp, tag, strlen(tag))) {
        printf("%s\n", resp + strlen(tag));
        rc = strncmp(resp + strlen(tag), "OK", 2) ? 1 : 0;
        end = 0;
      }
      memmove(resp, nl + 1, strlen(nl + 1) + 1);
      rl = strlen(resp);
    }
  }
  close(fd);
  if (end != 0)
    fprintf(stderr, "relay: no reply\n");
  return rc;
}

/* ------------------------------------------------------------- text display */
/* dutctl text IP [--fg N] [--bg N] [--jumbo] [--file F | LINE ...]
 * Writes an 80x25 screen (ADR 0012): chars at 0x0000, attributes at 0x0800,
 * default VGA palette at 0x1000, control at 0x1030 (force text if --force). */
static int cmd_text(int argc, char **argv)
{
  if (argc < 1)
    return fprintf(stderr, "usage: dutctl text IP [--screen N] [--fg N] [--bg N] [--force] [--jumbo] [--file F | LINE ...]\n"
                           "  --screen 0 editable (default), 1 no video, 2 select (palette/control only on 0)\n"), 2;
  static const uint32_t vga[16] = {0x000000, 0x0000AA, 0x00AA00, 0x00AAAA, 0xAA0000, 0xAA00AA, 0xAA5500,
                                   0xAAAAAA, 0x555555, 0x5555FF, 0x55FF55, 0x55FFFF, 0xFF5555, 0xFF55FF,
                                   0xFFFF55, 0xFFFFFF};
  static uint8_t mem[0x1031];
  int fg = 15, bg = 1, jumbo = 0, force = 0, row = 0, screen = 0;
  const char *file = NULL;
  memset(mem, ' ', 0x800);
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--screen") && i + 1 < argc) screen = atoi(argv[++i]) & 3;
    else if (!strcmp(argv[i], "--fg") && i + 1 < argc) fg = atoi(argv[++i]) & 15;
    else if (!strcmp(argv[i], "--bg") && i + 1 < argc) bg = atoi(argv[++i]) & 15;
    else if (!strcmp(argv[i], "--jumbo")) jumbo = 1;
    else if (!strcmp(argv[i], "--force")) force = 1;
    else if (!strcmp(argv[i], "--file") && i + 1 < argc) file = argv[++i];
    else if (row < 25) {
      size_t l = strlen(argv[i]);
      memcpy(mem + 80 * row++, argv[i], l > 80 ? 80 : l);
    }
  }
  if (file) {
    FILE *f = strcmp(file, "-") ? fopen(file, "r") : stdin;
    if (!f) die(file);
    char line[256];
    while (row < 25 && fgets(line, sizeof line, f)) {
      size_t l = strcspn(line, "\r\n");
      memcpy(mem + 80 * row++, line, l > 80 ? 80 : l);
    }
    if (f != stdin) fclose(f);
  }
  memset(mem + 0x800, (bg << 4) | fg, 2000);
  for (int i = 0; i < 16; i++) {
    mem[0x1000 + 3 * i] = (uint8_t)(vga[i] >> 16);
    mem[0x1001 + 3 * i] = (uint8_t)(vga[i] >> 8);
    mem[0x1002 + 3 * i] = (uint8_t)vga[i];
  }
  mem[0x1030] = (uint8_t)force;
  int fd = udp_bind(0);
  struct sockaddr_in t = parse_target(argv[0], DP_PORT_TEXT);
  if (screen == 3)
    return fprintf(stderr, "dutctl text: screen must be 0, 1 or 2\n"), 2;
  /* screens 1/2 keep their own palettes (2 = power-LED colours): chars + attrs only */
  size_t total = screen == 0 ? sizeof mem : 0x1000;
  size_t chunk = jumbo ? total : 1024;
  for (size_t off = 0; off < total; off += chunk) {
    size_t n = total - off < chunk ? total - off : chunk;
    uint8_t pkt[DP_HDR_LEN + 4 + sizeof mem];
    dp_put16(pkt + DP_HDR_LEN, (uint16_t)(((unsigned)screen << 13) | off));
    dp_put16(pkt + DP_HDR_LEN + 2, 0);
    memcpy(pkt + DP_HDR_LEN + 4, mem + off, n);
    size_t len = dp_encode_hdr(pkt, DP_T_TEXT_WRITE, (uint16_t)(4 + n), DP_DUT_ANY);
    if (sendto(fd, pkt, len, 0, (struct sockaddr *)&t, sizeof t) < 0)
      die("sendto (for --jumbo the interface MTU must be >= 4200)");
  }
  close(fd);
  return 0;
}

/* ------------------------------------------------------------- main */
static void usage(void)
{
  fprintf(stderr,
          "dutctl - Mimas A7 DUT supervisor control\n"
          "  dutctl listen [-t SECONDS] [-n COUNT] [--kv]\n"
          "  dutctl set IP NAME VALUE          (dutctl set for names)\n"
          "  dutctl mgmt IP KEY [HEXVALUE] [--cmd-id N] [--dut N]   raw MGMT_SET\n"
          "  dutctl kbd IP [KEY ...]           keys by name (A, RETURN, F1...) or matrix number\n"
          "  dutctl uart IP [--baud N] [--clear] [--from-start]\n"
          "  dutctl jtag-idcode IP [--kbd]     (--kbd: the physical keyboard's CPLD)\n"
          "  dutctl xvc IP [--port 2542] [--kbd]\n"
          "  dutctl relay TTY COMMAND...\n"
          "  dutctl text IP [--screen N] [--fg N] [--bg N] [--force] [--jumbo] [--file F | LINE ...]\n"
          "  dutctl video IP [--frames N] [--out PREFIX] [--enable] [--require-complete]\n"
          "  dutctl thumbs IFACE [--out PREFIX] [--pictures N] [--request] [--force IP] [--scale 1|2]\n"
          "  dutctl screenshot [IP|DIGIT] [-o FILE.png|.ppm] [--screen auto|editable|novideo|select]\n"
          "                    [--timeout S]     one frame from a video target (alias: dutctl -S)\n");
}


/* ------------------------------------------------------------- video capture */
static int cmd_video(int argc, char **argv)
{
  if (argc < 1)
    return fprintf(stderr, "usage: dutctl video IP [--frames N] [--out PREFIX] [--enable] "
                           "[--require-complete] [--timeout S]\n"
                           "  receives raster packets (UDP 6504) from IP, assembles frames and writes\n"
                           "  PREFIX-NNNNNN.ppm (default prefix 'frame'); --enable switches capture on\n"
                           "  first; --require-complete exits 1 if any frame was incomplete\n"), 2;
  const char *ip = argv[0], *prefix = "frame";
  long frames = 1, timeout_s = 10;
  int enable = 0, require = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--out") && i + 1 < argc) prefix = argv[++i];
    else if (!strcmp(argv[i], "--timeout") && i + 1 < argc) timeout_s = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--enable")) enable = 1;
    else if (!strcmp(argv[i], "--require-complete")) require = 1;
    else return fprintf(stderr, "dutctl video: unknown option %s\n", argv[i]), 2;
  }
  struct sockaddr_in t = parse_target(ip, DP_PORT_RASTER);
  int fd = udp_bind(DP_PORT_RASTER);
  int big = 8 << 20;
  setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);
  if (enable) {
    uint8_t one = 1;
    if (mgmt_set(ip, DP_K_CAPTURE_EN, &one, 1) < 0)
      return fprintf(stderr, "dutctl video: enabling capture failed\n"), 1;
  }
  static rf_asm_t a;
  static uint8_t buf[DP_RASTER_MAX_PACKET + 64];
  rf_init(&a);
  signal(SIGINT, on_sig);
  long done = 0, incomplete = 0;
  double end = now_s() + timeout_s;
  rf_frame_t f;
  while (!g_stop && done < frames && now_s() < end) {
    dp_hdr_t h;
    int n = udp_recv(fd, buf, sizeof buf, 200, &t, DP_T_RASTER, &h, NULL);
    if (n < 0)
      continue;
    dp_raster_t r;
    if (dp_decode_raster(buf + DP_HDR_LEN, h.length, &r) < 0)
      continue;
    if (rf_feed(&a, &r, &f) != 1)
      continue;
    char path[512];
    snprintf(path, sizeof path, "%s-%06ld.ppm", prefix, done);
    if (rf_write_ppm(path, &f) < 0)
      fprintf(stderr, "dutctl video: cannot write %s\n", path);
    printf("frame %u: %ux%u %s (%u lines, %u dup%s) -> %s\n", f.frame, f.width, f.height,
           f.complete ? "complete" : "INCOMPLETE", f.lines_received, f.duplicates,
           f.dropped_flag ? ", FPGA dropped lines" : "", path);
    if (!f.complete)
      incomplete++;
    done++;
  }
  close(fd);
  if (done < frames)
    fprintf(stderr, "dutctl video: %ld of %ld frames received (late packets %u)\n", done, frames, a.late);
  return (done < frames || (require && incomplete)) ? 1 : 0;
}

/* ------------------------------------------------------------- thumbnails */
/* dutctl thumbs: receive thumbnail relay frames (raw Ethernet 0x88B5, ADR
 * 0005 section 10) on an interface and write every machine's latest complete
 * picture as PREFIX-mNN.ppm. Needs CAP_NET_RAW (or root) for AF_PACKET.
 * Pictures arrive when a board is asked: --request broadcasts requests like a
 * console on its select screen; --force IP sets key 0x0041 on that board to
 * this interface's MAC (and clears it on exit). */
typedef struct {
  uint32_t frame;
  int active;
  uint16_t width, height, rows;
  uint8_t have[DP_TH_MAX_H];
  uint8_t rgb[3 * DP_TH_MAX_W * DP_TH_MAX_H];
} th_pic_t;

static int th_write_ppm(const char *path, const th_pic_t *p)
{
  FILE *f = fopen(path, "wb");
  if (!f)
    return -1;
  fprintf(f, "P6\n%u %u\n255\n", p->width, p->height);
  for (unsigned y = 0; y < p->height; y++)
    fwrite(p->rgb + 3u * p->width * y, 3, p->width, f);
  return fclose(f);
}

static int cmd_thumbs(int argc, char **argv)
{
  if (argc < 1)
    return fprintf(stderr, "usage: dutctl thumbs IFACE [--out PREFIX] [--pictures N] [--timeout S]\n"
                           "         [--request] [--force IP] [--scale 1|2] [--div N]\n"
                           "  writes PREFIX-mNN.ppm (default prefix 'thumb') for each machine's latest\n"
                           "  complete thumbnail; --request broadcasts requests every 250 ms, --force IP\n"
                           "  points that board's relay at this interface (key 0x0041). Needs CAP_NET_RAW.\n"),
           2;
  const char *ifname = argv[0], *prefix = "thumb", *force_ip = NULL;
  long want = 0, timeout_s = 10;
  int request = 0, scale = DP_TH_SCALE_HALF, div = 2;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--out") && i + 1 < argc) prefix = argv[++i];
    else if (!strcmp(argv[i], "--pictures") && i + 1 < argc) want = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--timeout") && i + 1 < argc) timeout_s = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--request")) request = 1;
    else if (!strcmp(argv[i], "--force") && i + 1 < argc) force_ip = argv[++i];
    else if (!strcmp(argv[i], "--scale") && i + 1 < argc) scale = (int)strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--div") && i + 1 < argc) div = (int)strtol(argv[++i], NULL, 0);
    else return fprintf(stderr, "dutctl thumbs: unknown option %s\n", argv[i]), 2;
  }
  if ((scale != 1 && scale != 2) || div < 1 || div > 15)
    return fprintf(stderr, "dutctl thumbs: --scale 1 or 2, --div 1..15\n"), 2;
  int fd = socket(AF_PACKET, SOCK_RAW, htons(DP_ETH_THUMB));
  if (fd < 0)
    return perror("dutctl thumbs: AF_PACKET socket (needs CAP_NET_RAW)"), 1;
  struct ifreq ifr;
  memset(&ifr, 0, sizeof ifr);
  snprintf(ifr.ifr_name, sizeof ifr.ifr_name, "%s", ifname);
  if (ioctl(fd, SIOCGIFINDEX, &ifr) < 0)
    return perror("dutctl thumbs: interface"), 1;
  int ifindex = ifr.ifr_ifindex;
  if (ioctl(fd, SIOCGIFHWADDR, &ifr) < 0)
    return perror("dutctl thumbs: interface MAC"), 1;
  uint8_t mymac[6];
  memcpy(mymac, ifr.ifr_hwaddr.sa_data, 6);
  struct sockaddr_ll sll = {.sll_family = AF_PACKET, .sll_protocol = htons(DP_ETH_THUMB), .sll_ifindex = ifindex};
  if (bind(fd, (struct sockaddr *)&sll, sizeof sll) < 0)
    return perror("dutctl thumbs: bind"), 1;
  int big = 16 << 20;
  setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);
  if (force_ip) {
    uint8_t v[8];
    memcpy(v, mymac, 6);
    v[6] = (uint8_t)scale;
    v[7] = (uint8_t)div;
    if (mgmt_set(force_ip, DP_K_THUMB_FORCE, v, 8) != 0)
      return fprintf(stderr, "dutctl thumbs: setting the forced destination failed\n"), 1;
  }
  static th_pic_t pics[32];
  static uint8_t buf[9100], lines[3 * DP_TH_MAX_W * 64];
  uint32_t nosrc = 0, seen = 0;
  long done = 0, frames = 0, bad = 0;
  signal(SIGINT, on_sig);
  double end = now_s() + timeout_s, next_req = 0;
  while (!g_stop && now_s() < end && (want == 0 || done < want)) {
    if (request && now_s() >= next_req) {
      uint8_t f[64] = {0};
      memset(f, 0xFF, 6);
      memcpy(f + 6, mymac, 6);
      dp_put16(f + 12, DP_ETH_THUMB);
      dp_encode_thumb_request(f + 14, (uint8_t)scale, (uint8_t)div);
      struct sockaddr_ll to = sll;
      to.sll_halen = 6;
      memset(to.sll_addr, 0xFF, 6);
      if (sendto(fd, f, 60, 0, (struct sockaddr *)&to, sizeof to) < 0)
        perror("dutctl thumbs: request");
      next_req = now_s() + 0.25;
    }
    struct pollfd p = {.fd = fd, .events = POLLIN};
    if (poll(&p, 1, 50) <= 0)
      continue;
    ssize_t n = recv(fd, buf, sizeof buf, 0);
    if (n < 14 + DP_TH_REQ_LEN || dp_get16(buf + 12) != DP_ETH_THUMB)
      continue;
    dp_thumb_t t;
    if (dp_decode_thumb(buf + 14, (size_t)n - 14, &t) < 0) {
      bad++;
      continue;
    }
    if (t.subtype == DP_TH_SUB_REQ)
      continue;
    seen |= 1u << t.machine;
    if (t.subtype == DP_TH_SUB_NOSRC) {
      if (!(nosrc & (1u << t.machine)))
        printf("machine %u: present, no source\n", t.machine);
      nosrc |= 1u << t.machine;
      continue;
    }
    frames++;
    if (t.nlines > 64 || dp_thumb_lines(&t, lines, sizeof lines) < 0) {
      bad++;
      continue;
    }
    th_pic_t *pc = &pics[t.machine];
    if (!pc->active || pc->frame != t.frame || pc->width != t.width) {
      memset(pc->have, 0, sizeof pc->have);
      pc->active = 1;
      pc->frame = t.frame;
      pc->width = t.width;
      pc->height = t.height;
      pc->rows = 0;
    }
    for (unsigned l = 0; l < t.nlines; l++) {
      unsigned y = t.row + l;
      if (!pc->have[y])
        pc->rows++;
      pc->have[y] = 1;
      memcpy(pc->rgb + 3u * pc->width * y, lines + 3u * t.width * l, 3u * t.width);
    }
    if (pc->rows == pc->height) {
      char path[512];
      snprintf(path, sizeof path, "%s-m%02u.ppm", prefix, t.machine);
      if (th_write_ppm(path, pc) < 0)
        fprintf(stderr, "dutctl thumbs: cannot write %s\n", path);
      else
        printf("machine %u picture %u: %ux%u -> %s\n", t.machine, t.frame, pc->width, pc->height, path);
      nosrc &= ~(1u << t.machine);
      pc->active = 0;
      done++;
    }
  }
  if (force_ip) {
    uint8_t off[8] = {0, 0, 0, 0, 0, 0, 1, 2};
    mgmt_set(force_ip, DP_K_THUMB_FORCE, off, 8);
  }
  close(fd);
  printf("%ld pictures, %ld relay frames, %ld malformed; machines seen %08x\n", done, frames, bad, seen);
  return (want && done < want) ? 1 : 0;
}

/* ------------------------------------------------------------- screenshot */
/* dutctl screenshot [TARGET] (issue 0042): one complete frame from a board's
 * video target DUT, written as PNG or PPM. The management protocol has no
 * read, so what this changes is put back to known values afterwards:
 * capture enable to its state in the heartbeat (video_flags b2), the
 * telemetry destination to broadcast (the default), the console screen to
 * auto (only if --screen forced it). */
static struct {
  int armed;            /* something was changed: restore at exit */
  char ip[INET_ADDRSTRLEN];
  uint8_t cap_prev;     /* capture enable before */
  int screen_forced;
} g_shot;

static void shot_restore(void)
{
  if (!g_shot.armed)
    return;
  g_shot.armed = 0;
  static const uint8_t bc_ip[4] = {0xff, 0xff, 0xff, 0xff};
  static const uint8_t bc_mac[6] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
  uint8_t zero = 0;
  int bad = 0;
  bad |= mgmt_set_q(g_shot.ip, DP_K_CAPTURE_EN, &g_shot.cap_prev, 1, 1);
  if (g_shot.screen_forced)
    bad |= mgmt_set_q(g_shot.ip, DP_K_CON_SCREEN, &zero, 1, 1);
  bad |= mgmt_set_q(g_shot.ip, DP_K_DEST_IP, bc_ip, 4, 1);
  bad |= mgmt_set_q(g_shot.ip, DP_K_DEST_MAC, bc_mac, 6, 1);
  if (bad)
    fprintf(stderr, "dutctl screenshot: WARNING: restoring the settings of %s failed; restore by hand:\n"
                    "  dutctl mgmt %s 0x0040 %02x; dutctl mgmt %s 0x0003 ffffffff; "
                    "dutctl mgmt %s 0x0004 ffffffffffff%s%s%s\n",
            g_shot.ip, g_shot.ip, g_shot.cap_prev, g_shot.ip, g_shot.ip,
            g_shot.screen_forced ? "; dutctl mgmt " : "", g_shot.screen_forced ? g_shot.ip : "",
            g_shot.screen_forced ? " 0x0035 00" : "");
}

/* This host's address and MAC on the route to dst (network order). */
static int local_addr_for(struct in_addr dst, struct in_addr *src, uint8_t mac[6], char *ifname, size_t ifcap)
{
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0)
    return -1;
  struct sockaddr_in t = {.sin_family = AF_INET, .sin_port = htons(DP_PORT_MGMT), .sin_addr = dst};
  struct sockaddr_in me;
  socklen_t ml = sizeof me;
  int r = connect(fd, (struct sockaddr *)&t, sizeof t) == 0 && getsockname(fd, (struct sockaddr *)&me, &ml) == 0;
  close(fd);
  if (!r || me.sin_addr.s_addr == htonl(INADDR_ANY))
    return -1;
  *src = me.sin_addr;
  struct ifaddrs *ifs, *i;
  if (getifaddrs(&ifs) < 0)
    return -1;
  int found = 0;
  for (i = ifs; i && !found; i = i->ifa_next)
    if (i->ifa_addr && i->ifa_addr->sa_family == AF_INET &&
        ((struct sockaddr_in *)i->ifa_addr)->sin_addr.s_addr == src->s_addr) {
      snprintf(ifname, ifcap, "%s", i->ifa_name);
      found = 1;
    }
  freeifaddrs(ifs);
  if (!found)
    return -1;
  char path[128], line[64];
  snprintf(path, sizeof path, "/sys/class/net/%s/address", ifname);
  FILE *f = fopen(path, "r");
  if (!f)
    return -1;
  r = fgets(line, sizeof line, f) && parse_mac(line, mac) == 0;
  fclose(f);
  if (!r)
    return -1;
  static const uint8_t z[6];
  return (memcmp(mac, z, 6) && !(mac[0] & 1)) ? 0 : -1; /* loopback / multicast MAC: unusable */
}

static const char *ep_ip(const ss_ep_t *e, char *buf)
{
  struct in_addr a = {.s_addr = e->addr};
  return inet_ntop(AF_INET, &a, buf, INET_ADDRSTRLEN);
}

/* "machine 1 (console 2, dut1 203.28.176.87)" */
static const char *ep_desc(const ss_ep_t *e, char *buf, size_t cap)
{
  char ipb[INET_ADDRSTRLEN];
  int m = ss_machine_of(e->dut_id), d = ss_machine_digit(m);
  if (d >= 0)
    snprintf(buf, cap, "machine %d (console %c, dut%u %s)", m, d, e->ep, ep_ip(e, ipb));
  else
    snprintf(buf, cap, "machine %d (dut%u %s)", m, e->ep, ep_ip(e, ipb));
  return buf;
}

static int has_ext(const char *path, const char *ext)
{
  size_t l = strlen(path), e = strlen(ext);
  return l > e && !strcasecmp(path + l - e, ext);
}

static int cmd_screenshot(int argc, char **argv)
{
  static const char *const usage_txt =
      "usage: dutctl screenshot [TARGET] [-o FILE] [--screen auto|editable|novideo|select] [--timeout S]\n"
      "       dutctl -S [TARGET] [options]           (same; like m65 -S)\n"
      "  TARGET: an endpoint IPv4 address, or a console digit 1-9, 0 (machine 0-9,\n"
      "  as on the select screen); none = the only machine that can be captured.\n"
      "  Only a board's video target DUT can be captured (it is not changed).\n"
      "  Points the DUT's telemetry at this host, enables capture, waits for one\n"
      "  complete frame (default timeout 10 s), then restores capture, broadcast\n"
      "  telemetry and (with --screen) the auto console screen, also on errors\n"
      "  and Ctrl-C. FILE: .png or .ppm; default mega65-screenshot-NNNNNN.png\n"
      "  (lowest free number in the current directory, never overwritten).\n";
  const char *target = NULL, *out = NULL;
  double timeout_s = 10;
  int screen = -1;
  for (int i = 0; i < argc; i++) {
    if ((!strcmp(argv[i], "-o") || !strcmp(argv[i], "--out")) && i + 1 < argc)
      out = argv[++i];
    else if (!strcmp(argv[i], "--timeout") && i + 1 < argc)
      timeout_s = atof(argv[++i]);
    else if (!strcmp(argv[i], "--screen") && i + 1 < argc) {
      static const char *const names[] = {"auto", "editable", "novideo", "select"};
      const char *s = argv[++i];
      for (int k = 0; k < 4; k++)
        if (!strcmp(s, names[k]) || (!strcmp(s, "no-video") && k == 2))
          screen = k;
      if (screen < 0)
        return fprintf(stderr, "dutctl screenshot: --screen auto|editable|novideo|select\n"), 2;
    } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help"))
      return fputs(usage_txt, stderr), 2;
    else if (argv[i][0] != '-' && !target)
      target = argv[i];
    else
      return fprintf(stderr, "dutctl screenshot: unexpected %s\n%s", argv[i], usage_txt), 2;
  }
  if (out && !has_ext(out, ".png") && !has_ext(out, ".ppm"))
    return fprintf(stderr, "dutctl screenshot: FILE must end in .png or .ppm\n"), 2;
  if (timeout_s <= 0)
    timeout_s = 10;
  int want_machine = -1;
  struct in_addr want_addr = {0};
  if (target) {
    if (strlen(target) == 1 && ss_digit_machine(target[0]) >= 0)
      want_machine = ss_digit_machine(target[0]);
    else if (inet_pton(AF_INET, target, &want_addr) != 1)
      return fprintf(stderr, "dutctl screenshot: TARGET must be an IPv4 address or a digit 1-9, 0\n"), 2;
    else if (want_addr.s_addr == htonl(INADDR_BROADCAST) || IN_MULTICAST(ntohl(want_addr.s_addr)) ||
             want_addr.s_addr == htonl(INADDR_ANY))
      return fprintf(stderr, "dutctl screenshot: TARGET must be a unicast endpoint address\n"), 2;
  }

  struct sigaction sa = {0};
  sa.sa_handler = on_sig; /* no SA_RESTART: poll() returns at once */
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGTERM, &sa, NULL);
  sigaction(SIGHUP, &sa, NULL);

  /* 1. heartbeats: who is where, which DUT is each board's video target */
  enum { MAX_EP = 64 };
  static ss_ep_t eps[MAX_EP];
  int neps = 0;
  {
    int fd = udp_bind(DP_PORT_HB);
    uint8_t buf[DP_MAX_PACKET];
    double end = now_s() + 1.5;
    while (!g_stop && now_s() < end) {
      dp_hdr_t h;
      struct sockaddr_in src;
      if (udp_recv(fd, buf, sizeof buf, 100, NULL, DP_T_HEARTBEAT, &h, &src) < 0)
        continue;
      dp_heartbeat_t hb;
      if (dp_decode_heartbeat(buf + DP_HDR_LEN, h.length, &hb) < 0)
        continue;
      int k = ss_find_addr(eps, neps, src.sin_addr.s_addr);
      if (k < 0) {
        if (neps == MAX_EP)
          continue;
        k = neps++;
      }
      ss_ep_t *e = &eps[k];
      e->addr = src.sin_addr.s_addr;
      e->ep = h.dut;
      e->dut_id = hb.dut_id;
      e->selected = hb.selected;
      e->dna = hb.dna;
      e->boot_id = hb.boot_id;
      e->caps = hb.caps;
      e->has_video = hb.has_video;
      e->video_flags = hb.video_flags;
      e->console_screen = hb.console_screen;
      e->h_active = hb.h_active;
      e->v_active = hb.v_active;
    }
    close(fd);
  }
  if (g_stop)
    return 130;
  char d1[96], d2[96];
  int k;
  if (want_machine >= 0) {
    int cnt;
    k = ss_find_machine(eps, neps, want_machine, &cnt);
    if (k < 0)
      return fprintf(stderr, "dutctl screenshot: no heartbeat from machine %d (console %s) in 1.5 s\n",
                     want_machine, target), 1;
    if (cnt > 1)
      fprintf(stderr, "dutctl screenshot: warning: %d endpoints claim machine %d; using %s\n", cnt,
              want_machine, ep_desc(&eps[k], d1, sizeof d1));
  } else if (target) {
    k = ss_find_addr(eps, neps, want_addr.s_addr);
    if (k < 0)
      return fprintf(stderr, "dutctl screenshot: no heartbeat from %s in 1.5 s (is it an endpoint, "
                             "and are its heartbeats sent to this host?)\n", target), 1;
  } else {
    int idx[MAX_EP];
    int c = ss_capturable(eps, neps, idx, MAX_EP);
    if (c == 0)
      return fprintf(stderr, "dutctl screenshot: no machine can be captured (%d endpoints heard; "
                             "none is its board's video target with video locked)\n", neps), 1;
    if (c > 1) {
      fprintf(stderr, "dutctl screenshot: %d machines can be captured; choose one as TARGET:\n", c);
      for (int i = 0; i < c && i < MAX_EP; i++)
        fprintf(stderr, "  %s\n", ep_desc(&eps[idx[i]], d1, sizeof d1));
      return 1;
    }
    k = idx[0];
  }
  ss_ep_t *e = &eps[k];
  ep_desc(e, d1, sizeof d1);
  if (!ss_is_video_target(e)) {
    int vt = ss_board_video_target(e), s = ss_sibling(eps, neps, k);
    if (vt < 0)
      fprintf(stderr, "dutctl screenshot: %s is not its board's video target; that board has no local "
                      "video target (selected 0x%02x)\n", d1, e->selected);
    else if (s >= 0)
      fprintf(stderr, "dutctl screenshot: %s is not its board's video target; the video target on that "
                      "board is %s\n", d1, ep_desc(&eps[s], d2, sizeof d2));
    else
      fprintf(stderr, "dutctl screenshot: %s is not its board's video target; the video target on that "
                      "board is its dut%d\n", d1, vt);
    return 1;
  }
  if (!(e->caps & (1u << 4)))
    return fprintf(stderr, "dutctl screenshot: %s has no HDMI capture (capability b4 clear)\n", d1), 1;
  if (!e->has_video || !(e->video_flags & DP_VF_LOCKED))
    fprintf(stderr, "dutctl screenshot: warning: %s reports no locked video; trying anyway\n", d1);

  char ip[INET_ADDRSTRLEN], ifname[IF_NAMESIZE + 1];
  ep_ip(e, ip);
  struct in_addr me;
  uint8_t mac[6];
  if (local_addr_for((struct in_addr){.s_addr = e->addr}, &me, mac, ifname, sizeof ifname) < 0)
    return fprintf(stderr, "dutctl screenshot: cannot find this host's address/MAC towards %s\n", ip), 1;

  /* 2. raster socket first, then point the DUT at this host and enable */
  int fd = udp_bind(DP_PORT_RASTER);
  int big = 8 << 20;
  setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);
  snprintf(g_shot.ip, sizeof g_shot.ip, "%s", ip);
  g_shot.cap_prev = (e->has_video && (e->video_flags & DP_VF_CAPTURE)) ? 1 : 0;
  g_shot.screen_forced = screen > 0;
  g_shot.armed = 1;
  atexit(shot_restore);
  int rc = 1;
  uint8_t ipv[4], one = 1, scr = (uint8_t)(screen > 0 ? screen : 0);
  memcpy(ipv, &me.s_addr, 4);
  double settle = now_s();
  if (screen > 0) {
    if (mgmt_set_q(ip, DP_K_CON_SCREEN, &scr, 1, 1))
      goto out;
    settle = now_s() + 0.5; /* on a self-loop the receiver re-locks after a screen change */
  }
  if (mgmt_set_q(ip, DP_K_DEST_MAC, mac, 6, 1) || mgmt_set_q(ip, DP_K_DEST_IP, ipv, 4, 1) ||
      mgmt_set_q(ip, DP_K_CAPTURE_EN, &one, 1, 1))
    goto out;

  /* 3. one complete frame */
  {
    static rf_asm_t a;
    static uint8_t buf[DP_RASTER_MAX_PACKET + 64];
    rf_init(&a);
    struct sockaddr_in t = {.sin_family = AF_INET, .sin_addr.s_addr = e->addr};
    double end = now_s() + timeout_s;
    rf_frame_t f;
    long frames = 0, incomplete = 0, best = 0;
    int got = 0;
    while (!g_stop && now_s() < end) {
      dp_hdr_t h;
      if (udp_recv(fd, buf, sizeof buf, 100, &t, DP_T_RASTER, &h, NULL) < 0)
        continue;
      dp_raster_t r;
      if (dp_decode_raster(buf + DP_HDR_LEN, h.length, &r) < 0 || rf_feed(&a, &r, &f) != 1)
        continue;
      if (now_s() < settle)
        continue;
      frames++;
      if (!f.complete) {
        incomplete++;
        if (f.lines_received > best)
          best = f.lines_received;
        continue;
      }
      got = 1;
      break;
    }
    if (!got) {
      if (g_stop)
        fprintf(stderr, "dutctl screenshot: interrupted\n");
      else
        fprintf(stderr, "dutctl screenshot: no complete frame from %s in %g s (%ld frames, %ld incomplete, "
                        "best %ld lines; late packets %u)\n", d1, timeout_s, frames, incomplete, best, a.late);
      rc = g_stop ? 130 : 1;
      goto out;
    }
    /* restore before writing: the board does not need to wait for the disk */
    close(fd);
    fd = -1;
    shot_restore();

    /* 4. write */
    char path[64];
    int ofd = -1;
    if (out)
      ofd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    else
      for (int n = 0; n < 1000000; n++) {
        snprintf(path, sizeof path, "mega65-screenshot-%06d.png", n);
        ofd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0644);
        if (ofd >= 0 || errno != EEXIST)
          break;
      }
    const char *file = out ? out : path;
    FILE *fp = ofd >= 0 ? fdopen(ofd, "wb") : NULL;
    if (!fp) {
      fprintf(stderr, "dutctl screenshot: cannot create %s: %s\n", file, strerror(errno));
      if (ofd >= 0)
        close(ofd);
      goto out;
    }
    int ok;
    if (has_ext(file, ".ppm"))
      ok = fprintf(fp, "P6\n%u %u\n255\n", f.width, f.height) > 0 &&
           fwrite(f.rgb, 3, (size_t)f.width * f.height, fp) == (size_t)f.width * f.height;
    else
      ok = pw_write_png_fp(fp, f.rgb, f.width, f.height) == 0;
    long size = ok ? ftell(fp) : -1;
    if (fclose(fp) != 0 || !ok) {
      fprintf(stderr, "dutctl screenshot: writing %s failed\n", file);
      goto out;
    }
    printf("%s: %ux%u, %ld bytes, frame %u, %s\n", file, f.width, f.height, size, f.frame, d1);
    rc = 0;
  }
out:
  if (fd >= 0)
    close(fd);
  shot_restore();
  return rc;
}

int main(int argc, char **argv)
{
  if (argc < 2) {
    usage();
    return 2;
  }
  const char *c = argv[1];
  argc -= 2;
  argv += 2;
  if (!strcmp(c, "listen")) return cmd_listen(argc, argv);
  if (!strcmp(c, "set")) return cmd_set(argc, argv);
  if (!strcmp(c, "mgmt")) return cmd_mgmt(argc, argv);
  if (!strcmp(c, "kbd")) return cmd_kbd(argc, argv);
  if (!strcmp(c, "uart")) return cmd_uart(argc, argv);
  if (!strcmp(c, "jtag-idcode")) return cmd_jtag_idcode(argc, argv);
  if (!strcmp(c, "xvc")) return cmd_xvc(argc, argv);
  if (!strcmp(c, "relay")) return cmd_relay(argc, argv);
  if (!strcmp(c, "text")) return cmd_text(argc, argv);
  if (!strcmp(c, "video")) return cmd_video(argc, argv);
  if (!strcmp(c, "thumbs")) return cmd_thumbs(argc, argv);
  if (!strcmp(c, "screenshot") || !strcmp(c, "-S")) return cmd_screenshot(argc, argv);
  usage();
  return 2;
}
