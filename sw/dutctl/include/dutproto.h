/* dutproto.h - FPGA-DUT-Manager wire protocol v1 (docs/adrs/0005).
 * Mirrors hdl/src/proto/proto_pkg.vhd and tests/netproto.py.
 * All encode/decode is byte-explicit (big-endian); no struct packing.
 * Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later. */
#ifndef DUTPROTO_H
#define DUTPROTO_H

#include <stddef.h>
#include <stdint.h>

#define DP_MAGIC 0x4D36
#define DP_VERSION 1
#define DP_HDR_LEN 8
#define DP_DUT_ANY 0xFF

enum dp_port {
  DP_PORT_MGMT = 6500,
  DP_PORT_HB = 6501,
  DP_PORT_KBD = 6502,
  DP_PORT_UART = 6503,
  DP_PORT_RASTER = 6504,
  DP_PORT_AUDIO = 6505,
  DP_PORT_JTAG = 6507,
  DP_PORT_TEXT = 6508,
};

enum dp_type {
  DP_T_HEARTBEAT = 0x01,
  DP_T_MGMT_SET = 0x10,
  DP_T_MGMT_ACK = 0x11,
  DP_T_KBD_SET = 0x20,
  DP_T_UART_TX = 0x30,
  DP_T_UART_SNAP = 0x31,
  DP_T_JTAG_REQ = 0x40,
  DP_T_JTAG_RESP = 0x41,
  DP_T_TEXT_WRITE = 0x50,
  DP_T_RASTER = 0x60,
};

enum dp_key {
  DP_K_MAC = 0x0001,
  DP_K_IP = 0x0002,
  DP_K_DEST_IP = 0x0003,
  DP_K_DEST_MAC = 0x0004,
  DP_K_IDENTITY = 0x0005,
  DP_K_DHCP_EN = 0x0006,
  DP_K_UART_BAUD = 0x0010,
  DP_K_UART_FAST = 0x0011,
  DP_K_UART_SNAP_EN = 0x0012,
  DP_K_UART_PERIOD = 0x0013,
  DP_K_KBD_POLICY = 0x0020,
  DP_K_KBD_OVERRIDE = 0x0021,
  DP_K_KBD_TARGET = 0x0030,
  DP_K_VID_TARGET = 0x0031,
  DP_K_COUPLED = 0x0032,
  DP_K_PK_LED_MODE = 0x0033, /* physical keyboard LEDs: 0 status, 1 DUT, 2 host */
  DP_K_PK_LED_HOST = 0x0034, /* 12-byte LED vector (LED0 R,G,B .. LED3 R,G,B) */
  DP_K_CON_SCREEN = 0x0035,  /* console screen: 0 auto, 1 editable, 2 no video, 3 select */
  DP_K_CAPTURE_EN = 0x0040,
  DP_K_THUMB_FORCE = 0x0041, /* thumbnail relay to MAC(6) scale(1) div(1); MAC 0 = off */
  DP_K_VLAN = 0x0043,        /* inter-board VLAN ID u16 0..4094 (default 1650, 0 = untagged), issue 0060 */
  DP_K_HDMI_OWNER = 0x0044,  /* HDMI IN owner: 0 follows the video target (default), 1 DUT0,
                                2 DUT1, 3 none (issue 0060) */
  DP_K_RELAY_VIEW = 0x0045,  /* relayed full view: 0 complete pictures (triple buffered),
                                1 live line by line (default), issue 0060 */
  DP_K_HOST_VLAN = 0x0046,   /* host VLAN ID u16 0..4094 (default 0 = untagged): all host traffic
                                tagged with it, host frames accepted only on it (untagged: ARP,
                                ICMP, MGMT still answered), issue 0062 */
  DP_K_VLAN_BASE = 0x0047,   /* VLAN subnet base IPv4 (/24, last octet 0; default 10.231.50.0):
                                the board answers ARP/ping for base + 16 + DIP[7:4] tagged
                                with the key 0x0043 VLAN, issue 0063 */
  DP_K_HB_PERIOD = 0x0050,
  DP_K_OUT_POLICY = 0x0060, /* 0 auto (sense), 1 UART/KIO10 forced on (JTAG follows the
                               sense), 2 all outputs off, JTAG included (issue 0056) */
  DP_K_PK_JTAG = 0x0061, /* physical keyboard CPLD JTAG: 0 auto, 1 force on, 2 force off,
                            3 on with KB_JTAGEN driven low (diagnostic) (ADR 0014) */
  DP_K_PWR_CTL = 0x0062, /* shield power CTRL0..7 bitmask, bit n = power-board output n
                            (issue 0049); board-wide */
  DP_K_KJ_QUIET = 0x0063, /* keyboard JTAG quiet (issue 0054): 0 off, 1 (default) pause the physical
                             keyboard host while keyboard JTAG runs, 2 keyboard host stopped */
  DP_K_TDO_VOTE = 0x0064, /* JTAG TDO sampling, all engines (issue 0054): 0 single sample,
                             1 majority of 3 (half >= 4), 2 majority of 5 (half >= 6) */
};

