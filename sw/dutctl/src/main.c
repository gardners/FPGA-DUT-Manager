/* dutctl - command line control of Mimas A7 DUT supervisors.
 *
 *   dutctl listen [-t SECONDS]                 decode heartbeats
 *   dutctl set IP NAME VALUE                   management (see `dutctl help`)
 *   dutctl kbd IP [KEY ...]                    hold keys (none = all up)
 *   dutctl uart IP [--baud N] [--clear] [--from-start]
 *                                              interactive UART bridge
 *   dutctl jtag-idcode IP                      read JTAG IDCODE over UDP
 *   dutctl xvc IP [--port 2542]                XVC 1.0 server for Vivado
 *   dutctl relay TTY COMMAND...                Arduino relay controller
 *
 * LGPL-2.1-or-later. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "dutproto.h"
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
static int mgmt_set(const char *ip, uint16_t key, const uint8_t *val, uint16_t vlen)
{
  int fd = udp_bind(0);
  struct sockaddr_in t = parse_target(ip, DP_PORT_MGMT);
  uint8_t pkt[64], rx[DP_MAX_PACKET];
  srand((unsigned)(time(NULL) ^ getpid()));
  uint16_t cmd = (uint16_t)rand();
  size_t n = dp_encode_mgmt_set(pkt, DP_DUT_ANY, cmd, key, val, vlen);
  for (int attempt = 0; attempt < 5; attempt++) {
    sendto(fd, pkt, n, 0, (struct sockaddr *)&t, sizeof t);
    dp_hdr_t h;
    int r = udp_recv(fd, rx, sizeof rx, 200, &t, DP_T_MGMT_ACK, &h, NULL);
    if (r > 0) {
      dp_ack_t a;
      if (dp_decode_ack(rx + DP_HDR_LEN, h.length, &a) == 0 && a.cmd_id == cmd) {
        static const char *const st[] = {"ok", "bad key", "bad length", "bad value", "duplicate"};
        printf("dut%d key 0x%04x: %s (config generation %u)\n", h.dut, a.key,
               a.status < 5 ? st[a.status] : "?", a.cfg_gen);
        close(fd);
        return (a.status == DP_ACK_OK || a.status == DP_ACK_DUPLICATE) ? 0 : 1;
      }
    }
  }
  fprintf(stderr, "no MGMT_ACK from %s\n", ip);
  close(fd);
  return 1;
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
            "  names: mac ip dest-ip dest-mac baud uart-fast uart-snap uart-period-us\n"
            "         kbd-policy kbd-override kbd-target video-target coupled capture\n"
            "         hb-period-ms out-policy (0 auto, 1 on, 2 off)\n");
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
    {"mac", DP_K_MAC, 6}, {"ip", DP_K_IP, -4}, {"dest-ip", DP_K_DEST_IP, -4},
    {"dest-mac", DP_K_DEST_MAC, 6}, {"baud", DP_K_UART_BAUD, 4}, {"uart-fast", DP_K_UART_FAST, 1},
    {"uart-snap", DP_K_UART_SNAP_EN, 1}, {"uart-period-us", DP_K_UART_PERIOD, 2},
    {"kbd-policy", DP_K_KBD_POLICY, 1}, {"kbd-override", DP_K_KBD_OVERRIDE, 1},
    {"kbd-target", DP_K_KBD_TARGET, 1}, {"video-target", DP_K_VID_TARGET, 1},
    {"coupled", DP_K_COUPLED, 1}, {"capture", DP_K_CAPTURE_EN, 1},
    {"hb-period-ms", DP_K_HB_PERIOD, 2}, {"out-policy", DP_K_OUT_POLICY, 1},
  };
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
static int cmd_listen(int argc, char **argv)
{
  double secs = 0;
  for (int i = 0; i < argc; i++)
    if (!strcmp(argv[i], "-t") && i + 1 < argc)
      secs = atof(argv[++i]);
  int fd = udp_bind(DP_PORT_HB);
  signal(SIGINT, on_sig);
  double end = secs > 0 ? now_s() + secs : 1e300;
  uint8_t buf[DP_MAX_PACKET];
  while (!g_stop && now_s() < end) {
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
    printf("%-15s dut%d seq %-8u boot %08x build %08x dna %016llx dip %02x link %02x "
           "power vio=%d kb=%d out=%d  uart rx %u tx %u  jtag next %u st %02x  rej %u  keys",
           ipb, h.dut, hb.hb_seq, hb.boot_id, hb.build_id, (unsigned long long)hb.dna, hb.dip,
           hb.link_flags, (hb.target_flags >> 1) & 1, hb.target_flags & 1, (hb.target_flags >> 2) & 1,
           hb.uart_rx_seq, hb.uart_tx_acc, hb.jtag_next_seq, hb.jtag_status, hb.rx_rejects);
    for (int k = 0; k < 80; k++)
      if (hb.kbd_eff[k / 8] & (1u << (k % 8)))
        printf(" %s", dp_key_name(k));
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
} jtag_ctx_t;

static int jtag_txn(jtag_ctx_t *j, uint32_t bits, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo,
                    uint16_t flags)
{
  uint8_t pkt[DP_MAX_PACKET], rx[DP_MAX_PACKET];
  size_t n = dp_encode_jtag_req(pkt, DP_DUT_ANY, j->seq, j->half, 0, flags, bits, tms, tdi);
  if (!n)
    return -1;
  for (int attempt = 0; attempt < 50; attempt++) {
    sendto(j->fd, pkt, n, 0, (struct sockaddr *)&j->t, sizeof j->t);
    dp_hdr_t h;
    int r = udp_recv(j->fd, rx, sizeof rx, 100, &j->t, DP_T_JTAG_RESP, &h, NULL);
    if (r < 0)
      continue; /* lost request or response: resend the SAME seq (never re-clocked) */
    static dp_jtag_resp_t resp;
    if (dp_decode_jtag_resp(rx + DP_HDR_LEN, h.length, &resp) < 0 || resp.seq != j->seq)
      continue;
    switch (resp.status) {
    case DP_JS_DONE:
      if (flags & 1) { /* session reset */
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
      fprintf(stderr, "jtag: target not powered\n");
      return -1;
    }
  }
  fprintf(stderr, "jtag: no response\n");
  return -1;
}

