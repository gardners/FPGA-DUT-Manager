/* uartstream.h - host side of the UDP UART bridge (ADR 0005 section 6).
 *
 * RX: feed every snapshot; contiguous new bytes are emitted exactly once.
 * Byte offsets are 32-bit and compared modulo 2^32 within half range.
 * TX: tracks the FPGA's accepted offset and decides what to (re)send.
 * LGPL-2.1-or-later. */
#ifndef UARTSTREAM_H
#define UARTSTREAM_H

#include <stddef.h>
#include <stdint.h>

#include "dutproto.h"

typedef struct {
  int synced;            /* have we seen a snapshot since (re)boot? */
  uint32_t boot_id;
  uint32_t next_out;     /* absolute offset of the next byte to emit */
  uint64_t bytes_out;
  uint64_t bytes_lost;   /* bytes that fell out of history before we saw them */
  uint32_t reboots;
  /* TX */
  uint32_t tx_sent;      /* offset just after the last byte we have sent */
  uint32_t tx_acked;     /* FPGA's tx_accepted as last reported */
  uint16_t tx_free;
  uint16_t cmd_id;
} us_state_t;

void us_init(us_state_t *s);

/* Process one snapshot. Writes up to out_cap new bytes to out and returns
 * how many; *lost gets bytes skipped because of a gap. If start_at_end is
 * set and this is the first snapshot, only bytes arriving later are emitted. */
size_t us_rx_snapshot(us_state_t *s, const dp_snapshot_t *snap, uint8_t *out, size_t out_cap,
                      int start_at_end, uint32_t *lost);

/* Signed distance a - b modulo 2^32 */
static inline int32_t us_diff(uint32_t a, uint32_t b) { return (int32_t)(a - b); }

/* After a snapshot reports tx_accepted, how many of our sent bytes were not
 * accepted (and must be re-sent starting at tx_acked)? */
uint32_t us_tx_unaccepted(const us_state_t *s);

#endif
