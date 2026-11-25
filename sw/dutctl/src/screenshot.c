/* screenshot: target resolution for `dutctl screenshot` (issue 0042).
 * See screenshot.h.
 * Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
 */
#include "screenshot.h"

#include "dutproto.h"

#define CAP_HDMI_CAPTURE (1u << 4)

int ss_machine_of(uint8_t dut_id) { return (dut_id & 0x0F) * 2 + ((dut_id >> 4) & 1); }

int ss_digit_machine(int ch)
{
  if (ch < '0' || ch > '9')
    return -1;
  return (ch - '0' + 9) % 10;
}

int ss_machine_digit(int machine)
{
  if (machine < 0 || machine > 9)
    return -1;
  return '0' + (machine + 1) % 10;
}

int ss_board_video_target(const ss_ep_t *e)
{
  int vt = e->selected >> 4;
  return vt < 2 ? vt : -1;
}

int ss_is_video_target(const ss_ep_t *e) { return ss_board_video_target(e) == e->ep; }

int ss_can_capture(const ss_ep_t *e)
{
  return ss_is_video_target(e) && (e->caps & CAP_HDMI_CAPTURE) && e->has_video &&
         (e->video_flags & DP_VF_LOCKED);
}

int ss_find_machine(const ss_ep_t *eps, int n, int machine, int *count)
{
  int found = -1, c = 0;
  for (int i = 0; i < n; i++)
    if (ss_machine_of(eps[i].dut_id) == machine) {
      if (found < 0)
        found = i;
      c++;
    }
  if (count)
    *count = c;
  return found;
}

int ss_find_addr(const ss_ep_t *eps, int n, uint32_t addr)
{
  for (int i = 0; i < n; i++)
    if (eps[i].addr == addr)
      return i;
  return -1;
}

int ss_sibling(const ss_ep_t *eps, int n, int i)
{
  for (int j = 0; j < n; j++)
    if (j != i && eps[j].dna == eps[i].dna && eps[j].boot_id == eps[i].boot_id && eps[j].ep != eps[i].ep)
      return j;
  return -1;
}

int ss_capturable(const ss_ep_t *eps, int n, int *idx, int max)
{
  int c = 0;
  for (int i = 0; i < n; i++)
    if (ss_can_capture(&eps[i])) {
      if (c < max)
        idx[c] = i;
      c++;
    }
  return c;
}
