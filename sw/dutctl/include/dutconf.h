/* Per-DUT host configuration (issue 0053).
 *
 * File: $DUTCTL_CONF, or --conf FILE, or $XDG_CONFIG_HOME/dutctl/duts.conf
 * (default ~/.config/dutctl/duts.conf). INI-like:
 *
 *   # comment (also ';')
 *   [name]                    one section per DUT
 *   ip = 192.168.1.50         supervisor endpoint IPv4 (octopus JTAG, power)
 *   dut = 0                   endpoint index on that board (0/1; optional)
 *   jtag = octopus | usb      transport (default octopus)
 *   tck_half = 12             octopus TCK half period (clk_sys cycles, >= 2)
 *   kbd_tck_half = 64         same for the physical keyboard CPLD (--kbd)
 *   usb_vid = 0403            USB adaptor (jtag = usb)
 *   usb_pid = 6010
 *   usb_serial = FT1234AB
 *   ftdi_channel = 0          FTDI channel carrying JTAG (0 = A)
 *   usb_path = 1-2.3          sysfs port path (recorded for serial-less clones)
 *   tty = /dev/ttyUSB3        the adaptor's UART to the DUT
 *   cable = ft2232            openFPGALoader cable name (default from vid:pid)
 *   usb_freq = 6000000        openFPGALoader --freq for this adaptor (Hz)
 *   relay = /dev/ttyACM0 3    power path: relay controller tty and channel
 *
 * Per-board bench settings (issue 0066): MGMT keys are volatile, so a
 * supervisor reload (JTAG load, reconfiguration from flash, brown-out)
 * returns them to the build defaults. A board section, keyed by the board's
 * DNA as heartbeats show it (`dna 00124c296998c854`, 1..16 hex digits),
 * lists settings that `dutctl apply` sends to every board heard and that
 * `dutctl keeper` re-applies whenever the board's boot id changes:
 *
 *   [board 00124c296998c854]  one section per supervisor board
 *   set = hdmi-owner 1        NAME VALUE as for `dutctl set IP NAME VALUE`;
 *   set = relay-view 1        any number of lines, sent in file order
 *
 * The board is found from its heartbeats (no ip = key). The settings go to
 * the endpoint whose heartbeat was heard, with dut = any (board-wide keys).
 * [board] without a DNA is an ordinary DUT section named "board".
 *
 * Values run to the end of the line (surrounding blanks trimmed). Writing
 * (dc_text_set) edits the text in place, so comments and unknown keys survive.
 *
 * LGPL-2.1-or-later. */
#ifndef DUTCONF_H
#define DUTCONF_H

#include <stddef.h>

enum { DC_JTAG_OCTOPUS = 0, DC_JTAG_USB = 1 };
#define DC_MAX_DUTS 64

typedef struct {
  char name[64];
  char ip[64];
  int dut;          /* -1 unset */
  int jtag;         /* DC_JTAG_* */
  int tck_half;     /* 0 unset */
  int kbd_tck_half; /* 0 unset */
  unsigned usb_vid, usb_pid; /* 0 unset */
  char usb_serial[64];
  int ftdi_channel; /* -1 unset */
  char usb_path[64];
  char tty[128];
  char cable[64];
  long usb_freq;    /* 0 unset */
  char relay_tty[128];
  int relay_ch;     /* -1 unset */
  int line;         /* line of the [section] header */
} dc_dut_t;

#define DC_MAX_BOARDS 16
#define DC_MAX_SETS 16

typedef struct {
  char name[32];   /* setting name (dutset.h) */
  char value[96];
} dc_set_t;

typedef struct {
  unsigned long long dna;
  int nset;
  dc_set_t set[DC_MAX_SETS];
  int line;        /* line of the [board ...] header */
} dc_board_t;

typedef struct {
  int n;
  dc_dut_t d[DC_MAX_DUTS];
  int nboards;
  dc_board_t b[DC_MAX_BOARDS];
} dc_conf_t;

/* Parse text into c. Problems (unknown key, bad value, duplicate section,
 * key outside a section, unknown setting name or bad setting value in a
 * [board] section) are appended as lines "LINE: message\n" to err
 * (if non-NULL). Returns the number of problems (0 = clean); entries are
 * kept even when some of their keys were bad. */
int dc_parse(const char *text, dc_conf_t *c, char *err, size_t errcap);

/* Read and parse a file. A missing file is an empty configuration (returns
 * 0, *missing = 1). Returns -1 if the file exists but cannot be read,
 * otherwise the number of parse problems. */
int dc_load(const char *path, dc_conf_t *c, char *err, size_t errcap, int *missing);

/* The default path (see above); buf is filled and returned. */
const char *dc_default_path(char *buf, size_t cap);

const dc_dut_t *dc_find_name(const dc_conf_t *c, const char *name);
/* The [board DNA] section for a board DNA, or NULL. */
const dc_board_t *dc_find_board(const dc_conf_t *c, unsigned long long dna);
/* The entry for endpoint ip (and dut index, -1 = any). A wildcard on
 * either side matches; an exact index match wins over a wildcard. */
const dc_dut_t *dc_find_ip(const dc_conf_t *c, const char *ip, int dut);

/* Return a malloc'd copy of text with key in [section] set to value (value
 * NULL removes the key). An existing key line is replaced in place; a new
 * key goes after the section's last key; a missing section is appended at
 * the end. NULL on allocation failure. */
char *dc_text_set(const char *text, const char *section, const char *key, const char *value);

/* Load path (missing = empty), apply n (section, key, value) edits and
 * write it back atomically (tmp + rename, creating the directory). The
 * edits are arrays of n strings each. Returns 0 on success. */
int dc_update_file(const char *path, int n, const char *const *section, const char *const *key,
                   const char *const *value);

/* A section name usable for an endpoint without a configured DUT. */
void dc_auto_name(char *buf, size_t cap, const char *ip, int dut);

/* Default openFPGALoader cable for a vid:pid (NULL if unknown). */
const char *dc_default_cable(unsigned vid, unsigned pid);

#endif