/* JTAG_REQ flags (offset 18) and JTAG_RESP target (byte 17), ADR 0005 s7 / ADR 0014 */
#define DP_JF_ABORT 0x0001 /* abort / reset session: next seq := seq, nothing clocked */
#define DP_JF_KBD 0x0002   /* target the physical keyboard's CPLD instead of the DUT */
enum dp_jtag_target { DP_JT_DUT = 0, DP_JT_KBD = 1 };
/* out-policy values (key 0x0060) */
enum dp_out_policy { DP_OUTPOL_AUTO = 0, DP_OUTPOL_ON = 1, DP_OUTPOL_OFF = 2 };
/* heartbeat target_flags (byte 40) */
#define DP_TF_KB3V3 0x01
#define DP_TF_VIO 0x02
#define DP_TF_OUT_EN 0x04
#define DP_TF_SENSE_VALID 0x08
#define DP_TF_PWR_HOLD 0x10 /* shield power-off hold: all outputs forced off (issue 0056) */
/* heartbeat capabilities (byte 32) */
#define DP_CAP_KBD_JTAG 0x100
/* heartbeat kbd_phys_type (byte 76) */
enum dp_phys_type { DP_PHYS_NONE = 0, DP_PHYS_MK1, DP_PHYS_MK2, DP_PHYS_TYPE3 };

enum dp_ack_status { DP_ACK_OK = 0, DP_ACK_BAD_KEY, DP_ACK_BAD_LEN, DP_ACK_BAD_VALUE, DP_ACK_DUPLICATE };
enum dp_jtag_status { DP_JS_DONE = 0, DP_JS_BUSY, DP_JS_BAD_SEQ, DP_JS_BAD_FMT, DP_JS_UNPOWERED };

/* Largest JTAG_REQ the supervisor accepts: an RX slot holds 2047 bytes incl.
 * FCS, so the UDP payload is <= 2001 = 8 + 16 + 2 * 988 bytes (issue 0059).
 * Larger requests are answered DP_JS_BAD_FMT. Such a request (2028-byte IP
 * datagram) still needs a path MTU >= 2028; see dp_jtag_max_bits_for_mtu. */
#define DP_JTAG_MAX_BITS 7904
#define DP_JTAG_REQ_FIXED 16 /* JTAG_REQ payload before the vectors */
#define DP_IP_UDP_OVERHEAD 28 /* IPv4 (no options) + UDP headers */
#define DP_MTU_DEFAULT 1500
#define DP_MTU_MIN 576 /* IPv4 minimum reassembly size; smaller MTUs are refused */
#define DP_UART_TX_MAX 1024
#define DP_CLK_HZ 125000000.0
#define DP_MAX_PACKET 2200 /* control plane; raster uses DP_RASTER_MAX_PACKET */
#define DP_RASTER_HDR_LEN 52 /* common 8 + raster 44 (ADR 0005 section 8) */
#define DP_RASTER_VERSION 1
#define DP_RASTER_MAX_PX 1024
#define DP_RASTER_MAX_PACKET (DP_RASTER_HDR_LEN + 3 * DP_RASTER_MAX_PX)

