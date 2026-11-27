/* USB JTAG adaptor discovery (issue 0053): a sysfs walk over
 * /sys/bus/usb/devices (root passed in, so tests use a fake tree), the
 * openFPGALoader command line for an adaptor, and parsing of its --detect
 * output.
 *
 * LGPL-2.1-or-later. */
#ifndef JTAGDISC_H
#define JTAGDISC_H

#include <stdint.h>

#define JD_MAX_IFS 8
#define JD_MAX_ADAPTORS 32

typedef struct {
  int num;         /* bInterfaceNumber = FTDI channel (0 = A) */
  char driver[32]; /* bound kernel driver ("" = none, e.g. detached by libftdi) */
  char tty[32];    /* "ttyUSB3" etc., "" if none */
} jd_iface_t;

typedef struct {
  char path[64]; /* sysfs name = USB port path, e.g. "1-2.3" */
  unsigned vid, pid;
  int busnum, devnum;
  char serial[64], manufacturer[64], product[64];
  const char *kind; /* human-readable adaptor kind */
  const char *cable; /* openFPGALoader cable, NULL if unsupported */
  int nif;
  jd_iface_t ifs[JD_MAX_IFS];
} jd_adaptor_t;

/* Adaptor kind for a device, or NULL if it is not a JTAG adaptor we know
 * (the Mimas supervisor 2a19:1009 is deliberately excluded). *cable gets
 * the openFPGALoader cable name (NULL if openFPGALoader cannot drive it). */
const char *jd_classify(unsigned vid, unsigned pid, const char *manufacturer, const char *product,
                        const char **cable);

/* Walk root (normally "/sys/bus/usb/devices") and fill out[] with the JTAG
 * adaptors, sorted by path. Returns the count (<= max), -1 if root cannot
 * be opened. */
int jd_scan(const char *root, jd_adaptor_t *out, int max);

/* The tty of interface num ("" if none). */
const char *jd_tty(const jd_adaptor_t *a, int num);

/* IDCODEs listed in openFPGALoader --detect output ("idcode 0x..."), with
 * 0 and 0xffffffff (no target / floating TDO) dropped. Returns the count. */
int jd_parse_detect(const char *out, uint32_t *ids, int max);

/* An openFPGALoader command line. */
typedef struct {
  int argc;
  char *argv[24];
  char store[24][160];
} jd_cmd_t;

/* Build: OFL -c CABLE [--ftdi-serial S | --busdev-num BUSDEV | --vid V --pid P]
 * [--ftdi-channel N] [--freq F] MODE... where mode is "detect" (--detect) or
 * "xvc" (--xvc --port PORT). busdev ("BBB:DDD") is used only without a serial
 * (NULL = none). Returns 0, -1 if no cable is known. */
int jd_ofl_cmd(jd_cmd_t *c, const char *ofl, const char *cable, unsigned vid, unsigned pid,
               const char *serial, const char *busdev, int channel, long freq, const char *mode, int port);

/* Render argv as a shell-quoted line. */
void jd_cmd_str(const jd_cmd_t *c, char *buf, unsigned cap);

#endif
