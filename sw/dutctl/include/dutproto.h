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
  DP_K_CAPTURE_EN = 0x0040,
  DP_K_HB_PERIOD = 0x0050,
  DP_K_OUT_POLICY = 0x0060,
};

enum dp_ack_status { DP_ACK_OK = 0, DP_ACK_BAD_KEY, DP_ACK_BAD_LEN, DP_ACK_BAD_VALUE, DP_ACK_DUPLICATE };
enum dp_jtag_status { DP_JS_DONE = 0, DP_JS_BUSY, DP_JS_BAD_SEQ, DP_JS_BAD_FMT, DP_JS_UNPOWERED };

#define DP_JTAG_MAX_BITS 8192
#define DP_UART_TX_MAX 1024
#define DP_CLK_HZ 125000000.0
#define DP_MAX_PACKET 2200

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
} dp_heartbeat_t;

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

/* UART NCO increment for a baud rate at 125 MHz */
uint32_t dp_baud_nco(double baud);

/* MEGA65 matrix key names; returns key 0..79 or -1 */
int dp_key_by_name(const char *name);
const char *dp_key_name(int key);

#endif