/* raster flags (ADR 0005 section 8) */
enum dp_raster_flag {
  DP_RF_VSYNC = 0x01,
  DP_RF_VSYNC_POL = 0x02,
  DP_RF_HSYNC_POL = 0x04,
  DP_RF_ACTIVE = 0x08,
  DP_RF_FIRST = 0x10,
  DP_RF_DROPPED = 0x20,
  DP_RF_LOCKED = 0x40,
};
enum dp_raster_enc { DP_ENC_RAW = 0, DP_ENC_RLE24 = 1 };

typedef struct {
  uint16_t magic;
  uint8_t version, type;
  uint16_t length; /* payload bytes after the header */
  uint8_t dut, flags;
} dp_hdr_t;

typedef struct {
  uint32_t hb_seq, boot_id, build_id;
  uint64_t dna;
  uint8_t topo_index, topo_count, dip, link_flags;
  uint32_t caps, cfg_gen;
  uint8_t target_flags, kbd_owner, kbd_policy, selected;
  uint8_t kbd_eff[10], kbd_udp[10], kbd_phys[10];
  uint16_t phys_change;
  uint8_t phys_type, jtag_status;
  uint32_t jtag_next_seq, uart_rx_seq, uart_tx_acc;
  uint16_t rx_rejects, tx_drops;
  uint8_t dut_leds[12];
  uint8_t addr_src; /* 0 none, 1 DHCP, 2 fallback, 3 static */
  uint8_t dut_id;
  /* video block (ADR 0005 section 8); valid only when has_video (payload >= 124) */
  uint8_t has_video;
  uint8_t video_flags; /* DP_VF_* bits */
  uint8_t console_screen; /* HDMI OUT shown: DP_CON_* (issues 0029, 0032) */
  uint16_t h_total, v_total, h_active, v_active;
  uint32_t pixel_clock_hz, frames_captured;
  uint16_t raster_lines_dropped, tmds_decode_errors;
  /* link block (ADR 0005 section 3a); valid only when has_link (payload >= 132) */
  uint8_t has_link;
  uint8_t rx_phase_pos;  /* RX sample phase, positions of 5.625 deg from power-up */
  uint8_t rx_eye_width;  /* passing positions in the last hunt (0 = never hunted) */
  uint16_t rx_hunts, rx_bad_frames;
  uint8_t rx_link_flags; /* b0 hunting, b1 RX MMCM locked */
  /* memory block (ADR 0005 section 3b); valid only when has_mem (payload >= 144) */
  uint8_t has_mem;
  uint8_t mem_flags;      /* DP_MEM_* */
  uint16_t mem_errors;    /* self-test words that failed (saturates at 0xFFFF) */
  uint16_t mem_dq_fail;   /* bit i: DDR3 DQ i read a wrong bit */
  uint16_t mem_test_kib;  /* self-test region size, KiB */
  uint32_t mem_first_err; /* word address of the first failing word, 0xFFFFFFFF none */
  /* shield block (ADR 0005 section 3c, issue 0049); valid only when has_shield
     (payload >= 152) */
  uint8_t has_shield;
  uint8_t shd_flags;       /* DP_SF_* */
  uint8_t shd_revision;    /* expander A port 0 straps (valid with DP_SF_PRESENT) */
  uint8_t shd_features;    /* expander A port 1 straps */
  uint8_t shd_sense;       /* b0-3 VIO sense DUT0..3, b4-7 kbd 3V3 sense DUT0..3 (DP_SF_SENSE) */
  uint8_t shd_hdmi;        /* b0-2 +5V HDMI1..3, b3 PK_JTAGEN driven, b4-6 HPD HDMI1..3 */
  uint8_t shd_pwr;         /* power CTRL0..7 as driven */
  uint16_t shd_i2c_errors; /* failed shield I2C transactions (saturates) */
  /* relay block (ADR 0005 section 3d, issue 0061); valid only when has_relay
     (payload >= 180). Board-wide; counters are u16 and wrap. */
  uint8_t has_relay;
  uint16_t rl_req_sent;   /* relay requests sent (any scale) */
  uint16_t rl_req_full;   /* ... of which targeted scale 3 (full view) */
  uint16_t rl_rx_req;     /* requests heard (good FCS, our VLAN, broadcast or ours) */
  uint16_t rl_rx_lines;   /* lines frames for us, good */
  uint16_t rl_rx_bad;     /* lines frames for us, not good (FCS, header, incomplete, FIFO) */
  uint16_t rl_rx_ovf;     /* ... of which the receive FIFO overflowed */
  uint16_t rl_rx_nosrc;   /* "present, no source" frames for us */
  uint16_t rl_rx_vlan;    /* relay frames for us dropped for the VLAN (wrong VID / untagged) */
  uint16_t rl_rx_long;    /* relay frames for us longer than 2047 bytes (MAC slot) */
  uint16_t rl_rx_foreign; /* good lines frames for a machine not taken */
  uint16_t rl_full_pics;  /* full pictures completed into the triple buffer */
  uint16_t rl_full_swaps; /* full_display buffer changes (new pictures shown) */
  uint8_t rl_flags;       /* DP_RLF_* */
  uint8_t rl_last_machine; /* last good relay frame's machine (0xFF none) */
  uint8_t rl_last_scale;   /* its scale (0 for "no source") */
  uint8_t rl_full_age;     /* 8 ms units since the last full picture (255 = >= 2 s / never) */
  /* relay receive load (bytes 188..195, issue 0060 relay-rx-speed); valid only
     when has_rxload (payload >= 188) */
  uint8_t has_rxload;
  uint16_t rl_fifo_hwm;    /* receive FIFO peak fill in the last second (entries) */
  uint16_t rl_wr_stall;    /* writer waited for DDR3 (word FIFO full), 2.048 us units, wraps */
  uint16_t rl_mem_wait;    /* words offered, memory port busy, 2.048 us units, wraps */
  uint8_t rl_wf_hwm;       /* word FIFO peak fill / 2 in the last second (of 256) */
  uint8_t rl_fifo_aw;      /* log2 of the receive FIFO's entries */
  /* network block (bytes 196..199, issue 0062); valid only when has_net
     (payload >= 192) */
  uint8_t has_net;
  uint16_t host_vlan;       /* key 0x0046: host traffic VLAN ID, 0 = untagged */
  uint16_t host_vlan_drops; /* frames for the host path dropped for their VLAN (wrapping) */
  /* VLAN identity (bytes 200..207, issue 0063); valid only when has_vident
     (payload >= 200) */
  uint8_t has_vident;
  uint8_t vlan_ip[4];       /* board's address on the inter-board VLAN, 0.0.0.0 = off */
  uint16_t vlan;            /* key 0x0043: inter-board VLAN ID (0 = untagged, identity off) */
  uint16_t vlan_hits;       /* ARP/ICMP requests answered for vlan_ip (wrapping) */
} dp_heartbeat_t;

