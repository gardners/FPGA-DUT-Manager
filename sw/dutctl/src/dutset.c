/* Named management settings -> MGMT key/value (issue 0066). LGPL-2.1-or-later. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "dutset.h"

#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dutproto.h"

#define DS_RGB 12 /* kbd-led-rgb */
#define DS_MAC 6
#define DS_IP (-4)

static const struct {
  const char *name;
  uint16_t key;
  int len; /* 1, 2, 4 numeric; DS_MAC; DS_IP; DS_RGB */
} tab[] = {
    {"mac", DP_K_MAC, DS_MAC}, {"ip", DP_K_IP, DS_IP}, {"dhcp", DP_K_DHCP_EN, 1},
    {"dest-ip", DP_K_DEST_IP, DS_IP}, {"dest-mac", DP_K_DEST_MAC, DS_MAC}, {"baud", DP_K_UART_BAUD, 4},
    {"uart-fast", DP_K_UART_FAST, 1}, {"uart-snap", DP_K_UART_SNAP_EN, 1},
    {"uart-period-us", DP_K_UART_PERIOD, 2}, {"kbd-policy", DP_K_KBD_POLICY, 1},
    {"kbd-override", DP_K_KBD_OVERRIDE, 1}, {"kbd-target", DP_K_KBD_TARGET, 1},
    {"video-target", DP_K_VID_TARGET, 1}, {"coupled", DP_K_COUPLED, 1},
    {"capture", DP_K_CAPTURE_EN, 1}, {"hb-period-ms", DP_K_HB_PERIOD, 2},
    {"out-policy", DP_K_OUT_POLICY, 1}, {"kbd-leds", DP_K_PK_LED_MODE, 1},
    {"console-screen", DP_K_CON_SCREEN, 1}, {"kbd-jtag", DP_K_PK_JTAG, 1},
    {"power-ctl", DP_K_PWR_CTL, 1}, {"kbd-jtag-quiet", DP_K_KJ_QUIET, 1},
    {"jtag-tdo-vote", DP_K_TDO_VOTE, 1}, {"vlan", DP_K_VLAN, 2},
    {"hdmi-owner", DP_K_HDMI_OWNER, 1}, {"host-vlan", DP_K_HOST_VLAN, 2},
    {"relay-view", DP_K_RELAY_VIEW, 1}, {"vlan-base", DP_K_VLAN_BASE, DS_IP},
    {"kbd-led-rgb", DP_K_PK_LED_HOST, DS_RGB},
};

const char *const ds_names[] = {
    "mac", "ip", "dhcp", "dest-ip", "dest-mac", "baud", "uart-fast", "uart-snap", "uart-period-us",
    "kbd-policy", "kbd-override", "kbd-target", "video-target", "coupled", "capture", "hb-period-ms",
    "out-policy", "kbd-leds", "console-screen", "kbd-jtag", "power-ctl", "kbd-jtag-quiet",
    "jtag-tdo-vote", "vlan", "hdmi-owner", "host-vlan", "relay-view", "vlan-base", "kbd-led-rgb", NULL,
};

static int bad(const char **why, const char *msg)
{
  if (why)
    *why = msg;
  return DS_BAD_VALUE;
}

int ds_encode(const char *name, const char *value, uint16_t *key, uint8_t v[DS_MAX_VALUE], uint16_t *vlen,
              const char **why)
{
  if (why)
    *why = "";
  for (size_t i = 0; i < sizeof tab / sizeof tab[0]; i++) {
    if (strcmp(name, tab[i].name))
      continue;
    int len = tab[i].len;
    *key = tab[i].key;
    if (len == DS_RGB) {
      unsigned c[4];
      int n = 0;
      if (sscanf(value, "%6x,%6x,%6x,%6x%n", &c[0], &c[1], &c[2], &c[3], &n) != 4 || value[n])
        return bad(why, "expected RRGGBB,RRGGBB,RRGGBB,RRGGBB");
      for (int l = 0; l < 4; l++) {
        v[3 * l] = (uint8_t)(c[l] >> 16);    /* R */
        v[3 * l + 1] = (uint8_t)(c[l] >> 8); /* G */
        v[3 * l + 2] = (uint8_t)c[l];        /* B */
      }
      *vlen = 12;
      return DS_OK;
    }
    if (len == DS_MAC) {
      unsigned m[6];
      int n = 0;
      if (sscanf(value, "%2x:%2x:%2x:%2x:%2x:%2x%n", &m[0], &m[1], &m[2], &m[3], &m[4], &m[5], &n) != 6 ||
          value[n])
        return bad(why, "bad MAC (expected aa:bb:cc:dd:ee:ff)");
      for (int b = 0; b < 6; b++)
        v[b] = (uint8_t)m[b];
      *vlen = 6;
      return DS_OK;
    }
    if (len == DS_IP) {
      if (inet_pton(AF_INET, value, v) != 1)
        return bad(why, "bad IPv4 address");
      *vlen = 4;
      return DS_OK;
    }
    char *end;
    errno = 0;
    unsigned long long u = strtoull(value, &end, 0);
    if (!*value || *end || errno || value[0] == '-' || value[0] == ' ')
      return bad(why, "not a number");
    if (tab[i].key == DP_K_UART_BAUD) {
      if (u < 1 || u > 100000000ull)
        return bad(why, "baud out of range");
      u = dp_baud_nco((double)u);
    }
    if (u >> (8 * len))
      return bad(why, len == 1 ? "out of range (0..255)"
                      : len == 2 ? "out of range (0..65535)"
                                 : "out of range (32 bits)");
    for (int b = 0; b < len; b++)
      v[b] = (uint8_t)(u >> (8 * (len - 1 - b)));
    *vlen = (uint16_t)len;
    return DS_OK;
  }
  if (why)
    *why = "unknown setting";
  return DS_UNKNOWN_NAME;
}
