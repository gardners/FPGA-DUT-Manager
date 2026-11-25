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
    hb = dict(hb_seq=42, boot_id=0x11223344, build_id=0xC0DE0001, dna=0x0123456789ABCDEF,
              topo_index=0, topo_count=2, dip=0x05, link_flags=0x03, caps=7, cfg_gen=9,
              target_flags=0x0F, kbd_owner=1, kbd_policy=0, selected=0x10,
              kbd_eff=(1 << 10) | (1 << 79), kbd_udp=1 << 10, kbd_phys=1 << 60,
              phys_change=3, phys_type=2, jtag_status=0x02, jtag_next_seq=77,
              uart_rx_seq=1000, uart_tx_acc=55, rx_rejects=4, tx_drops=1,
              dut_leds=bytes(range(12)), addr_src=1, dut_id=7)
    v.append(("heartbeat", P.encode_heartbeat(1, hb)))
    hbv = dict(hb, video_flags=0x07, h_total=864, v_total=625, h_active=720, v_active=576,
               pixel_clock_hz=27000000, frames_captured=0x01020304, raster_lines_dropped=5,
               tmds_decode_errors=6)
    v.append(("heartbeat_video", P.encode_heartbeat(0, hbv)))
    # raster: 720-px active line, pixel x = (x & 0xFF, (x >> 8) ^ line, (3 * x) & 0xFF)
    px = b"".join(bytes([x & 0xFF, (x >> 8) ^ 5, (3 * x) & 0xFF]) for x in range(720))
    v.append(("raster_active", P.encode_raster(
        0, 0x89ABCDEF, 5, 864, 625, px, hs_start=732, hs_end=796,
        flags=P.RF_ACTIVE | P.RF_LOCKED | P.RF_HPOL, uart_rx_seq=1000, uart_hist=b"READY.\r\n")))
    v.append(("raster_blank", P.encode_raster(
        1, 7, 600, 864, 625, b"", hs_start=732, hs_end=796,
        flags=P.RF_VSYNC | P.RF_LOCKED | P.RF_DROPPED, uart_rx_seq=0xFFFFFFFF)))
    rle_px = bytes([0x10, 0x20, 0x30]) * 300 + bytes([1, 2, 3]) * 20
    pkt = P.encode_raster(0, 8, 0, 864, 625, rle_px, hs_start=732, hs_end=796,
                          flags=P.RF_ACTIVE | P.RF_FIRST | P.RF_LOCKED, rle=True)
    assert pkt[8 + 17] == P.ENC_RLE24
    v.append(("raster_rle", pkt))
    for name, p in v:  # self-check: round trip
        if name.startswith("raster"):
            assert P.decode_raster(p[8:])["pixels"] in (px, b"", rle_px)
    hist = bytes(507) + b"HELLO"
    snap = dict(boot_id=0x11223344, snap_seq=5, rx_seq=5, tx_accepted=5, tx_emitted=5,
                tx_free=2043, framing_errors=1, rx_overflows=0, tx_rejects=2, clear_gen=0,
                rx_seq_at_clear=0, baud_nco=68719477, rx_history=hist,
                tx_history=bytes(123) + b"HELLO")
    v.append(("snapshot", P.encode_snapshot(0, snap)))
    v.append(("jtag_resp", P.encode_jtag_resp(0, 0xDEADBEEF, 0xDEADBEF0, 0, 41,
                                              bytes([0x00, 0x26, 0x81, 0xC5, 0x06, 0x00]))))
    v.append(("ack", P.encode_ack(1, 0x1234, 0x0010, 0, 9)))
    return v


if __name__ == "__main__":
    with open(sys.argv[1], "w") as fh:
        for name, data in vectors():
            fh.write("%s %s\n" % (name, data.hex()))