/* heartbeat relay_flags (byte 184, ADR 0005 section 3d, issue 0061) */
enum dp_relay_flag {
  DP_RLF_FULL_WANT = 0x01,  /* full view wanted (selected target without local video) */
  DP_RLF_FULL_FRESH = 0x02, /* a full picture in the last second: shown */
  DP_RLF_FULL_STALE = 0x04, /* wanted, but no full picture in the last second */
  DP_RLF_LAST_VALID = 0x08, /* rl_last_machine / rl_last_scale valid */
  DP_RLF_LAST_NOSRC = 0x10, /* the last relay frame was "present, no source" */
  DP_RLF_STREAMING = 0x20,  /* this board's own source is streaming */
  DP_RLF_LIVE = 0x40,       /* key 0x0045 = 1: live line-by-line full view */
};

/* heartbeat shd_flags (ADR 0005 section 3c, issue 0049) */
enum dp_shield_flag {
  DP_SF_BUILD = 0x01,   /* bitstream has the shield I2C master */
  DP_SF_PROBED = 0x02,  /* first probe finished */
  DP_SF_PRESENT = 0x04, /* expander A answered */
  DP_SF_SENSE = 0x08,   /* last poll of expander B succeeded */
  DP_SF_PWRB = 0x10,    /* power board PRESENT (valid with DP_SF_SENSE) */
  DP_SF_ADOPTED = 0x20, /* CTRL state kept from before an FPGA reconfiguration */
};

/* heartbeat mem_flags (ADR 0005 section 3b, issue 0034) */
enum dp_mem_flag {
  DP_MEM_CALIBRATED = 0x01,
  DP_MEM_ST_RUNNING = 0x02,
  DP_MEM_ST_DONE = 0x04,
  DP_MEM_ST_PASS = 0x08,
};

