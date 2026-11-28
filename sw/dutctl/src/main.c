/* dutctl - command line control of Mimas A7 DUT supervisors.
 *
 *   dutctl listen [-t SECONDS] [-n COUNT] [--kv]
 *                                              decode heartbeats (--kv: key=value)
 *   dutctl mgmt IP KEY [HEXVALUE] [--cmd-id N] [--dut N]
 *                                              raw MGMT_SET, prints the ack
 *   dutctl set IP NAME VALUE                   management (see `dutctl help`)
 *   dutctl apply [-t SECONDS]                  send duts.conf [board DNA] settings
 *                                              to the boards heard (issue 0066)
 *   dutctl keeper [--min-interval S]           re-apply them whenever a board's
 *                                              boot id changes (systemd user unit)
 *   dutctl kbd IP [KEY ...]                    hold keys (none = all up)
 *   dutctl uart IP [--baud N] [--clear] [--from-start]
 *                                              interactive UART bridge
 *   dutctl jtag-idcode IP [DUT]|NAME [--kbd]   read JTAG IDCODE over UDP
 *   dutctl xvc IP [DUT]|NAME [--port 2542] [--kbd]
 *                                              XVC 1.0 server for Vivado
 *                                              (--kbd: the physical keyboard's
 *                                              CPLD instead of the DUT, ADR 0014)
 *   dutctl jtag-speed IP [DUT]|NAME [--kbd] [--reps N] [--save]
 *                                              max safe octopus TCK (issue 0054)
 *   dutctl duts                                configured DUTs (issue 0053)
 *   dutctl jtag-discover [--scan] [--power-cycle --yes] [--write]
 *                                              USB JTAG adaptors -> DUTs
 *   (global: --conf FILE, else $DUTCTL_CONF, else ~/.config/dutctl/duts.conf)
 *   dutctl relay [--raw] TTY COMMAND...        Arduino relay controller (out-policy
 *                                              hooks for DUTs in duts.conf, issue 0056)
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
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "dutconf.h"
#include "dutset.h"
#include "dutproto.h"
#include "jtagdisc.h"
#include "jtagspeed.h"
#include "keeper.h"
#include "pngwrite.h"
#include "rasterframe.h"
#include "relayhook.h"
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
static int udp_bind_addr(uint16_t port, in_addr_t addr)
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
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = addr};
  if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0)
    die("bind");
  return fd;
}

static int udp_bind(uint16_t port)
{
  return udp_bind_addr(port, htonl(INADDR_ANY));
}

/* Heartbeat listener for apply / keeper (issue 0066). Bound to the limited
 * broadcast address it hears the default (broadcast) heartbeats of every
 * board, like `dutctl listen` and alongside it, but never takes a share of
 * heartbeats a board sends unicast to this host while another dutctl has
 * pointed its telemetry here (screenshot): SO_REUSEPORT load-balances
 * unicast datagrams between the INADDR_ANY sockets of one port. --any
 * binds INADDR_ANY instead (unicast telemetry, loopback tests). */
