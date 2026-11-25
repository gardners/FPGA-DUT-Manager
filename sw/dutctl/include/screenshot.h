/* screenshot: target resolution for `dutctl screenshot` (issue 0042).
 *
 * Pure logic, no I/O, so it can be unit tested: machine numbers, console
 * digits, and picking the endpoint to capture from a table of heartbeats.
 *
 * Machine numbers follow supervisor_core: m0 = id0(3:0) & '0',
 * m1 = id1(3:0) & '1', where the heartbeat's dut_id is id0 = '0' & DIP[3:0]
 * (P12) or id1 = '1' & DIP[7:4] (P13). So machine = (dut_id & 0x0F) * 2 +
 * (dut_id >> 4 & 1). The console's select screen and the KVM hotkey number
 * machines 0..9 with the digits 1..9, 0 (box "1" is machine 0).
 *
 * Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
 */
#ifndef SCREENSHOT_H
#define SCREENSHOT_H

#include <stdint.h>

/* machine number 0..31 of a heartbeat dut_id */
int ss_machine_of(uint8_t dut_id);
/* console digit '1'..'9','0' -> machine 0..9; anything else -1 */
int ss_digit_machine(int ch);
/* machine 0..9 -> console digit character; anything else -1 */
int ss_machine_digit(int machine);

/* one endpoint, from its latest heartbeat */
typedef struct {
  uint32_t addr;       /* IPv4, network byte order (heartbeat source) */
  uint8_t ep;          /* endpoint index on its board (header dut: 0 = P12, 1 = P13) */
  uint8_t dut_id;
  uint8_t selected;    /* hi nibble video target (0/1 = this board's DUT), lo kbd target */
  uint64_t dna;
  uint32_t boot_id;
  uint32_t caps;
  uint8_t has_video, video_flags, console_screen;
  uint16_t h_active, v_active;
} ss_ep_t;

/* the board's local video target endpoint index (0/1), -1 if none here */
int ss_board_video_target(const ss_ep_t *e);
/* this endpoint is its board's video target */
int ss_is_video_target(const ss_ep_t *e);
/* video target, HDMI capture capability, and video locked */
int ss_can_capture(const ss_ep_t *e);
/* index of the endpoint with this machine number, -1 if none; *count gets
 * the number of matches (several boards with the same DIP setting) */
int ss_find_machine(const ss_ep_t *eps, int n, int machine, int *count);
/* index of the endpoint with this address, -1 if none */
int ss_find_addr(const ss_ep_t *eps, int n, uint32_t addr);
/* index of the other endpoint on the same board as eps[i], -1 if unseen */
int ss_sibling(const ss_ep_t *eps, int n, int i);
/* indices of all capturable endpoints (up to max); returns how many there are */
int ss_capturable(const ss_ep_t *eps, int n, int *idx, int max);

#endif