typedef struct {
  uint8_t version; /* raster format version (DP_RASTER_VERSION) */
  uint32_t frame;
  uint16_t line, h_total, v_total, active_count, v_active, hs_start, hs_end;
  uint8_t flags, encoding;
  uint16_t payload_bytes;
  uint32_t uart_rx_seq;
  uint8_t uart_rx_history[16];
  const uint8_t *payload; /* points into the caller's buffer (payload_bytes long) */
} dp_raster_t;

typedef struct {
  uint32_t boot_id, snap_seq, rx_seq, tx_accepted, tx_emitted;
  uint16_t tx_free, framing_errors, rx_overflows, tx_rejects, clear_gen;
  uint32_t rx_seq_at_clear, baud_nco;
  uint8_t rx_history[512];
  uint8_t tx_history[128];
} dp_snapshot_t;

typedef struct {
  uint32_t seq, next_seq;
  uint8_t status;
  uint8_t target; /* dp_jtag_target */
  uint16_t tdo_bytes;
  uint32_t bit_count;
  uint8_t tdo[DP_JTAG_MAX_BITS / 8];
} dp_jtag_resp_t;

typedef struct {
  uint16_t cmd_id, key;
  uint8_t status;
  uint32_t cfg_gen;
} dp_ack_t;

/* big-endian helpers */
static inline void dp_put16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v; }
static inline void dp_put32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static inline uint16_t dp_get16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static inline uint32_t dp_get32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }

/* Largest JTAG_REQ bit count whose datagram fits one unfragmented IPv4
 * packet of `mtu` bytes (the FPGA does not reassemble fragments), a multiple
 * of 8, capped at DP_JTAG_MAX_BITS: 1500 -> 5792, >= 2028 -> 7904.
 * Returns 0 for mtu < DP_MTU_MIN. */
uint32_t dp_jtag_max_bits_for_mtu(unsigned mtu);

/* Encoders return the total datagram length (header + payload), 0 on error. */
size_t dp_encode_hdr(uint8_t *buf, uint8_t type, uint16_t plen, uint8_t dut);
size_t dp_encode_mgmt_set(uint8_t *buf, uint8_t dut, uint16_t cmd_id, uint16_t key,
                          const uint8_t *value, uint16_t vlen);
size_t dp_encode_kbd_set(uint8_t *buf, uint8_t dut, const uint8_t bitmap[10]);
size_t dp_encode_uart_tx(uint8_t *buf, uint8_t dut, uint32_t offset, uint16_t cmd_id,
                         uint8_t flags, const uint8_t *data, uint16_t len);
size_t dp_encode_jtag_req(uint8_t *buf, uint8_t dut, uint32_t seq, uint32_t half,
                          uint16_t report_us, uint16_t flags, uint32_t bits,
                          const uint8_t *tms, const uint8_t *tdi);

/* Decoders return 0 on success, -1 on malformed input. */
int dp_parse_hdr(const uint8_t *buf, size_t len, dp_hdr_t *h);
int dp_decode_heartbeat(const uint8_t *pl, size_t len, dp_heartbeat_t *hb);
int dp_decode_snapshot(const uint8_t *pl, size_t len, dp_snapshot_t *s);
int dp_decode_jtag_resp(const uint8_t *pl, size_t len, dp_jtag_resp_t *r);
int dp_decode_ack(const uint8_t *pl, size_t len, dp_ack_t *a);
/* Raster: pl/len = body after the common header. Checks payload length and,
 * for raw encoding, payload_bytes == 3 * active_count. */
int dp_decode_raster(const uint8_t *pl, size_t len, dp_raster_t *r);
/* Expand a raster payload to RGB888 (raw copy or RLE24 decode) into out
 * (cap bytes). Returns pixels written, or -1 if malformed / not matching
 * active_count. */
int dp_raster_pixels(const dp_raster_t *r, uint8_t *out, size_t cap);

/* UART NCO increment for a baud rate at 125 MHz */
uint32_t dp_baud_nco(double baud);