static int hb_bind(int any)
{
  return udp_bind_addr(DP_PORT_HB, any ? htonl(INADDR_ANY) : htonl(INADDR_BROADCAST));
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
            "         hb-period-ms out-policy (0 auto, 1 UART/KIO10 on, 2 all off incl. JTAG)\n"
            "         kbd-leds (physical keyboard LEDs: 0 status colour, 1 DUT's, 2 host)\n"
            "         console-screen (0 auto incl. passthrough, 1 editable, 2 no video, 3 select)\n"
            "         kbd-jtag (keyboard CPLD JTAG: 0 auto, 1 on, 2 off, 3 on with JTAGEN low)\n"
            "         power-ctl (shield power outputs CTRL0..7 bitmask, e.g. 0x05)\n"
            "         kbd-jtag-quiet (0 off, 1 (default) pause the keyboard scan during keyboard JTAG,\n"
            "                         2 keyboard scan stopped; needs kbd-jtag 1)\n"
            "         jtag-tdo-vote (TDO sampling: 0 single, 1 majority of 3, 2 majority of 5)\n"
            "         vlan (inter-board relay VLAN ID, default 1650, 0 = untagged)\n"
            "         host-vlan (VLAN ID of all host traffic, default 0 = untagged; 1..4094 tags it\n"
            "                    and accepts host frames only on it (untagged: ARP, ping, MGMT);\n"
            "                    DHCP leases are dropped and renewed on the new VLAN)\n"
            "         vlan-base (IPv4 /24 base of the inter-board VLAN, last octet 0, default\n"
            "                    10.231.50.0; the board answers ARP/ping on the vlan for\n"
            "                    base + 16 + DIP[7:4])\n"
            "         hdmi-owner (DUT on the HDMI IN: 0 the video target's (default), 1 DUT0, 2 DUT1,\n"
            "                     3 none; the others show relayed video, full-screen when selected)\n"
            "         relay-view (relayed full-screen view: 0 complete pictures only, 1 live line by\n"
            "                     line, lost lines keep the previous picture (default))\n"
            "         kbd-led-rgb RRGGBB,RRGGBB,RRGGBB,RRGGBB (LED0..3 for kbd-leds 2;\n"
            "                     LED0/1 = drive LED, LED2/3 = power LED)\n");
    return 2;
  }
  uint16_t key, len;
  uint8_t v[DS_MAX_VALUE];
  const char *why;
  int r = ds_encode(argv[1], argv[2], &key, v, &len, &why);
  if (r == DS_UNKNOWN_NAME)
    return fprintf(stderr, "unknown setting %s\n", argv[1]), 2;
  if (r != DS_OK)
    return fprintf(stderr, "%s: %s\n", argv[1], why), 2;
  return mgmt_set(argv[0], key, v, len);
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
  printf(" has_relay=%u", hb->has_relay);
  if (hb->has_relay)
    printf(" rl_req_sent=%u rl_req_full=%u rl_rx_req=%u rl_rx_lines=%u rl_rx_bad=%u rl_rx_ovf=%u "
           "rl_rx_nosrc=%u rl_rx_vlan=%u rl_rx_long=%u rl_rx_foreign=%u rl_full_pics=%u "
           "rl_full_swaps=%u rl_flags=%u rl_last_machine=%u rl_last_scale=%u rl_full_age=%u",
           hb->rl_req_sent, hb->rl_req_full, hb->rl_rx_req, hb->rl_rx_lines, hb->rl_rx_bad,
           hb->rl_rx_ovf, hb->rl_rx_nosrc, hb->rl_rx_vlan, hb->rl_rx_long, hb->rl_rx_foreign,
           hb->rl_full_pics, hb->rl_full_swaps, hb->rl_flags, hb->rl_last_machine,
           hb->rl_last_scale, hb->rl_full_age);
  printf(" has_rxload=%u", hb->has_rxload);
  if (hb->has_rxload)
    printf(" rl_fifo_hwm=%u rl_wr_stall=%u rl_mem_wait=%u rl_wf_hwm=%u rl_fifo_aw=%u", hb->rl_fifo_hwm,
           hb->rl_wr_stall, hb->rl_mem_wait, hb->rl_wf_hwm, hb->rl_fifo_aw);
  printf(" has_net=%u", hb->has_net);
  if (hb->has_net)
    printf(" host_vlan=%u host_vlan_drops=%u", hb->host_vlan, hb->host_vlan_drops);
  printf(" has_vident=%u", hb->has_vident);
  if (hb->has_vident)
    printf(" vlan_ip=%u.%u.%u.%u vlan=%u vlan_hits=%u", hb->vlan_ip[0], hb->vlan_ip[1], hb->vlan_ip[2],
           hb->vlan_ip[3], hb->vlan, hb->vlan_hits);
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
    if (hb.has_relay) {
      printf("  relay req %u (full %u) heard %u  rx lines %u bad %u (ovf %u) nosrc %u vlan-drop %u "
             "long %u foreign %u",
             hb.rl_req_sent, hb.rl_req_full, hb.rl_rx_req, hb.rl_rx_lines, hb.rl_rx_bad, hb.rl_rx_ovf,
             hb.rl_rx_nosrc, hb.rl_rx_vlan, hb.rl_rx_long, hb.rl_rx_foreign);
      if (hb.rl_flags & DP_RLF_LAST_VALID)
        printf("  last m%u %s", hb.rl_last_machine,
               (hb.rl_flags & DP_RLF_LAST_NOSRC) ? "nosrc" : hb.rl_last_scale == 3 ? "1/1"
                                                       : hb.rl_last_scale == 2 ? "1/4" : "1/2");
      printf("  full pics %u shown %u", hb.rl_full_pics, hb.rl_full_swaps);
      if (hb.rl_flags & DP_RLF_FULL_WANT)
        printf(" %s age %u ms", (hb.rl_flags & DP_RLF_FULL_FRESH) ? "LIVE" : "NO-PICTURE",
               hb.rl_full_age * 8u);
      if (hb.rl_flags & DP_RLF_FULL_WANT)
        printf(" %s", (hb.rl_flags & DP_RLF_LIVE) ? "live-view" : "complete-view");
      if (hb.rl_flags & DP_RLF_STREAMING)
        printf(" streaming");
      if (hb.has_rxload)
        printf("  rx fifo peak %u/%u wf peak %u stall %u wait %u", hb.rl_fifo_hwm, 1u << hb.rl_fifo_aw,
               2u * hb.rl_wf_hwm, hb.rl_wr_stall, hb.rl_mem_wait);
    }
    if (hb.has_net && (hb.host_vlan || hb.host_vlan_drops))
      printf("  host-vlan %u (vlan drops %u)", hb.host_vlan, hb.host_vlan_drops);
    if (hb.has_vident) {
      if (hb.vlan_ip[0] | hb.vlan_ip[1] | hb.vlan_ip[2] | hb.vlan_ip[3])
        printf("  vlan-ip %u.%u.%u.%u (vlan %u, answered %u)", hb.vlan_ip[0], hb.vlan_ip[1],
               hb.vlan_ip[2], hb.vlan_ip[3], hb.vlan, hb.vlan_hits);
      else
        printf("  vlan-ip off");
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

/* ------------------------------------------------------------- per-DUT config */
/* Issue 0053: ~/.config/dutctl/duts.conf (or $DUTCTL_CONF, or --conf FILE). */
static const char *g_conf_arg;
static char g_conf_path[1024];
static dc_conf_t g_conf;
static int g_conf_loaded;

static const char *conf_path(void)
{
  if (!g_conf_path[0]) {
    if (g_conf_arg)
      snprintf(g_conf_path, sizeof g_conf_path, "%s", g_conf_arg);
    else if (getenv("DUTCTL_CONF") && *getenv("DUTCTL_CONF"))
      snprintf(g_conf_path, sizeof g_conf_path, "%s", getenv("DUTCTL_CONF"));
    else
      dc_default_path(g_conf_path, sizeof g_conf_path);
  }
  return g_conf_path;
}

static const dc_conf_t *conf(void)
{
  if (!g_conf_loaded) {
    static char err[4096];
    int missing;
    int r = dc_load(conf_path(), &g_conf, err, sizeof err, &missing);
    if (r < 0)
      fprintf(stderr, "dutctl: cannot read %s: %s\n", conf_path(), strerror(errno));
    else if (r > 0)
      fprintf(stderr, "dutctl: %s:\n%s", conf_path(), err);
    if (g_conf_arg && missing)
      fprintf(stderr, "dutctl: note: %s does not exist (empty configuration)\n", conf_path());
    g_conf_loaded = 1;
  }
  return &g_conf;
}

/* A JTAG target on the command line: "IP [DUT]" or a configured DUT name. */
typedef struct {
  char ip[64];
  int dut;              /* endpoint index, -1 = wildcard */
  const dc_dut_t *cfg;  /* NULL if not configured */
} target_t;

static int is_index(const char *s)
{
  return *s && strspn(s, "0123456789") == strlen(s) && strlen(s) <= 3;
}

/* Consumes argv[0] (and argv[1] if it is a DUT index); returns the number
 * of arguments used, -1 on error (message printed). */
static int resolve_target(const char *cmd, int argc, char **argv, target_t *t)
{
  memset(t, 0, sizeof *t);
  t->dut = -1;
  if (argc < 1)
    return -1;
  int used = 1;
  if (argc > 1 && is_index(argv[1])) {
    t->dut = atoi(argv[1]);
    used = 2;
  }
  struct in_addr a;
  if (inet_pton(AF_INET, argv[0], &a) == 1) {
    snprintf(t->ip, sizeof t->ip, "%s", argv[0]);
    t->cfg = dc_find_ip(conf(), t->ip, t->dut);
    return used;
  }
  t->cfg = dc_find_name(conf(), argv[0]);
  if (!t->cfg) {
    fprintf(stderr, "dutctl %s: '%s' is neither an IPv4 address nor a DUT in %s (see dutctl duts)\n", cmd,
            argv[0], conf_path());
    return -1;
  }
  if (t->cfg->jtag == DC_JTAG_OCTOPUS && !t->cfg->ip[0]) {
    fprintf(stderr, "dutctl %s: DUT %s has no ip = (octopus JTAG needs the supervisor endpoint)\n", cmd,
            t->cfg->name);
    return -1;
  }
  snprintf(t->ip, sizeof t->ip, "%s", t->cfg->ip);
  if (t->dut < 0)
    t->dut = t->cfg->dut;
  return used;
}

/* TCK half period for an octopus target: --half, else the configured value,
 * else the built-in default (~10.4 MHz to a DUT, ~2 MHz to the keyboard). */
static uint32_t target_half(const target_t *t, int kbd, long override)
{
  if (override >= 2)
    return (uint32_t)override;
  if (t->cfg && (kbd ? t->cfg->kbd_tck_half : t->cfg->tck_half) >= 2)
    return (uint32_t)(kbd ? t->cfg->kbd_tck_half : t->cfg->tck_half);
  return kbd ? 32 : 6;
}

/* ------------------------------------------------------------- USB JTAG */
static int is_exec(const char *p)
{
  return p && *p && access(p, X_OK) == 0;
}

/* openFPGALoader: $DUTCTL_OPENFPGALOADER, $PATH, then this repo's tools/. */
static const char *find_ofl(void)
{
  static char buf[1024];
  const char *e = getenv("DUTCTL_OPENFPGALOADER");
  if (e && *e)
    return is_exec(e) ? e : NULL;
  const char *path = getenv("PATH");
  if (path) {
    const char *p = path;
    while (*p) {
      size_t l = strcspn(p, ":");
      snprintf(buf, sizeof buf, "%.*s/openFPGALoader", (int)l, p);
      if (l && is_exec(buf))
        return buf;
      p += l + (p[l] == ':');
    }
  }
#ifdef DUTCTL_REPO_OFL
  if (is_exec(DUTCTL_REPO_OFL))
    return DUTCTL_REPO_OFL;
#endif
  return NULL;
}

static int usb_cmd_for(const dc_dut_t *d, const char *mode, int port, jd_cmd_t *c)
{
  const char *ofl = find_ofl();
  const char *cable = d->cable[0] ? d->cable : dc_default_cable(d->usb_vid, d->usb_pid);
  if (jd_ofl_cmd(c, ofl ? ofl : "openFPGALoader", cable, d->usb_vid, d->usb_pid, d->usb_serial,
                 NULL, d->ftdi_channel, d->usb_freq, mode, port) < 0) {
    fprintf(stderr, "dutctl: DUT %s: no openFPGALoader cable known for %04x:%04x (set cable = ...)\n",
            d->name, d->usb_vid, d->usb_pid);
    return -1;
  }
  return 0;
}

/* jtag = usb: print the command (and tool hints), or exec it with --exec. */
static int usb_jtag(const dc_dut_t *d, const char *mode, int port, int exec)
{
  jd_cmd_t c;
  if (usb_cmd_for(d, mode, port, &c) < 0)
    return 1;
  if (!d->usb_serial[0])
    fprintf(stderr, "dutctl: warning: DUT %s has no usb_serial; the first %04x:%04x adaptor is used "
                    "(recorded USB port: %s)\n", d->name, d->usb_vid, d->usb_pid,
            d->usb_path[0] ? d->usb_path : "none");
  if (exec) {
    if (!find_ofl())
      return fprintf(stderr, "dutctl: openFPGALoader not found (PATH, $DUTCTL_OPENFPGALOADER)\n"), 1;
    fflush(stdout);
    execv(c.argv[0], c.argv);
    perror(c.argv[0]);
    return 1;
  }
  char line[2048];
  jd_cmd_str(&c, line, sizeof line);
  printf("%s\n", line);
  fprintf(stderr, "# DUT %s uses USB JTAG; run the line above, or add --exec.\n", d->name);
  if (d->usb_serial[0] || d->tty[0])
    fprintf(stderr, "# m65:%s%s%s%s\n", d->usb_serial[0] ? " -f " : "", d->usb_serial,
            d->tty[0] ? " -l " : "", d->tty);
  return 0;
}

/* ------------------------------------------------------------- JTAG */
typedef struct {
  int fd;
  struct sockaddr_in t;
  uint32_t seq;
  uint32_t half;
  uint8_t dut;     /* header dut field: endpoint index or DP_DUT_ANY */
  uint16_t target; /* 0 = the DUT, DP_JF_KBD = the physical keyboard's CPLD */
  uint32_t max_bits; /* per JTAG_REQ: fits one unfragmented packet (issue 0059) */
} jtag_ctx_t;

/* path MTU towards the supervisors: global --mtu N, else $DUTCTL_MTU, else
 * 1500. Every JTAG shift is split into requests that fit one unfragmented
 * IPv4 packet (the FPGA does not reassemble fragments), at most
 * DP_JTAG_MAX_BITS (issue 0059). */
static unsigned g_mtu = DP_MTU_DEFAULT;

static int set_mtu(const char *s, const char *what)
{
  char *end;
  long v = strtol(s, &end, 0);
  if (!*s || *end || v < DP_MTU_MIN || v > 65535) {
    fprintf(stderr, "dutctl: %s %s: need an MTU of %d..65535 bytes\n", what, s, DP_MTU_MIN);
    return -1;
  }
  g_mtu = (unsigned)v;
  return 0;
}

static int jtag_txn(jtag_ctx_t *j, uint32_t bits, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo,
                    uint16_t flags)
{
  uint8_t pkt[DP_MAX_PACKET], rx[DP_MAX_PACKET];
  size_t n = dp_encode_jtag_req(pkt, j->dut, j->seq, j->half, 0, (uint16_t)(flags | j->target),
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
  if (j->dut != DP_DUT_ANY)
    fprintf(stderr, "jtag: no response (is %s really endpoint dut%u? a wrong index is dropped)\n",
            inet_ntoa(j->t.sin_addr), j->dut);
  else
    fprintf(stderr, "jtag: no response\n");
  return -1;
}

static int jtag_open(jtag_ctx_t *j, const target_t *t, int kbd, uint32_t half)
{
  j->fd = udp_bind(0);
  j->t = parse_target(t->ip, DP_PORT_JTAG);
  j->target = kbd ? DP_JF_KBD : 0;
  j->dut = t->dut >= 0 ? (uint8_t)t->dut : DP_DUT_ANY;
  j->half = half;
  j->max_bits = dp_jtag_max_bits_for_mtu(g_mtu);
  srand((unsigned)(time(NULL) ^ getpid()));
  j->seq = (uint32_t)rand();
  uint8_t z = 0;
  return jtag_txn(j, 1, &z, &z, NULL, DP_JF_ABORT); /* session reset: nothing clocked */
}

static int jtag_chunk(void *ctx, uint32_t n, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo)
{
  return jtag_txn(ctx, n, tms, tdi, tdo, 0);
}

/* any length: consecutive requests of <= j->max_bits continue the shift
 * exactly (no extra TCK edges, TAP state carried over) */
static int jtag_shift(jtag_ctx_t *j, uint32_t bits, const uint8_t *tms, const uint8_t *tdi, uint8_t *tdo)
{
  return xvc_split_shift(bits, tms, tdi, tdo, j->max_bits, jtag_chunk, j);
}

static int cmd_jtag_idcode(int argc, char **argv)
{
  static const char *const use = "usage: dutctl jtag-idcode IP [DUT] | NAME  [--kbd] [--half N] [--exec]\n"
                                 "  NAME: a DUT from the configuration (dutctl duts); jtag = usb prints the\n"
                                 "  openFPGALoader command (--exec runs it). --half: TCK half period override\n";
  target_t t;
  int used = resolve_target("jtag-idcode", argc, argv, &t);
  if (used < 0)
    return fputs(argc < 1 ? use : "", stderr), 2;
  int kbd = 0, exec = 0;
  long half = 0;
  for (int i = used; i < argc; i++) {
    if (!strcmp(argv[i], "--kbd"))
      kbd = 1;
    else if (!strcmp(argv[i], "--exec"))
      exec = 1;
    else if (!strcmp(argv[i], "--half") && i + 1 < argc)
      half = strtol(argv[++i], NULL, 0);
    else
      return fprintf(stderr, "dutctl jtag-idcode: unknown option %s\n%s", argv[i], use), 2;
  }
  if (t.cfg && t.cfg->jtag == DC_JTAG_USB && !kbd)
    return usb_jtag(t.cfg, "detect", 0, exec);
  if (!t.ip[0])
    return fprintf(stderr, "dutctl jtag-idcode: no supervisor ip for %s\n", argv[0]), 2;
  jtag_ctx_t j;
  if (jtag_open(&j, &t, kbd, target_half(&t, kbd, half)) < 0)
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
  static const char *const use = "usage: dutctl xvc IP [DUT] | NAME  [--port 2542] [--kbd] [--half N] [--exec]\n"
                                 "  the configured / --half TCK is the fastest XVC settck may select\n";
  target_t t;
  int used = resolve_target("xvc", argc, argv, &t);
  if (used < 0)
    return fputs(argc < 1 ? use : "", stderr), 2;
  int port = 2542, kbd = 0, exec = 0;
  long half_arg = 0;
  for (int i = used; i < argc; i++) {
    if (!strcmp(argv[i], "--port") && i + 1 < argc)
      port = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--kbd"))
      kbd = 1;
    else if (!strcmp(argv[i], "--exec"))
      exec = 1;
    else if (!strcmp(argv[i], "--half") && i + 1 < argc)
      half_arg = strtol(argv[++i], NULL, 0);
    else
      return fprintf(stderr, "dutctl xvc: unknown option %s\n%s", argv[i], use), 2;
  }
  if (t.cfg && t.cfg->jtag == DC_JTAG_USB && !kbd)
    return usb_jtag(t.cfg, "xvc", port, exec);
  if (!t.ip[0])
    return fprintf(stderr, "dutctl xvc: no supervisor ip for %s\n", argv[0]), 2;
  uint32_t min_half = target_half(&t, kbd, half_arg);
  int ls = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port), .sin_addr.s_addr = INADDR_ANY};
  if (bind(ls, (struct sockaddr *)&a, sizeof a) < 0 || listen(ls, 1) < 0)
    die("xvc listen");
  fprintf(stderr, "XVC server for %s%s on port %d (max %u bits per UDP shift at MTU %u, TCK <= %.2f MHz)\n",
          t.ip, kbd ? " keyboard CPLD" : "", port, dp_jtag_max_bits_for_mtu(g_mtu), g_mtu,
          js_freq_hz((int)min_half) / 1e6);
  signal(SIGPIPE, SIG_IGN);
  static xvc_parser_t xp;
  static uint8_t tdo[XVC_MAX_BYTES];
  while (!g_stop) {
    int c = accept(ls, NULL, NULL);
    if (c < 0)
      continue;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    jtag_ctx_t j;
    if (jtag_open(&j, &t, kbd, min_half) < 0) { /* exclusive session per connection */
      close(c);
      continue;
    }
    xvc_init(&xp);
    fprintf(stderr, "xvc: client connected\n");
    for (;;) {
      uint8_t in[8192];
      ssize_t n = recv(c, in, sizeof in, 0);
      if (n <= 0)
        break;
      if (xvc_feed(&xp, in, (size_t)n) < 0) {
        fprintf(stderr, "xvc: input buffer overflow (%zu + %zd bytes); dropping the client\n", xp.len, n);
        break;
      }
      xvc_cmd_t cmd;
      int fail = 0;
      while ((cmd = xvc_next(&xp)) != XVC_NONE) {
        if (cmd == XVC_GETINFO) {
          char info[64];
          /* XVC 1.0: the maximum shift vector in BYTES, TMS + TDI together
           * (Xilinx reference server; openFPGALoader halves it per vector).
           * Advertising bits here (as before 2026-11-27) let clients send
           * 4x larger shifts than we accept, and they were dropped.
           * XVC_ADVERTISED_BYTES (16384 = 8192 per vector = 65536 bits) is
           * smaller than what we accept on purpose: openFPGALoader's
           * XVC_client::writeTDI keeps the burst byte count and the index of
           * the final TMS=1 bit in uint16_t, so bursts over 65536 bits wrap:
           * the data pointer stops advancing and TMS rises early, which
           * silently loses the end of a bitstream (DONE=0, no CRC error). */
          int l = snprintf(info, sizeof info, "xvcServer_v1.0:%d\n", XVC_ADVERTISED_BYTES);
          send(c, info, (size_t)l, 0);
        } else if (cmd == XVC_SETTCK) {
          uint32_t half = (xp.settck_period_ns + 8) / 16; /* ns -> half periods of 8 ns */
          if (half < min_half)
            half = min_half; /* never faster than the configured safe TCK (issue 0054) */
          j.half = half;
          uint32_t actual = half * 16;
          uint8_t r[4] = {(uint8_t)actual, (uint8_t)(actual >> 8), (uint8_t)(actual >> 16), (uint8_t)(actual >> 24)};
          send(c, r, 4, 0);
        } else if (cmd == XVC_SHIFT) {
          if (jtag_shift(&j, xp.shift_bits, xp.tms, xp.tdi, tdo) < 0) {
            fprintf(stderr, "xvc: shift of %u bits failed; dropping the client\n", xp.shift_bits);
            fail = 1;
            break;
          }
          send(c, tdo, (xp.shift_bits + 7) / 8, 0);
        } else {
          if (xp.len >= 10 && memcmp(xp.buf, "shift:", 6) == 0)
            fprintf(stderr, "xvc: shift of %u bits is over the %u-bit limit; dropping the client\n",
                    (unsigned)xp.buf[6] | (unsigned)xp.buf[7] << 8 | (unsigned)xp.buf[8] << 16 |
                        (unsigned)xp.buf[9] << 24, XVC_MAX_BYTES * 8);
          else
            fprintf(stderr, "xvc: protocol error; dropping the client\n");
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

/* ------------------------------------------------------------- JTAG speed */
/* dutctl jtag-speed (issue 0054): sweep the octopus TCK from slow to the
 * minimum half period of 2 with read-only probes (IDCODE after reset, BYPASS
 * random / all-0 / all-1 DR shifts) and recommend half of the fastest
 * error-free frequency. */
static int cmd_jtag_speed(int argc, char **argv)
{
  static const char *const use =
      "usage: dutctl jtag-speed IP [DUT] | NAME  [--kbd] [--reps N] [--save] [--from HALF] [--to HALF]\n"
      "                        [--tolerate N] [-v]\n"
      "  sweeps the TCK half period (clk_sys cycles of 8 ns) from HALF (default 50, 1.25 MHz) down\n"
      "  to --to (default 2, 31.25 MHz); each step runs N probes (default 200): TAP reset + IDCODE\n"
      "  compare, BYPASS random-pattern / all-0 / all-1 DR shifts checked against the chain length.\n"
      "  Read-only (IDCODE and BYPASS only). Recommends f_max / 2; --save stores it as tck_half\n"
      "  (kbd_tck_half with --kbd) in the per-DUT configuration. --tolerate N: a step passes with\n"
      "  up to N failing probes (default 0). -v: positions of the wrong bits\n"
      "  (id+N / dr+N = bit N of the IDCODE window / DR shift, (received value)).\n";
  target_t t;
  int used = resolve_target("jtag-speed", argc, argv, &t);
  if (used < 0)
    return fputs(argc < 1 ? use : "", stderr), 2;
  int kbd = 0, save = 0, verbose = 0;
  long reps = 200, from = js_steps[0], to = 2, tolerate = 0;
  for (int i = used; i < argc; i++) {
    if (!strcmp(argv[i], "--kbd")) kbd = 1;
    else if (!strcmp(argv[i], "--save")) save = 1;
    else if (!strcmp(argv[i], "-v") || !strcmp(argv[i], "--verbose")) verbose = 1;
    else if (!strcmp(argv[i], "--reps") && i + 1 < argc) reps = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--tolerate") && i + 1 < argc) tolerate = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--from") && i + 1 < argc) from = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--to") && i + 1 < argc) to = strtol(argv[++i], NULL, 0);
    else return fprintf(stderr, "dutctl jtag-speed: unknown option %s\n%s", argv[i], use), 2;
  }
  if (reps < 1 || from < 2 || to < 2 || to > from || tolerate < 0)
    return fprintf(stderr, "dutctl jtag-speed: need --reps >= 1 and 2 <= --to <= --from\n"), 2;
  if (!t.ip[0])
    return fprintf(stderr, "dutctl jtag-speed: no supervisor ip for %s\n", argv[0]), 2;
  if (t.cfg && t.cfg->jtag == DC_JTAG_USB && !kbd)
    return fprintf(stderr, "dutctl jtag-speed: DUT %s uses USB JTAG; the probe measures the octopus path "
                           "(set usb_freq for the adaptor instead)\n", t.cfg->name), 2;
  /* steps: --from, then the standard steps strictly between, down to --to */
  int steps[64], nsteps = 0;
  steps[nsteps++] = (int)from;
  for (int i = 0; i < js_nsteps; i++)
    if (js_steps[i] < from && js_steps[i] >= to)
      steps[nsteps++] = js_steps[i];

  jtag_ctx_t j;
  if (jtag_open(&j, &t, kbd, (uint32_t)steps[0]) < 0)
    return 1;
  static js_probe_t p;
  static uint8_t ref[JS_MAX_BITS / 8], tdo[JS_MAX_BITS / 8];
  uint32_t seed = (uint32_t)rand() | 1;
  const char *what = kbd ? "keyboard CPLD" : "DUT";

  /* 1. reference at the slowest step, repeated to make sure it is stable */
  js_build(&p, seed++);
  if (jtag_shift(&j, p.bits, p.tms, p.tdi, ref) < 0)
    return 1;
  int n = js_chain_len(&p, ref, JS_MAX_CHAIN);
  uint32_t ids[16];
  int nid = js_idcodes(&p, ref, ids, 16);
  if (n < 0) {
    int ones = 0;
    for (uint32_t i = 0; i < p.dr_bits; i++)
      ones += (ref[(p.dr_at + i) / 8] >> ((p.dr_at + i) % 8)) & 1;
    fprintf(stderr, "dutctl jtag-speed: no working chain to the %s at %.2f MHz: the BYPASS pattern did "
                    "not come back (TDO %s)\n", what, js_freq_hz(steps[0]) / 1e6,
            ones == 0 ? "stuck at 0" : ones == (int)p.dr_bits ? "stuck at 1" : "noisy");
    return 1;
  }
  if (n == 0 || nid == 0)
    return fprintf(stderr, "dutctl jtag-speed: TDO follows TDI with no delay: no device on the chain\n"), 1;
  printf("%s %s%s%s%s: %d device%s in the chain, IDCODE", what, t.ip, t.cfg ? " (" : "",
         t.cfg ? t.cfg->name : "", t.cfg ? ")" : "", n, n == 1 ? "" : "s");
  for (int i = 0; i < nid; i++)
    printf(ids[i] ? " 0x%08x" : " (bypass-only)", ids[i]);
  printf("  (reference at half %d, %.2f MHz)\n", steps[0], js_freq_hz(steps[0]) / 1e6);
  for (int r = 0; r < 4; r++) {
    js_errs_t e;
    js_build(&p, seed++);
    if (jtag_shift(&j, p.bits, p.tms, p.tdi, tdo) < 0)
      return 1;
    if (js_check(&p, tdo, ref, n, &e))
      return fprintf(stderr, "dutctl jtag-speed: the chain is not stable even at the slowest step "
                             "(half %d); check the cabling\n", steps[0]), 1;
  }

  /* 2. sweep */
  int pass[64];
  printf("  half   TCK MHz   result (%ld probes of %u bits each)\n", reps, p.bits);
  for (int s = 0; s < nsteps && !g_stop; s++) {
    j.half = (uint32_t)steps[s];
    long bad = 0;
    js_errs_t tot = {0};
    for (long r = 0; r < reps && !g_stop; r++) {
      js_errs_t e;
      js_build(&p, seed++);
      if (jtag_shift(&j, p.bits, p.tms, p.tdi, tdo) < 0)
        return 1;
      if (js_check(&p, tdo, ref, n, &e)) {
        bad++;
        if (verbose) {
          uint32_t pos[8];
          int k = js_errpos(&p, tdo, ref, n, pos, 8);
          printf("        probe %ld: %u wrong bit%s, at", r, e.id_err + e.rand_err + e.zero_err + e.one_err,
                 e.id_err + e.rand_err + e.zero_err + e.one_err == 1 ? "" : "s");
          for (int q = 0; q < k; q++) {
            uint32_t b = pos[q];
            int got = (tdo[b / 8] >> (b % 8)) & 1;
            if (b < p.dr_at)
              printf(" id+%u(%d)", b - p.id_at, got);
            else {
              /* expected / received around the bit, oldest first */
              char ex[12], rx[12];
              int m = 0;
              for (int o = -4; o <= 4; o++, m++) {
                uint32_t q2 = b + (uint32_t)o, src = q2 - (uint32_t)n;
                ex[m] = (char)('0' + ((p.tdi[src / 8] >> (src % 8)) & 1));
                rx[m] = (char)('0' + ((tdo[q2 / 8] >> (q2 % 8)) & 1));
              }
              ex[m] = rx[m] = 0;
              printf(" dr+%u(%d; expected %s got %s)", b - p.dr_at, got, ex, rx);
            }
          }
          printf("\n");
        }
        tot.id_err += e.id_err;
        tot.rand_err += e.rand_err;
        tot.zero_err += e.zero_err;
        tot.one_err += e.one_err;
      }
    }
    pass[s] = bad <= tolerate;
    printf("  %4d  %8.3f   ", steps[s], js_freq_hz(steps[s]) / 1e6);
    if (!bad)
      printf("ok\n");
    else if (pass[s])
      printf("ok within --tolerate: %ld/%ld probes (bit errors: idcode %u, random %u, all-0 %u, all-1 %u)\n",
             bad, reps, tot.id_err, tot.rand_err, tot.zero_err, tot.one_err);
    else
      printf("FAIL %ld/%ld probes (bit errors: idcode %u, random %u, all-0 %u, all-1 %u)\n", bad, reps,
             tot.id_err, tot.rand_err, tot.zero_err, tot.one_err);
    fflush(stdout);
  }
  if (g_stop)
    return 130;

  /* 3. recommendation, with the steps of this sweep */
  int fmax;
  int rec = js_recommend(steps, pass, nsteps, &fmax);
  if (fmax < 0) {
    fprintf(stderr, "dutctl jtag-speed: even half %d failed; nothing recommended.\n", steps[0]);
    int later = 0;
    for (int s = 1; s < nsteps; s++)
      later += pass[s];
    if (later)
      fprintf(stderr, "  Faster steps passed too, so the errors do not depend on TCK: a noise / signal\n"
                      "  integrity problem rather than a speed limit (-v shows the wrong bits). The\n"
                      "  fastest clean step bounds the timing; --tolerate N accepts N failing probes\n"
                      "  per step to get a recommendation regardless.\n");
    return 1;
  }
  int first_fail = fmax + 1 < nsteps ? steps[fmax + 1] : 0;
  printf("f_max: half %d = %.3f MHz (%s)\n", steps[fmax], js_freq_hz(steps[fmax]) / 1e6,
         first_fail ? "the next step failed" : "the fastest step tested; the real limit may be higher");
  printf("recommended: tck_half %d = %.3f MHz (margin %.1fx below f_max)\n", rec, js_freq_hz(rec) / 1e6,
         (double)rec / steps[fmax]);

  /* 4. IDCODE at the recommended speed */
  j.half = (uint32_t)rec;
  js_build(&p, seed++);
  js_errs_t e;
  if (jtag_shift(&j, p.bits, p.tms, p.tdi, tdo) < 0)
    return 1;
  uint32_t idr[16];
  int nr = js_idcodes(&p, tdo, idr, 16);
  int ok = js_check(&p, tdo, ref, n, &e) == 0;
  printf("check at half %d: %s, IDCODE 0x%08x\n", rec, ok ? "ok" : "FAILED", nr ? idr[0] : 0);
  if (!ok)
    return 1;

  if (save) {
    char sec[96];
    if (t.cfg)
      snprintf(sec, sizeof sec, "%s", t.cfg->name);
    else
      dc_auto_name(sec, sizeof sec, t.ip, t.dut);
    char hv[16], dv[16];
    snprintf(hv, sizeof hv, "%d", rec);
    snprintf(dv, sizeof dv, "%d", t.dut);
    const char *secs[3] = {sec, sec, sec};
    const char *keys[3] = {kbd ? "kbd_tck_half" : "tck_half", "ip", "dut"};
    const char *vals[3] = {hv, t.ip, dv};
    int ne = t.cfg ? 1 : (t.dut >= 0 ? 3 : 2); /* new section: record where it is */
    if (dc_update_file(conf_path(), ne, secs, keys, vals) < 0)
      return fprintf(stderr, "dutctl jtag-speed: writing %s failed: %s\n", conf_path(), strerror(errno)), 1;
    printf("saved [%s] %s = %d in %s\n", sec, keys[0], rec, conf_path());
  }
  return 0;
}

/* ------------------------------------------------------------- relays */
/* One relay controller command; prints the reply unless quiet. Returns 0
 * when the controller answered OK. */
static int relay_run(const char *tty, int argc, char **argv, int quiet)
{
  int fd = open(tty, O_RDWR | O_NOCTTY);
  if (fd < 0) {
    perror(tty);
    return 1;
  }
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
  static int bump;
  int id = (int)(((unsigned long)tv.tv_sec * 1000003UL + (unsigned long)tv.tv_usec * 7919UL +
                  (unsigned long)getpid() * 104729UL + (unsigned long)bump++ * 31UL) % 99999UL) + 1;
  int l = snprintf(line, sizeof line, "#%d", id);
  for (int i = 0; i < argc; i++)
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
        rc = strncmp(resp + strlen(tag), "OK", 2) ? 1 : 0;
        if (!quiet || rc)
          printf("%s\n", resp + strlen(tag));
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

/* out-policy for one hooked DUT; returns 0 when acknowledged */
static int relay_hook_policy(const dc_dut_t *d, uint8_t pol, const char *why)
{
  if (!d->ip[0]) {
    printf("DUT %s: no ip in %s, out-policy %u not set (%s)\n", d->name, conf_path(), pol, why);
    return 1;
  }
  printf("DUT %s (%s): out-policy %u (%s) %s\n", d->name, d->ip, pol,
         pol == DP_OUTPOL_OFF ? "outputs off, JTAG included" : "auto", why);
  fflush(stdout);
  if (mgmt_set_q(d->ip, DP_K_OUT_POLICY, &pol, 1, 1)) {
    fprintf(stderr, "  WARNING: out-policy %u on %s not acknowledged\n", pol, d->ip);
    return 1;
  }
  return 0;
}

/* dutctl relay [--raw] TTY COMMAND...: before a relay command cuts a DUT's
 * power, the DUTs mapped to those channels in duts.conf (relay = TTY CH) get
 * out-policy 2, so the supervisor stops driving them (no back-powering,
 * issue 0056); after switching on they get out-policy 0 again. --raw sends
 * the command alone. */
static int cmd_relay(int argc, char **argv)
{
  int raw = 0;
  if (argc > 0 && !strcmp(argv[0], "--raw")) {
    raw = 1;
    argc--;
    argv++;
  }
  if (argc < 2)
    return fprintf(stderr,
                   "usage: dutctl relay [--raw] TTY COMMAND...  (e.g. STATUS, STATUS 3, POWER 3 ON, POWER 1 2 OFF, "
                   "CYCLE 2 3000, ALL OFF)\n"
                   "  POWER .. OFF / ALL OFF / CYCLE first set out-policy 2 on the DUTs that duts.conf maps\n"
                   "  to those channels (relay = TTY CHANNEL); POWER .. ON / CYCLE set out-policy 0 %d ms\n"
                   "  after switching on. --raw: the relay command only.\n",
                   RH_SETTLE_MS),
           2;
  const char *tty = argv[0];
  rh_plan_t p;
  if (raw || !rh_plan(conf(), tty, argc - 1, argv + 1, &p))
    return relay_run(tty, argc - 1, argv + 1, 0);
  const dc_conf_t *c = conf();
  for (int i = 0; i < p.npre; i++)
    relay_hook_policy(&c->d[p.pre[i]], DP_OUTPOL_OFF, "before switching off");
  int rc = relay_run(tty, argc - 1, argv + 1, 0);
  if (rc && p.npre && !p.npost)
    printf("relay command failed: the DUTs above keep out-policy 2 (outputs off); "
           "dutctl set IP out-policy 0 to undo\n");
  if (p.npost) {
    if (rc) {
      printf("relay command failed: out-policy left as it is\n");
      return rc;
    }
    struct timespec ts = {.tv_sec = p.post_delay_ms / 1000, .tv_nsec = (p.post_delay_ms % 1000) * 1000000L};
    while (nanosleep(&ts, &ts) && errno == EINTR)
      ;
    for (int i = 0; i < p.npost; i++)
      relay_hook_policy(&c->d[p.post[i]], DP_OUTPOL_AUTO, "after switching on");
  }
  return rc;
}

/* ------------------------------------------------------------- apply / keeper */
/* Issue 0066: [board DNA] sections of duts.conf, re-applied after a reload. */

/* Send one board's settings to endpoint ip (dut = any), in file order.
 * done gets "name value, ..." (failed ones marked); returns the failures. */
static int board_send(const dc_board_t *b, const char *ip, char *done, size_t cap)
{
  int fails = 0;
  done[0] = 0;
  for (int i = 0; i < b->nset; i++) {
    const dc_set_t *e = &b->set[i];
    uint16_t key, len;
    uint8_t v[DS_MAX_VALUE];
    const char *why;
    size_t l = strlen(done);
    if (ds_encode(e->name, e->value, &key, v, &len, &why) != DS_OK) {
      fprintf(stderr, "dutctl: board %016llx: %s %s: %s\n", b->dna, e->name, e->value, why);
      fails++;
      continue;
    }
    int bad = mgmt_set_q(ip, key, v, len, 1);
    fails += bad;
    if (l + 1 < cap)
      snprintf(done + l, cap - l, "%s%s %s%s", l ? ", " : "", e->name, e->value, bad ? " FAILED" : "");
  }
  return fails;
}

/* The next heartbeat from a board with a usable source address: 0, or -1
 * on timeout / signal / undecodable packet. */
static int hb_next(int fd, int timeout_ms, dp_heartbeat_t *hb, char *ip, size_t ipcap)
{
  uint8_t buf[DP_MAX_PACKET];
  dp_hdr_t h;
  struct sockaddr_in src;
  if (udp_recv(fd, buf, sizeof buf, timeout_ms, NULL, DP_T_HEARTBEAT, &h, &src) < 0)
    return -1;
  if (dp_decode_heartbeat(buf + DP_HDR_LEN, h.length, hb) < 0 || src.sin_addr.s_addr == 0)
    return -1;
  inet_ntop(AF_INET, &src.sin_addr, ip, (socklen_t)ipcap);
  return 0;
}

static int cmd_apply(int argc, char **argv)
{
  double secs = 5;
  int any = 0;
  for (int i = 0; i < argc; i++) {
    if (!strcmp(argv[i], "-t") && i + 1 < argc)
      secs = atof(argv[++i]);
    else if (!strcmp(argv[i], "--any"))
      any = 1;
    else
      return fprintf(stderr,
                     "usage: dutctl [--conf FILE] apply [-t SECONDS] [--any]\n"
                     "  listen for heartbeats (default 5 s) and send each [board DNA] section's\n"
                     "  settings in duts.conf once to that board; exit 1 if any send failed\n"
                     "  (a board not heard is reported, not a failure). Format: dutctl duts --help\n"
                     "  --any: also hear heartbeats sent unicast to this host (default: broadcast\n"
                     "  ones only, so other dutctl commands keep all of theirs)\n"),
             !strcmp(argv[i], "-h") || !strcmp(argv[i], "--help") ? 0 : 2;
  }
  const dc_conf_t *c = conf();
  if (c->nboards == 0) {
    printf("no [board DNA] sections in %s (nothing to apply)\n", conf_path());
    return 0;
  }
  int done[DC_MAX_BOARDS] = {0}, ndone = 0, fails = 0;
  int fd = hb_bind(any);
  signal(SIGINT, on_sig);
  signal(SIGTERM, on_sig);
  double end = now_s() + secs;
  while (!g_stop && ndone < c->nboards && now_s() < end) {
    dp_heartbeat_t hb;
    char ip[32];
    int left = (int)((end - now_s()) * 1000);
    if (hb_next(fd, left > 200 ? 200 : (left > 0 ? left : 1), &hb, ip, sizeof ip) < 0)
      continue;
    const dc_board_t *b = dc_find_board(c, hb.dna);
    if (!b || done[b - c->b])
      continue;
    done[b - c->b] = 1;
    ndone++;
    char what[2048];
    int f = board_send(b, ip, what, sizeof what);
    fails += f;
    printf("board %016llx via %s (boot %08x): %s%s\n", b->dna, ip, hb.boot_id,
           b->nset ? what : "(no settings)", (f || !b->nset) ? "" : " - applied");
    fflush(stdout);
  }
  close(fd);
  for (int i = 0; i < c->nboards; i++)
    if (!done[i])
      printf("board %016llx: not heard within %.1f s (not applied)\n", c->b[i].dna, secs);
  fflush(stdout);
  return fails ? 1 : 0;
}

static volatile sig_atomic_t g_hup;
static void on_hup(int s) { (void)s; g_hup = 1; }

static void keeper_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void keeper_log(const char *fmt, ...)
{
  char ts[32];
  time_t t = time(NULL);
  struct tm tm;
  localtime_r(&t, &tm);
  strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", &tm);
  printf("%s ", ts);
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  printf("\n");
  fflush(stdout);
}

static int cmd_keeper(int argc, char **argv)
{
  double min_iv = 5, max_backoff = 60;
  int any = 0;
  for (int i = 0; i < argc; i++) {
    if (!strcmp(argv[i], "--min-interval") && i + 1 < argc)
      min_iv = atof(argv[++i]);
    else if (!strcmp(argv[i], "--any"))
      any = 1;
    else
      return fprintf(stderr,
                     "usage: dutctl [--conf FILE] keeper [--min-interval SECONDS] [--any]\n"
                     "  long-running: send the [board DNA] settings of duts.conf when a board is\n"
                     "  first heard and again whenever its heartbeat boot id changes (supervisor\n"
                     "  reloaded or reconfigured). At most one send per board per --min-interval\n"
                     "  (default 5 s); failures are retried with backoff up to 60 s. SIGHUP\n"
                     "  re-reads duts.conf and re-applies to every board. One line per action on\n"
                     "  stdout. Hears broadcast heartbeats only unless --any (see dutctl apply -h).\n"
                     "  systemd user unit: sw/dutctl/systemd/dutctl-keeper.service\n"),
             !strcmp(argv[i], "-h") || !strcmp(argv[i], "--help") ? 0 : 2;
  }
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = on_sig;
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGTERM, &sa, NULL);
  sa.sa_handler = on_hup;
  sigaction(SIGHUP, &sa, NULL);
  static kp_t k;
  kp_init(&k, min_iv, max_backoff);
  const dc_conf_t *c = conf();
  keeper_log("keeper: %d board section(s) in %s", c->nboards, conf_path());
  int fd = hb_bind(any);
  while (!g_stop) {
    if (g_hup) {
      g_hup = 0;
      g_conf_loaded = 0;
      c = conf();
      for (int i = 0; i < k.n;)
        if (!dc_find_board(c, k.b[i].dna))
          kp_forget(&k, k.b[i].dna);
        else
          i++;
      kp_invalidate_all(&k);
      keeper_log("keeper: re-read %s: %d board section(s)", conf_path(), c->nboards);
    }
    dp_heartbeat_t hb;
    char ip[32];
    if (hb_next(fd, 500, &hb, ip, sizeof ip) < 0)
      continue;
    const dc_board_t *b = dc_find_board(c, hb.dna);
    if (!b)
      continue;
    const kp_board_t *before = kp_find(&k, hb.dna);
    uint32_t old = before ? before->boot : 0;
    kp_reason_t why = kp_heartbeat(&k, hb.dna, hb.boot_id, now_s());
    if (why == KP_NONE)
      continue;
    char what[2048];
    int f = board_send(b, ip, what, sizeof what);
    kp_done(&k, hb.dna, hb.boot_id, f == 0);
    char reason[64];
    if (why == KP_REBOOT)
      snprintf(reason, sizeof reason, "boot %08x -> %08x", old, hb.boot_id);
    else if (why == KP_RETRY)
      snprintf(reason, sizeof reason, "retry %d, boot %08x", kp_find(&k, hb.dna)->fails, hb.boot_id);
    else
      snprintf(reason, sizeof reason, "%s, boot %08x", kp_reason_name(why), hb.boot_id);
    keeper_log("board %016llx via %s (%s): %s%s", b->dna, ip, reason, b->nset ? what : "(no settings)",
               (f || !b->nset) ? "" : " - applied");
  }
  close(fd);
  keeper_log("keeper: stopped");
  return 0;
}

/* ------------------------------------------------------------- duts */
static int cmd_duts(int argc, char **argv)
{
  if (argc > 0) {
    fprintf(stderr,
            "usage: dutctl [--conf FILE] duts       list the configured DUTs\n"
            "  file: --conf FILE, $DUTCTL_CONF, else $XDG_CONFIG_HOME/dutctl/duts.conf\n"
            "  (~/.config/dutctl/duts.conf). One [name] section per DUT:\n"
            "    ip = A.B.C.D        supervisor endpoint (octopus JTAG)\n"
            "    dut = 0|1           endpoint index (optional)\n"
            "    jtag = octopus|usb\n"
            "    tck_half = N        octopus TCK half period (dutctl jtag-speed --save)\n"
            "    kbd_tck_half = N    keyboard CPLD (jtag-speed --kbd --save)\n"
            "    usb_vid = 0403  usb_pid = 6010  usb_serial = S  ftdi_channel = 0\n"
            "    usb_path = 1-2.3  tty = /dev/ttyUSB3  cable = ft2232  usb_freq = HZ\n"
            "    relay = /dev/ttyACM0 3   power path (relay controller tty and channel)\n"
            "  `dutctl jtag-discover` proposes the usb_* keys.\n"
            "  Bench settings per supervisor board (issue 0066; MGMT keys reset on every\n"
            "  reload), keyed by the DNA its heartbeats show (dutctl listen: dna ...):\n"
            "    [board 00124c296998c854]\n"
            "    set = hdmi-owner 1  NAME VALUE as for dutctl set; any number of lines\n"
            "  `dutctl apply` sends them once, `dutctl keeper` after every reload.\n");
    return argc == 1 && (!strcmp(argv[0], "-h") || !strcmp(argv[0], "--help")) ? 0 : 2;
  }
  const dc_conf_t *c = conf();
  if (c->n == 0 && c->nboards == 0) {
    printf("no DUTs configured in %s (dutctl duts --help)\n", conf_path());
    return 0;
  }
  printf("%s:\n", conf_path());
  if (c->n)
    printf("%-16s %-7s %-18s %-14s %s\n", "name", "jtag", "endpoint", "TCK", "adaptor / power");
  for (int i = 0; i < c->n; i++) {
    const dc_dut_t *d = &c->d[i];
    char ep[80], tck[40], extra[400];
    if (d->ip[0])
      snprintf(ep, sizeof ep, d->dut >= 0 ? "%s/%d" : "%s", d->ip, d->dut);
    else
      snprintf(ep, sizeof ep, "-");
    if (d->jtag == DC_JTAG_USB)
      snprintf(tck, sizeof tck, d->usb_freq ? "%.2f MHz" : "default", d->usb_freq / 1e6);
    else if (d->tck_half)
      snprintf(tck, sizeof tck, "%.2f MHz", js_freq_hz(d->tck_half) / 1e6);
    else
      snprintf(tck, sizeof tck, "10.42 MHz dflt");
    extra[0] = 0;
    size_t l = 0;
    if (d->jtag == DC_JTAG_USB)
      l += (size_t)snprintf(extra + l, sizeof extra - l, "%04x:%04x serial %s ch %d%s%s%s%s", d->usb_vid,
                            d->usb_pid, d->usb_serial[0] ? d->usb_serial : "(none)",
                            d->ftdi_channel < 0 ? 0 : d->ftdi_channel, d->tty[0] ? " tty " : "", d->tty,
                            d->usb_path[0] ? " port " : "", d->usb_path);
    if (d->kbd_tck_half && l < sizeof extra)
      l += (size_t)snprintf(extra + l, sizeof extra - l, "%skbd %.2f MHz", l ? "  " : "",
                            js_freq_hz(d->kbd_tck_half) / 1e6);
    if (d->relay_tty[0] && l < sizeof extra)
      snprintf(extra + l, sizeof extra - l, "%srelay %s %d", l ? "  " : "", d->relay_tty, d->relay_ch);
    printf("%-16s %-7s %-18s %-14s %s\n", d->name, d->jtag == DC_JTAG_USB ? "usb" : "octopus", ep, tck,
           extra);
  }
  for (int i = 0; i < c->nboards; i++) {
    const dc_board_t *b = &c->b[i];
    printf("board %016llx:", b->dna);
    for (int j = 0; j < b->nset; j++)
      printf("%s %s %s", j ? "," : "", b->set[j].name, b->set[j].value);
    printf("%s\n", b->nset ? "" : " (no settings)");
  }
  return 0;
}

/* ------------------------------------------------------------- jtag-discover */
/* Run openFPGALoader --detect on one adaptor; fills ids, returns the count
 * (0 = no chain), -1 if it could not be run. */
static int ofl_detect(const char *ofl, const jd_adaptor_t *a, int channel, uint32_t *ids, int max,
                      int verbose)
{
  jd_cmd_t c;
  char bd[32];
  snprintf(bd, sizeof bd, "%03d:%03d", a->busnum, a->devnum); /* serial-less adaptors */
  if (jd_ofl_cmd(&c, ofl, a->cable, a->vid, a->pid, a->serial, bd, channel, 1000000, "detect", 0) < 0)
    return -1;
  if (verbose) {
    char line[1024];
    jd_cmd_str(&c, line, sizeof line);
    fprintf(stderr, "  $ %s\n", line);
  }
  int pfd[2];
  if (pipe(pfd) < 0)
    return -1;
  fflush(stdout);
  pid_t pid = fork();
  if (pid < 0)
    return -1;
  if (pid == 0) {
    dup2(pfd[1], 1);
    dup2(pfd[1], 2);
    close(pfd[0]);
    close(pfd[1]);
    alarm(20);
    execv(c.argv[0], c.argv);
    _exit(127);
  }
  close(pfd[1]);
  static char out[16384];
  size_t ol = 0;
  ssize_t r;
  while ((r = read(pfd[0], out + ol, sizeof out - 1 - ol)) > 0)
    ol += (size_t)r;
  out[ol] = 0;
  close(pfd[0]);
  int st;
  waitpid(pid, &st, 0);
  if (WIFEXITED(st) && WEXITSTATUS(st) == 127)
    return -1;
  return jd_parse_detect(out, ids, max);
}

static void ids_str(const uint32_t *ids, int n, char *buf, size_t cap)
{
  size_t l = 0;
  buf[0] = 0;
  if (n <= 0)
    snprintf(buf, cap, n < 0 ? "(not scanned)" : "no chain");
  for (int i = 0; i < n && l < cap; i++)
    l += (size_t)snprintf(buf + l, cap - l, "%s0x%08x", i ? " " : "", ids[i]);
}

static int cmd_jtag_discover(int argc, char **argv)
{
  static const char *const use =
      "usage: dutctl jtag-discover [--scan] [--all] [--channel N]\n"
      "       dutctl jtag-discover --power-cycle --yes [--dut NAME]... [--wait S] [--write]\n"
      "  lists USB JTAG adaptors (FTDI 0403:6010/6011/6014/6001 incl. TE0790 and Digilent;\n"
      "  the Mimas supervisors 2a19:1009 are excluded) and their ttys from sysfs.\n"
      "  --scan: also read each adaptor's chain with openFPGALoader --detect (FTDI channel\n"
      "  --channel, default 0; libftdi detaches that channel's ttyUSB). FT232R (0403:6001) is\n"
      "  usually a plain serial port (e.g. an Arduino) and is only scanned with --all.\n"
      "  --power-cycle: for each configured DUT with a relay = power path (or each --dut), switch\n"
      "  its power off, wait S seconds (default 3), rescan, and see whose chain disappeared;\n"
      "  then power it back on. Interrupts work on the DUTs, so it needs --yes. The mapping is\n"
      "  written to the configuration after confirmation, or at once with --write.\n";
  int scan = 0, all = 0, pc = 0, yes = 0, write = 0, channel = 0;
  double wait_s = 3;
  const char *only[DC_MAX_DUTS];
  int nonly = 0;
  for (int i = 0; i < argc; i++) {
    if (!strcmp(argv[i], "--scan")) scan = 1;
    else if (!strcmp(argv[i], "--all")) all = 1;
    else if (!strcmp(argv[i], "--power-cycle")) pc = scan = 1;
    else if (!strcmp(argv[i], "--yes")) yes = 1;
    else if (!strcmp(argv[i], "--write")) write = 1;
    else if (!strcmp(argv[i], "--channel") && i + 1 < argc) channel = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--wait") && i + 1 < argc) wait_s = atof(argv[++i]);
    else if (!strcmp(argv[i], "--dut") && i + 1 < argc && nonly < DC_MAX_DUTS) only[nonly++] = argv[++i];
    else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) return fputs(use, stderr), 0;
    else return fprintf(stderr, "dutctl jtag-discover: unknown option %s\n%s", argv[i], use), 2;
  }
  if (channel < 0 || channel > 3)
    return fprintf(stderr, "dutctl jtag-discover: --channel 0..3\n"), 2;
  if (pc && !yes)
    return fprintf(stderr, "dutctl jtag-discover: --power-cycle switches DUTs off and on (interrupting "
                           "their work); add --yes to confirm\n"), 2;
  const char *root = getenv("DUTCTL_SYSFS_USB");
  if (!root || !*root)
    root = "/sys/bus/usb/devices";
  static jd_adaptor_t ad[JD_MAX_ADAPTORS];
  int na = jd_scan(root, ad, JD_MAX_ADAPTORS);
  if (na < 0)
    return fprintf(stderr, "dutctl jtag-discover: cannot read %s\n", root), 1;
  const dc_conf_t *c = conf();
  /* adaptors carrying a configured relay controller are never scanned */
  int skip[JD_MAX_ADAPTORS] = {0};
  for (int i = 0; i < na; i++) {
    for (int k = 0; k < ad[i].nif; k++)
      for (int d = 0; d < c->n; d++) {
        const char *rt = c->d[d].relay_tty;
        const char *b = strrchr(rt, '/');
        if (ad[i].ifs[k].tty[0] && !strcmp(b ? b + 1 : rt, ad[i].ifs[k].tty))
          skip[i] = 1;
      }
    if (!ad[i].cable || (ad[i].pid == 0x6001 && !all))
      skip[i] = skip[i] ? skip[i] : 2;
  }
  printf("%d USB JTAG adaptor%s (%s):\n", na, na == 1 ? "" : "s", root);
  for (int i = 0; i < na; i++) {
    jd_adaptor_t *a = &ad[i];
    printf("  %-10s %04x:%04x  %-32s serial %-14s", a->path, a->vid, a->pid, a->kind,
           a->serial[0] ? a->serial : "(none!)");
    for (int k = 0; k < a->nif; k++)
      printf("  if%d %s%s%s", a->ifs[k].num, a->ifs[k].tty[0] ? "/dev/" : "",
             a->ifs[k].tty[0] ? a->ifs[k].tty : (a->ifs[k].driver[0] ? a->ifs[k].driver : "-"),
             "");
    if (skip[i] == 1)
      printf("  [relay controller: not scanned]");
    printf("\n");
    for (int d = 0; d < c->n; d++)
      if (c->d[d].jtag == DC_JTAG_USB &&
          ((a->serial[0] && !strcmp(c->d[d].usb_serial, a->serial)) ||
           (!a->serial[0] && c->d[d].usb_path[0] && !strcmp(c->d[d].usb_path, a->path))))
        printf("             configured for DUT %s\n", c->d[d].name);
    if (!a->serial[0])
      printf("             warning: no USB serial; it can only be told apart by its USB port (%s)\n", a->path);
  }
  if (!scan)
    return 0;

  const char *ofl = find_ofl();
  if (!ofl)
    return fprintf(stderr, "dutctl jtag-discover: openFPGALoader not found (PATH, $DUTCTL_OPENFPGALOADER): "
                           "chains cannot be scanned. Without it, map adaptors by hand (dutctl duts --help) "
                           "or unplug them one at a time and compare this listing.\n"), 1;
  static uint32_t base[JD_MAX_ADAPTORS][8];
  int nbase[JD_MAX_ADAPTORS];
  printf("chains (openFPGALoader --detect, FTDI channel %d):\n", channel);
  for (int i = 0; i < na; i++) {
    nbase[i] = skip[i] ? -1 : ofl_detect(ofl, &ad[i], channel, base[i], 8, 0);
    char s[160];
    ids_str(base[i], nbase[i], s, sizeof s);
    printf("  %-10s %s\n", ad[i].path, skip[i] == 2 ? "(skipped: no openFPGALoader cable, or an FT232R without --all)" : s);
  }
  if (!pc)
    return 0;

  /* DUTs to cycle */
  int sel[DC_MAX_DUTS], ns = 0;
  for (int d = 0; d < c->n; d++) {
    int want = nonly == 0;
    for (int k = 0; k < nonly; k++)
      want |= !strcmp(only[k], c->d[d].name);
    if (!want)
      continue;
    if (!c->d[d].relay_tty[0]) {
      if (nonly)
        fprintf(stderr, "dutctl jtag-discover: DUT %s has no relay = TTY CHANNEL power path; skipped\n",
                c->d[d].name);
      continue;
    }
    sel[ns++] = d;
  }
  for (int k = 0; k < nonly; k++)
    if (!dc_find_name(c, only[k]))
      fprintf(stderr, "dutctl jtag-discover: no DUT %s in %s\n", only[k], conf_path());
  if (!ns)
    return fprintf(stderr, "dutctl jtag-discover: no DUT with a power path (relay = TTY CHANNEL) to "
                           "cycle\n"), 1;
  int map[DC_MAX_DUTS];
  for (int s = 0; s < ns && !g_stop; s++) {
    const dc_dut_t *d = &c->d[sel[s]];
    char ch[16];
    snprintf(ch, sizeof ch, "%d", d->relay_ch);
    char *off[] = {"POWER", ch, "OFF"}, *on[] = {"POWER", ch, "ON"};
    map[s] = -1;
    printf("DUT %s: power off (relay %s %d)\n", d->name, d->relay_tty, d->relay_ch);
    fflush(stdout);
    if (relay_run(d->relay_tty, 3, off, 1)) {
      fprintf(stderr, "  power off failed; skipped\n");
      continue;
    }
    usleep((useconds_t)(wait_s * 1e6));
    int gone[JD_MAX_ADAPTORS], ngone = 0;
    for (int i = 0; i < na; i++) {
      gone[i] = 0;
      if (nbase[i] <= 0)
        continue;
      uint32_t ids[8];
      int r = ofl_detect(ofl, &ad[i], channel, ids, 8, 0);
      if (r == 0 || (r > 0 && (r != nbase[i] || memcmp(ids, base[i], sizeof ids[0] * (size_t)r)))) {
        gone[i] = 1;
        ngone++;
      }
    }
    printf("DUT %s: power on\n", d->name);
    fflush(stdout);
    if (relay_run(d->relay_tty, 3, on, 1))
      fprintf(stderr, "  WARNING: power on failed: dutctl relay %s POWER %d ON\n", d->relay_tty, d->relay_ch);
    usleep((useconds_t)(wait_s * 1e6));
    for (int i = 0; i < na; i++)
      if (gone[i]) {
        uint32_t ids[8];
        int r = ofl_detect(ofl, &ad[i], channel, ids, 8, 0);
        printf("  adaptor %s: chain went away%s\n", ad[i].path, r == nbase[i] ? " and came back" : ", NOT back yet");
        if (ngone == 1)
          map[s] = i;
      }
    if (ngone == 0)
      printf("  no adaptor's chain changed (the DUT is on the octopus, unpowered already, or its adaptor "
             "is powered by the target)\n");
    else if (ngone > 1)
      printf("  %d adaptors changed: ambiguous, not mapped\n", ngone);
  }
  /* proposal */
  int nmap = 0;
  printf("proposed mapping:\n");
  for (int s = 0; s < ns; s++) {
    if (map[s] < 0)
      continue;
    const jd_adaptor_t *a = &ad[map[s]];
    const char *tty = "";
    for (int k = 0; k < a->nif; k++)
      if (a->ifs[k].num != channel && a->ifs[k].tty[0])
        tty = a->ifs[k].tty; /* the adaptor's other channel = the DUT's UART (TE0790) */
    printf("  [%s] jtag = usb, %04x:%04x serial %s channel %d port %s%s%s\n", c->d[sel[s]].name, a->vid,
           a->pid, a->serial[0] ? a->serial : "(none)", channel, a->path, tty[0] ? " tty /dev/" : "", tty);
    nmap++;
  }
  if (!nmap)
    return printf("  (none)\n"), 1;
  if (!write) {
    if (!isatty(0))
      return printf("not written (rerun with --write, or interactively)\n"), 0;
    printf("write %d mapping%s to %s? [y/N] ", nmap, nmap == 1 ? "" : "s", conf_path());
    fflush(stdout);
    char ans[16] = "";
    if (!fgets(ans, sizeof ans, stdin) || (ans[0] != 'y' && ans[0] != 'Y'))
      return printf("not written\n"), 0;
  }
  static const char *secs[DC_MAX_DUTS * 9], *keys[DC_MAX_DUTS * 9], *vals[DC_MAX_DUTS * 9];
  static char vbuf[DC_MAX_DUTS * 9][160];
  int ne = 0;
  for (int s = 0; s < ns; s++) {
    if (map[s] < 0)
      continue;
    const jd_adaptor_t *a = &ad[map[s]];
    const char *tty = "";
    for (int k = 0; k < a->nif; k++)
      if (a->ifs[k].num != channel && a->ifs[k].tty[0])
        tty = a->ifs[k].tty;
#define KV(K, ...)                                                                                     \
  do {                                                                                                 \
    secs[ne] = c->d[sel[s]].name;                                                                      \
    keys[ne] = K;                                                                                      \
    snprintf(vbuf[ne], sizeof vbuf[0], __VA_ARGS__);                                                   \
    vals[ne] = vbuf[ne];                                                                               \
    ne++;                                                                                              \
  } while (0)
    KV("jtag", "usb");
    KV("usb_vid", "%04x", a->vid);
    KV("usb_pid", "%04x", a->pid);
    if (a->serial[0])
      KV("usb_serial", "%s", a->serial);
    KV("ftdi_channel", "%d", channel);
    KV("usb_path", "%s", a->path);
    KV("cable", "%s", a->cable);
    if (tty[0])
      KV("tty", "/dev/%s", tty);
#undef KV
  }
  if (dc_update_file(conf_path(), ne, secs, keys, vals) < 0)
    return fprintf(stderr, "dutctl jtag-discover: writing %s failed: %s\n", conf_path(), strerror(errno)), 1;
  printf("written to %s\n", conf_path());
  return 0;
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
          "  dutctl apply [-t SECONDS]         send duts.conf [board DNA] settings to the boards heard\n"
          "  dutctl keeper [--min-interval S]  re-apply them on every supervisor reload (boot id change)\n"
          "  dutctl mgmt IP KEY [HEXVALUE] [--cmd-id N] [--dut N]   raw MGMT_SET\n"
          "  dutctl kbd IP [KEY ...]           keys by name (A, RETURN, F1...) or matrix number\n"
          "  dutctl uart IP [--baud N] [--clear] [--from-start]\n"
          "  dutctl jtag-idcode IP [DUT] | NAME [--kbd] [--half N] [--exec]\n"
          "                                    (--kbd: the physical keyboard's CPLD)\n"
          "  dutctl xvc IP [DUT] | NAME [--port 2542] [--kbd] [--half N] [--exec]\n"
          "  dutctl jtag-speed IP [DUT] | NAME [--kbd] [--reps N] [--save] [--from H] [--to H]\n"
          "  dutctl duts [--help]              configured DUTs (per-DUT JTAG setup)\n"
          "  dutctl jtag-discover [--scan] [--all] [--power-cycle --yes [--dut NAME]... [--write]]\n"
          "  dutctl relay [--raw] TTY COMMAND...\n"
          "  dutctl text IP [--screen N] [--fg N] [--bg N] [--force] [--jumbo] [--file F | LINE ...]\n"
          "  dutctl video IP [--frames N] [--out PREFIX] [--enable] [--require-complete]\n"
          "  dutctl thumbs IFACE [--out PREFIX] [--pictures N] [--request] [--force IP] [--scale 1|2]\n"
          "  dutctl screenshot [IP|DIGIT] [-o FILE.png|.ppm] [--screen auto|editable|novideo|select]\n"
          "                    [--timeout S]     one frame from a video target (alias: dutctl -S)\n"
          "  global options: --conf FILE  (default $DUTCTL_CONF, else ~/.config/dutctl/duts.conf)\n"
          "                  --mtu N      path MTU to the supervisors (default $DUTCTL_MTU, else 1500);\n"
          "                               JTAG shifts are split to fit one unfragmented packet\n"
          "                               (1500: 5792 bits per request; >= 2028: 7904, the maximum)\n");
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
                           "         [--request] [--force IP] [--scale 1|2] [--div N] [--vlan VID]\n"
                           "  writes PREFIX-mNN.ppm (default prefix 'thumb') for each machine's latest\n"
                           "  complete thumbnail; --request broadcasts requests every 250 ms, --force IP\n"
                           "  points that board's relay at this interface (key 0x0041). Needs CAP_NET_RAW.\n"
                           "  Boards answer requests only on their relay VLAN (key 0x0043, default 1650):\n"
                           "  --vlan VID tags the requests (0 = untagged); --force needs no VLAN.\n"
                           "  With a host VLAN (key 0x0046, issue 0062) use the VLAN interface (e.g.\n"
                           "  eno2.1650): the kernel removes/adds the tag, so --vlan is then only for\n"
                           "  a relay VLAN other than the interface's.\n"),
           2;
  const char *ifname = argv[0], *prefix = "thumb", *force_ip = NULL;
  long want = 0, timeout_s = 10;
  int request = 0, scale = DP_TH_SCALE_HALF, div = 2, vlan = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--out") && i + 1 < argc) prefix = argv[++i];
    else if (!strcmp(argv[i], "--pictures") && i + 1 < argc) want = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--timeout") && i + 1 < argc) timeout_s = strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--request")) request = 1;
    else if (!strcmp(argv[i], "--force") && i + 1 < argc) force_ip = argv[++i];
    else if (!strcmp(argv[i], "--scale") && i + 1 < argc) scale = (int)strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--div") && i + 1 < argc) div = (int)strtol(argv[++i], NULL, 0);
    else if (!strcmp(argv[i], "--vlan") && i + 1 < argc) vlan = (int)strtol(argv[++i], NULL, 0);
    else return fprintf(stderr, "dutctl thumbs: unknown option %s\n", argv[i]), 2;
  }
  if ((scale != 1 && scale != 2) || div < 1 || div > 15 || vlan < 0 || vlan > 4094)
    return fprintf(stderr, "dutctl thumbs: --scale 1 or 2, --div 1..15, --vlan 0..4094\n"), 2;
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
      size_t o = 12;
      if (vlan) { /* 802.1Q tag, PCP 0 (issue 0060) */
        dp_put16(f + 12, 0x8100);
        dp_put16(f + 14, (uint16_t)vlan);
        o = 16;
      }
      dp_put16(f + o, DP_ETH_THUMB);
      dp_encode_thumb_request(f + o + 2, (uint8_t)scale, (uint8_t)div);
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
    if (n >= 18 && dp_get16(buf + 12) == 0x8100) { /* tag left in place: drop it */
      memmove(buf + 12, buf + 16, (size_t)n - 16);
      n -= 4;
    }
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
    if (t.width > DP_TH_MAX_W || t.height > DP_TH_MAX_H) /* 1/1 pictures (issue 0060): not stored here */
      continue;
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
  const char *em = getenv("DUTCTL_MTU");
  if (em && *em && set_mtu(em, "DUTCTL_MTU") < 0)
    return 2;
  /* global --conf FILE / --mtu N, anywhere on the line */
  for (int i = 1; i < argc; i++)
    if ((!strcmp(argv[i], "--conf") || !strcmp(argv[i], "--mtu")) && i + 1 < argc) {
      if (argv[i][2] == 'm') {
        if (set_mtu(argv[i + 1], "--mtu") < 0)
          return 2;
      } else
        g_conf_arg = argv[i + 1];
      memmove(argv + i, argv + i + 2, sizeof argv[0] * (size_t)(argc - i - 1)); /* incl. NULL */
      argc -= 2;
      i--;
    }
  if (argc < 2) {
    usage();
    return 2;
  }
  const char *c = argv[1];
  argc -= 2;
  argv += 2;
  if (!strcmp(c, "listen")) return cmd_listen(argc, argv);
  if (!strcmp(c, "set")) return cmd_set(argc, argv);
  if (!strcmp(c, "apply")) return cmd_apply(argc, argv);
  if (!strcmp(c, "keeper")) return cmd_keeper(argc, argv);
  if (!strcmp(c, "mgmt")) return cmd_mgmt(argc, argv);
  if (!strcmp(c, "kbd")) return cmd_kbd(argc, argv);
  if (!strcmp(c, "uart")) return cmd_uart(argc, argv);
  if (!strcmp(c, "jtag-idcode")) return cmd_jtag_idcode(argc, argv);
  if (!strcmp(c, "xvc")) return cmd_xvc(argc, argv);
  if (!strcmp(c, "jtag-speed")) return cmd_jtag_speed(argc, argv);
  if (!strcmp(c, "jtag-discover")) return cmd_jtag_discover(argc, argv);
  if (!strcmp(c, "duts")) return cmd_duts(argc, argv);
  if (!strcmp(c, "relay")) return cmd_relay(argc, argv);
  if (!strcmp(c, "text")) return cmd_text(argc, argv);
  if (!strcmp(c, "video")) return cmd_video(argc, argv);
  if (!strcmp(c, "thumbs")) return cmd_thumbs(argc, argv);
  if (!strcmp(c, "screenshot") || !strcmp(c, "-S")) return cmd_screenshot(argc, argv);
  usage();
  return 2;
}
