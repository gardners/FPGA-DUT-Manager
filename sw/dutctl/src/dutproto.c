/* dutproto.c - wire protocol v1 encode/decode. LGPL-2.1-or-later. */
#include "dutproto.h"

#include <math.h>
#include <string.h>
#include <strings.h>

size_t dp_encode_hdr(uint8_t *buf, uint8_t type, uint16_t plen, uint8_t dut)
{
  dp_put16(buf, DP_MAGIC);
  buf[2] = DP_VERSION;
  buf[3] = type;
  dp_put16(buf + 4, plen);
  buf[6] = dut;
  buf[7] = 0;
  return DP_HDR_LEN + plen;
}

size_t dp_encode_mgmt_set(uint8_t *buf, uint8_t dut, uint16_t cmd_id, uint16_t key,
                          const uint8_t *value, uint16_t vlen)
{
  if (vlen > 18)
    return 0;
  uint8_t *p = buf + DP_HDR_LEN;
  dp_put16(p, cmd_id);
  dp_put16(p + 2, key);
  dp_put16(p + 4, vlen);
  if (vlen)
    memcpy(p + 6, value, vlen);
  return dp_encode_hdr(buf, DP_T_MGMT_SET, 6 + vlen, dut);
}

size_t dp_encode_kbd_set(uint8_t *buf, uint8_t dut, const uint8_t bitmap[10])
{
  memcpy(buf + DP_HDR_LEN, bitmap, 10);
  return dp_encode_hdr(buf, DP_T_KBD_SET, 10, dut);
}

size_t dp_encode_uart_tx(uint8_t *buf, uint8_t dut, uint32_t offset, uint16_t cmd_id,
                         uint8_t flags, const uint8_t *data, uint16_t len)
{
  if (len > DP_UART_TX_MAX)
    return 0;
  uint8_t *p = buf + DP_HDR_LEN;
  dp_put32(p, offset);
  dp_put16(p + 4, cmd_id);
  p[6] = flags;
  p[7] = 0;
  dp_put16(p + 8, len);
  if (len)
    memcpy(p + 10, data, len);
  return dp_encode_hdr(buf, DP_T_UART_TX, 10 + len, dut);
}

size_t dp_encode_jtag_req(uint8_t *buf, uint8_t dut, uint32_t seq, uint32_t half,
                          uint16_t report_us, uint16_t flags, uint32_t bits,
                          const uint8_t *tms, const uint8_t *tdi)
{
  if (bits == 0 || bits > DP_JTAG_MAX_BITS)
    return 0;
  uint32_t nb = (bits + 7) / 8;
  uint8_t *p = buf + DP_HDR_LEN;
  dp_put32(p, seq);
  dp_put32(p + 4, half);
  dp_put16(p + 8, report_us);
  dp_put16(p + 10, flags);
  dp_put32(p + 12, bits);
  memcpy(p + 16, tms, nb);
  memcpy(p + 16 + nb, tdi, nb);
  /* unused high bits of the last byte are ignored by the FPGA; zero them
   * anyway so retransmissions are byte-identical */
  if (bits % 8) {
    uint8_t mask = (uint8_t)((1u << (bits % 8)) - 1);
    p[16 + nb - 1] &= mask;
    p[16 + 2 * nb - 1] &= mask;
  }
  return dp_encode_hdr(buf, DP_T_JTAG_REQ, (uint16_t)(16 + 2 * nb), dut);
}

int dp_parse_hdr(const uint8_t *buf, size_t len, dp_hdr_t *h)
{
  if (len < DP_HDR_LEN)
    return -1;
  h->magic = dp_get16(buf);
  h->version = buf[2];
  h->type = buf[3];
  h->length = dp_get16(buf + 4);
  h->dut = buf[6];
  h->flags = buf[7];
  if (h->magic != DP_MAGIC || h->version != DP_VERSION || (size_t)h->length + DP_HDR_LEN != len)
    return -1;
  return 0;
}

