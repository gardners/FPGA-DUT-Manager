# 0049: Three or four DUTs per supervisor (FPGA, protocol, host)

Status: Open
Opened: 2026-11-27 (owner: two Mimas per unit, "bonus points for a 4th DUT")

The shield (0045) adds HDMI receivers and JTAG/UART/keyboard ports so that one
Mimas serves 3-4 DUTs.

1. **Gate build (before the shield is fabricated):** a Vivado build with the
   on-board HDMI receiver plus 3 header receivers on the planned pins
   (BUFG-clocked dvi2rgb variant, one PLL each), placed and meeting timing.
   That decides 3 or 4 DUTs per board, and fixes the pin plan the KiCad
   shield uses (`docs/hardware/shield-pinplan.md`).
2. Second I2C expander for the slow lines (HPD, +5V sense, VIO and keyboard
   sense); I2C master in the FPGA reads the shield revision and features
   at boot and selects the pin use (bodge cables vs shield).
3. Protocol and identity: DUT numbering assumes 2 per board ((dut_id & 0xF)
   * 2 + half); per-DUT endpoints, DIP ID ranges (0026), heartbeat fields,
   dutctl machine digits, the select screen (8 machines over 2 boards ->
   the 4x3 mosaic). These change together (ADR 0005 rule).
4. Capture, passthrough and thumbnails for every receiver (thumbnail
   capture per source, or muxed).
