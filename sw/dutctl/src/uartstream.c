/* uartstream.c - UART snapshot merging. LGPL-2.1-or-later. */
#include "uartstream.h"

#include <string.h>

void us_init(us_state_t *s)
{
  memset(s, 0, sizeof *s);
}

size_t us_rx_snapshot(us_state_t *s, const dp_snapshot_t *snap, uint8_t *out, size_t out_cap,
                      int start_at_end, uint32_t *lost)
{
  *lost = 0;
  /* valid history = bytes since the later of boot and the last clear, <= 512 */
  uint32_t since_clear = snap->rx_seq - snap->rx_seq_at_clear;
  uint32_t valid = since_clear < 512 ? since_clear : 512;
  uint32_t oldest = snap->rx_seq - valid;

  if (!s->synced || snap->boot_id != s->boot_id) {
    if (s->synced)
      s->reboots++;
    s->synced = 1;
    s->boot_id = snap->boot_id;
    s->next_out = start_at_end ? snap->rx_seq : oldest;
    s->tx_sent = s->tx_acked = snap->tx_accepted;
  }

  s->tx_acked = snap->tx_accepted;
  s->tx_free = snap->tx_free;

  if (us_diff(snap->rx_seq, s->next_out) <= 0)
    return 0; /* nothing new (or a stale/reordered snapshot) */

  if (us_diff(oldest, s->next_out) > 0) {
    /* gap: bytes between next_out and oldest are gone */
    *lost = (uint32_t)us_diff(oldest, s->next_out);
    s->bytes_lost += *lost;
    s->next_out = oldest;
  }

  size_t n = 0;
  while (us_diff(snap->rx_seq, s->next_out) > 0 && n < out_cap) {
    /* position in the 512-byte history (oldest first) */
    uint32_t pos = 512 - (snap->rx_seq - s->next_out);
    out[n++] = snap->rx_history[pos];
    s->next_out++;
  }
  s->bytes_out += n;
  return n;
}

uint32_t us_tx_unaccepted(const us_state_t *s)
{
  int32_t d = us_diff(s->tx_sent, s->tx_acked);
  return d > 0 ? (uint32_t)d : 0;
}
