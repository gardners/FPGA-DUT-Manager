"""Golden protocol vectors for the C unit tests (sw/dutctl/tests).

Output lines: "<name> <hex>"  -- packets the C encoders must reproduce
exactly, or FPGA->host packets the C decoders must parse (expected field
values are hard-coded in the C test to match this file).
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import netproto as P  # noqa: E402

TMS = "11111" + "0100" + "0" * 31 + "1"


def vectors():
    v = []
    v.append(("mgmt_baud", P.mgmt_set(0, 0x1234, 0x0010, struct.pack(">I", 68719477))))
    v.append(("mgmt_ip", P.mgmt_set(0xFF, 7, 0x0002, P.ip("10.1.2.3"))))
    v.append(("kbd_wild", P.kbd_set(0xFF, [10, 63, 79])))
    v.append(("uart_hello_clear", P.uart_tx(1, 0xFFFFFFFE, 9, b"HELLO", clear=True)))
    v.append(("jtag_41", P.jtag_req(0, 0xDEADBEEF, TMS, "0" * len(TMS), half=6)))
    # keyboard CPLD target (ADR 0014): session reset on the wildcard endpoint
    v.append(("jtag_kbd_reset", P.jtag_req(0xFF, 7, "1", "0", half=6, flags=P.JF_ABORT | P.JF_KBD)))
    hb = dict(hb_seq=42, boot_id=0x11223344, build_id=0xC0DE0001, dna=0x0123456789ABCDEF,
              topo_index=0, topo_count=2, dip=0x05, link_flags=0x03, caps=7, cfg_gen=9,
              target_flags=0x0F, kbd_owner=1, kbd_policy=0, selected=0x10,
              kbd_eff=(1 << 10) | (1 << 79), kbd_udp=1 << 10, kbd_phys=1 << 60,
              phys_change=3, phys_type=2, jtag_status=0x02, jtag_next_seq=77,
              uart_rx_seq=1000, uart_tx_acc=55, rx_rejects=4, tx_drops=1,
              dut_leds=bytes(range(12)), addr_src=1, dut_id=7)
    v.append(("heartbeat", P.encode_heartbeat(1, hb)))
    hbv = dict(hb, video_flags=0x07, console_screen=3, h_total=864, v_total=625, h_active=720, v_active=576,
               pixel_clock_hz=27000000, frames_captured=0x01020304, raster_lines_dropped=5,
               tmds_decode_errors=6)
    v.append(("heartbeat_video", P.encode_heartbeat(0, hbv)))
    hbl = dict(hbv, rx_phase_pos=3, rx_eye_width=24, rx_hunts=2, rx_bad_frames=300,
               rx_link_flags=0x02)
    v.append(("heartbeat_link", P.encode_heartbeat(1, hbl)))
    hbm = dict(hbl, mem_flags=P.MEM_CALIBRATED | P.MEM_ST_DONE, mem_errors=513, mem_dq_fail=0x8001,
               mem_test_kib=1024, mem_first_err=0x00ABCDEF)
    v.append(("heartbeat_mem", P.encode_heartbeat(0, hbm)))
    hbs = dict(hbm, shd_flags=P.SF_BUILD | P.SF_PROBED | P.SF_PRESENT | P.SF_SENSE | P.SF_PWRB,
               shd_revision=0x01, shd_features=0x7F, shd_sense=0x31, shd_hdmi=0x5D, shd_pwr=0xA5,
               shd_i2c_errors=0x0102)
    v.append(("heartbeat_shield", P.encode_heartbeat(1, hbs)))
    hbr = dict(hbs, rl_req_sent=0x0102, rl_req_full=0x0304, rl_rx_req=0x0506, rl_rx_lines=0xFFFE,
               rl_rx_bad=0x0708, rl_rx_ovf=0x090A, rl_rx_nosrc=0x0B0C, rl_rx_vlan=0x0D0E,
               rl_rx_long=0x1011, rl_rx_foreign=0x1213, rl_full_pics=0x1415, rl_full_swaps=0x1617,
               rl_flags=P.RLF_FULL_WANT | P.RLF_FULL_STALE | P.RLF_LAST_VALID, rl_last_machine=1,
               rl_last_scale=3, rl_full_age=0xFF)
    v.append(("heartbeat_relay", P.encode_heartbeat(0, hbr)))
    v.append(("mgmt_pwr_ctl", P.mgmt_set(1, 0x0BAD, P.K_PWR_CTL, b"\xa5")))
    # raster: 720-px active line, pixel x = (x & 0xFF, (x >> 8) ^ line, (3 * x) & 0xFF)
    px = b"".join(bytes([x & 0xFF, (x >> 8) ^ 5, (3 * x) & 0xFF]) for x in range(720))
    v.append(("raster_active", P.encode_raster(
        0, 0x89ABCDEF, 5, 864, 625, px, hs_start=732, hs_end=796, v_active=576,
        flags=P.RF_ACTIVE | P.RF_LOCKED | P.RF_HPOL, uart_rx_seq=1000, uart_hist=b"READY.\r\n")))
    v.append(("raster_blank", P.encode_raster(
        1, 7, 600, 864, 625, b"", hs_start=732, hs_end=796, v_active=576,
        flags=P.RF_VSYNC | P.RF_LOCKED | P.RF_DROPPED, uart_rx_seq=0xFFFFFFFF)))
    rle_px = bytes([0x10, 0x20, 0x30]) * 300 + bytes([1, 2, 3]) * 20
    pkt = P.encode_raster(0, 8, 0, 864, 625, rle_px, hs_start=732, hs_end=796, v_active=576,
                          flags=P.RF_ACTIVE | P.RF_FIRST | P.RF_LOCKED, rle=True)
    assert pkt[8] == P.RASTER_VERSION and pkt[8 + 1] == P.ENC_RLE24
    v.append(("raster_badver", pkt[:8] + bytes([2]) + pkt[9:]))
    v.append(("raster_rle", pkt))
    for name, p in v:  # self-check: round trip
        if name.startswith("raster") and name != "raster_badver":
            assert P.decode_raster(p[8:])["pixels"] in (px, b"", rle_px)
    # thumbnail relay (ADR 0005 s10): request, RAW888 1/4-scale lines,
    # RLE24 1/2-scale lines, no-source, unknown version
    src = P.mac("02:4D:36:35:00:11")
    v.append(("thumb_req", P.thumb_request(src, P.TH_SCALE_QUARTER, 3)))
    q = [bytes(((x * 5 + y) & 255) for x in range(480)) for y in range(2)]
    v.append(("thumb_raw", P.thumb_frame(P.mac("02:00:00:00:00:aa"), src, 3, 0x01020304, 10, q,
                                         P.TH_SCALE_QUARTER, 100, enc=P.TH_ENC_RAW)))
    h = [bytes([9, 8, 7]) * 300 + bytes([1, 2, 3]) * 20 for _ in range(3)]
    t = P.thumb_frame(P.mac("02:00:00:00:00:aa"), src, 31, 7, 197, h, P.TH_SCALE_HALF, 200,
                      flags=P.TH_FLAG_PRESENT | P.TH_FLAG_LAST)
    assert t[14 + 7] == P.TH_ENC_RLE24
    v.append(("thumb_rle", t))
    v.append(("thumb_nosrc", P.thumb_nosrc(P.mac("02:00:00:00:00:aa"), src, 12)))
    v.append(("thumb_badver", t[:14] + bytes([2]) + t[15:]))
    for name, p in v[-5:-1]:
        d = P.decode_thumb(p[14:])
        assert d["sub"] != P.TH_SUB_LINES or d["lines"] in (q, h)
    # issue 0060: targeted priority 1/1 request (machine 5); a 1/1 lines frame
    v.append(("thumb_req_target", P.thumb_request(src, P.TH_SCALE_FULL, 1,
                                                  P.TH_RF_TARGETED | P.TH_RF_PRIORITY, 5)))
    v.append(("thumb_full", P.thumb_frame(P.mac("02:00:00:00:00:aa"), src, 1, 9, 479,
                                          [bytes([1, 2, 3]) * 720], P.TH_SCALE_FULL, 480)))
    hist = bytes(507) + b"HELLO"
    snap = dict(boot_id=0x11223344, snap_seq=5, rx_seq=5, tx_accepted=5, tx_emitted=5,
                tx_free=2043, framing_errors=1, rx_overflows=0, tx_rejects=2, clear_gen=0,
                rx_seq_at_clear=0, baud_nco=68719477, rx_history=hist,
                tx_history=bytes(123) + b"HELLO")
    v.append(("snapshot", P.encode_snapshot(0, snap)))
    v.append(("jtag_resp", P.encode_jtag_resp(0, 0xDEADBEEF, 0xDEADBEF0, 0, 41,
                                              bytes([0x00, 0x26, 0x81, 0xC5, 0x06, 0x00]))))
    # LCMXO2-1200HC IDCODE 0x012BA043 after 9 navigation bits
    v.append(("jtag_resp_kbd", P.encode_jtag_resp(1, 3, 4, 0, 41,
                                                  (0x012BA043 << 9).to_bytes(6, "little"),
                                                  target=P.JT_KBD)))
    v.append(("ack", P.encode_ack(1, 0x1234, 0x0010, 0, 9)))
    return v


if __name__ == "__main__":
    with open(sys.argv[1], "w") as fh:
        for name, data in vectors():
            fh.write("%s %s\n" % (name, data.hex()))