int dp_decode_heartbeat(const uint8_t *p, size_t len, dp_heartbeat_t *hb)
{
  if (len < 100)
    return -1;
  hb->hb_seq = dp_get32(p + 0);
  hb->boot_id = dp_get32(p + 4);
  hb->build_id = dp_get32(p + 8);
  hb->dna = (uint64_t)dp_get32(p + 12) << 32 | dp_get32(p + 16);
  hb->topo_index = p[20];
  hb->topo_count = p[21];
  hb->dip = p[22];
  hb->link_flags = p[23];
  hb->caps = dp_get32(p + 24);
  hb->cfg_gen = dp_get32(p + 28);
  hb->target_flags = p[32];
  hb->kbd_owner = p[33];
  hb->kbd_policy = p[34];
  hb->selected = p[35];
  memcpy(hb->kbd_eff, p + 36, 10);
  memcpy(hb->kbd_udp, p + 46, 10);
  memcpy(hb->kbd_phys, p + 56, 10);
  hb->phys_change = dp_get16(p + 66);
  hb->phys_type = p[68];
  hb->jtag_status = p[69];
  hb->jtag_next_seq = dp_get32(p + 70);
  hb->uart_rx_seq = dp_get32(p + 74);
  hb->uart_tx_acc = dp_get32(p + 78);
  hb->rx_rejects = dp_get16(p + 82);
  hb->tx_drops = dp_get16(p + 84);
  memcpy(hb->dut_leds, p + 86, 12);
  hb->addr_src = p[98];
  hb->dut_id = p[99];
  return 0;
}

int dp_decode_snapshot(const uint8_t *p, size_t len, dp_snapshot_t *s)
{
  if (len < 680)
    return -1;
  s->boot_id = dp_get32(p + 0);
  s->snap_seq = dp_get32(p + 4);
  s->rx_seq = dp_get32(p + 8);
  s->tx_accepted = dp_get32(p + 12);
  s->tx_emitted = dp_get32(p + 16);
  s->tx_free = dp_get16(p + 20);
  s->framing_errors = dp_get16(p + 22);
  s->rx_overflows = dp_get16(p + 24);
  s->tx_rejects = dp_get16(p + 26);
  s->clear_gen = dp_get16(p + 28);
  s->rx_seq_at_clear = dp_get32(p + 30);
  s->baud_nco = dp_get32(p + 34);
  memcpy(s->rx_history, p + 40, 512);
  memcpy(s->tx_history, p + 552, 128);
  return 0;
}

int dp_decode_jtag_resp(const uint8_t *p, size_t len, dp_jtag_resp_t *r)
{
  if (len < 16)
    return -1;
  r->seq = dp_get32(p);
  r->next_seq = dp_get32(p + 4);
  r->status = p[8];
  r->tdo_bytes = dp_get16(p + 10);
  r->bit_count = dp_get32(p + 12);
  if (r->tdo_bytes > sizeof r->tdo || len < 16u + r->tdo_bytes)
    return -1;
  memcpy(r->tdo, p + 16, r->tdo_bytes);
  return 0;
}

int dp_decode_ack(const uint8_t *p, size_t len, dp_ack_t *a)
{
  if (len < 10)
    return -1;
  a->cmd_id = dp_get16(p);
  a->key = dp_get16(p + 2);
  a->status = p[4];
  a->cfg_gen = dp_get32(p + 6);
  return 0;
}

uint32_t dp_baud_nco(double baud)
{
  return (uint32_t)llround(baud * 4294967296.0 / DP_CLK_HZ);
}

/* C64/C65 matrix order: index = column * 8 + row (as mk2_to_mk1.vhdl) */
static const char *const key_names[80] = {
  "DEL", "RETURN", "RIGHT", "F7", "F1", "F3", "F5", "DOWN",
  "3", "W", "A", "4", "Z", "S", "E", "LSHIFT",
  "5", "R", "D", "6", "C", "F", "T", "X",
  "7", "Y", "G", "8", "B", "H", "U", "V",
  "9", "I", "J", "0", "M", "K", "O", "N",
  "PLUS", "P", "L", "MINUS", "PERIOD", "COLON", "AT", "COMMA",
  "POUND", "ASTERISK", "SEMICOLON", "HOME", "RSHIFT", "EQUALS", "UPARROW", "SLASH",
  "1", "LEFTARROW", "CTRL", "2", "SPACE", "MEGA", "Q", "RUNSTOP",
  "NOSCROLL", "TAB", "ALT", "HELP", "F9", "F11", "F13", "ESC",
  "CAPSLOCK", "UP", "LEFT", "RESTORE", "DEL2", "RETURN2", "CAPSKEY", "K79",
};

int dp_key_by_name(const char *name)
{
  for (int i = 0; i < 80; i++)
    if (strcasecmp(name, key_names[i]) == 0)
      return i;
  return -1;
}

const char *dp_key_name(int key)
{
  return (key >= 0 && key < 80) ? key_names[key] : "?";
}