/* MEGA65 matrix key names; returns key 0..79 or -1 */
int dp_key_by_name(const char *name);
const char *dp_key_name(int key);
/* heartbeat byte 109 (console_screen): what HDMI OUT shows */
enum {
  DP_CON_EDITABLE = 0,
  DP_CON_NO_VIDEO = 1,
  DP_CON_SELECT = 2,
  DP_CON_PASSTHROUGH = 3, /* HDMI IN passed through (issue 0032) */
  DP_CON_RELAYED = 4,     /* full-resolution relayed picture of the video target (issue 0060) */
};
const char *dp_con_shown_name(int v); /* "editable" .. "relayed", "?" */
/* heartbeat byte 108 (video_flags), ADR 0005 section 8 */
enum {
  DP_VF_CLOCK = 0x01,   /* TMDS clock present */
  DP_VF_LOCKED = 0x02,  /* aligned + decoding */
  DP_VF_CAPTURE = 0x04, /* capture enabled */
  DP_VF_HDMI = 0x08,    /* HDMI preambles seen (else DVI source), issue 0040 */
  DP_VF_ISLANDS = 0x10, /* data islands (InfoFrames / audio) seen, issue 0040 */
};

/* ---------------------------------------------------------------------
 * Thumbnail relay (ADR 0005 section 10, issues 0035/0038): raw Ethernet,
 * EtherType 0x88B5. Bodies below are the bytes after the 14-byte Ethernet
 * header. */
#define DP_ETH_THUMB 0x88B5
#define DP_TH_VERSION 1
#define DP_TH_HDR_LEN 22
#define DP_TH_REQ_LEN 8
#define DP_TH_MAX_W 320
#define DP_TH_MAX_H 200
#define DP_CAP_THUMBS (1u << 7) /* heartbeat capabilities bit */
enum { DP_TH_SUB_REQ = 1, DP_TH_SUB_LINES = 2, DP_TH_SUB_NOSRC = 3 };
enum { DP_TH_SCALE_HALF = 1, DP_TH_SCALE_QUARTER = 2, DP_TH_SCALE_FULL = 3 /* 1/1, issue 0060 */ };
/* request byte 6 flags (issue 0060): b0 targeted (byte 7 = machine), b1 priority */
enum { DP_TH_RF_TARGETED = 1, DP_TH_RF_PRIORITY = 2 };
#define DP_VLAN_DEFAULT 1650 /* inter-board VLAN (key 0x0043) */
#define DP_HOST_VLAN_DEFAULT 0 /* host VLAN (key 0x0046): untagged */
#define DP_VLAN_BASE_DEFAULT 0x0AE73200u /* key 0x0047: 10.231.50.0 (issue 0063) */
#define DP_VLAN_IDENT_OFFSET 16 /* VLAN identity = base + 16 + DIP[7:4] */
enum { DP_TH_FLAG_PRESENT = 1, DP_TH_FLAG_LAST = 2 };

typedef struct {
  uint8_t subtype;        /* DP_TH_SUB_* */
  uint8_t scale, div;     /* request: scale and frame divisor; lines: scale */
  uint8_t rflags, target; /* request: flags (DP_TH_RF_*) and target machine */
  uint8_t machine, flags, encoding; /* DP_ENC_RAW (RAW888) / DP_ENC_RLE24 */
  uint32_t frame;         /* picture number */
  uint16_t row, nlines, width, height, payload_bytes;
  const uint8_t *payload; /* points into the caller's buffer */
} dp_thumb_t;

/* Request body (8 bytes) into buf; returns its length. */
size_t dp_encode_thumb_request(uint8_t *buf, uint8_t scale, uint8_t div);
/* The same with request flags (DP_TH_RF_*) and target machine (issue 0060). */
size_t dp_encode_thumb_request2(uint8_t *buf, uint8_t scale, uint8_t div, uint8_t flags, uint8_t target);
/* Decode a body (after the Ethernet header); 0 ok, -1 malformed / other. */
int dp_decode_thumb(const uint8_t *body, size_t len, dp_thumb_t *t);
/* Expand a lines frame into RGB888 rows (nlines * width * 3 bytes into out).
 * Returns the number of lines, -1 if malformed. */
int dp_thumb_lines(const dp_thumb_t *t, uint8_t *out, size_t cap);

#endif