static int jtag_open(jtag_ctx_t *j, const char *ip)
{
  j->fd = udp_bind(0);
  j->t = parse_target(ip, DP_PORT_JTAG);
  j->half = 6; /* ~10.4 MHz */
  srand((unsigned)(time(NULL) ^ getpid()));
  j->seq = (uint32_t)rand();
  uint8_t z = 0;
  return jtag_txn(j, 1, &z, &z, NULL, 1); /* session reset: nothing clocked */
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
    return fprintf(stderr, "usage: dutctl jtag-idcode IP\n"), 2;
  jtag_ctx_t j;
  if (jtag_open(&j, argv[0]) < 0)
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
    return fprintf(stderr, "usage: dutctl xvc IP [--port 2542]\n"), 2;
  int port = 2542;
  for (int i = 1; i < argc; i++)
    if (!strcmp(argv[i], "--port") && i + 1 < argc)
      port = atoi(argv[++i]);
  int ls = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port), .sin_addr.s_addr = INADDR_ANY};
  if (bind(ls, (struct sockaddr *)&a, sizeof a) < 0 || listen(ls, 1) < 0)
    die("xvc listen");
  fprintf(stderr, "XVC server for %s on port %d (max %d bits per UDP shift)\n", argv[0], port, DP_JTAG_MAX_BITS);
  signal(SIGPIPE, SIG_IGN);
  static xvc_parser_t xp;
  static uint8_t tdo[XVC_MAX_BYTES];
  while (!g_stop) {
    int c = accept(ls, NULL, NULL);
    if (c < 0)
      continue;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    jtag_ctx_t j;
    if (jtag_open(&j, argv[0]) < 0) { /* exclusive session per connection */
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
    return fprintf(stderr, "usage: dutctl relay TTY COMMAND...  (e.g. STATUS, POWER 3 1, CYCLE 2 3000)\n"), 2;
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
  int id = (int)(time(NULL) % 100000);
  int l = snprintf(line, sizeof line, "#%d", id);
  for (int i = 1; i < argc; i++)
    l += snprintf(line + l, sizeof line - (size_t)l, " %s", argv[i]);
  line[l++] = '\n';
  /* an Arduino may reset when the port opens: allow it to boot */
  usleep(50000);
  if (write(fd, line, (size_t)l) != l)
    die("relay write");
  char resp[512];
  size_t rl = 0;
  double end = now_s() + 3.0;
  int rc = 1;
  while (now_s() < end && rl < sizeof resp - 1) {
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

/* ------------------------------------------------------------- main */
static void usage(void)
{
  fprintf(stderr,
          "dutctl - Mimas A7 DUT supervisor control\n"
          "  dutctl listen [-t SECONDS]\n"
          "  dutctl set IP NAME VALUE          (dutctl set for names)\n"
          "  dutctl kbd IP [KEY ...]           keys by name (A, RETURN, F1...) or matrix number\n"
          "  dutctl uart IP [--baud N] [--clear] [--from-start]\n"
          "  dutctl jtag-idcode IP\n"
          "  dutctl xvc IP [--port 2542]\n"
          "  dutctl relay TTY COMMAND...\n");
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
  if (!strcmp(c, "kbd")) return cmd_kbd(argc, argv);
  if (!strcmp(c, "uart")) return cmd_uart(argc, argv);
  if (!strcmp(c, "jtag-idcode")) return cmd_jtag_idcode(argc, argv);
  if (!strcmp(c, "xvc")) return cmd_xvc(argc, argv);
  if (!strcmp(c, "relay")) return cmd_relay(argc, argv);
  usage();
  return 2;
}
