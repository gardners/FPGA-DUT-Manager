# 0009: Physical keyboard host: MK-I and MK-II

Status: Open (phase 3)
Opened: 2026-11-25

Port MK-I host (mega65kbd_to_matrix) and MK-II I2C scanner (mk2_to_mk1) with R6-style auto-detect into kbd_phys_host (ADR 0006).

## 2026-11-25 progress (MK-II analysis; session stopped before any HDL was written)

**Works:** nothing new in HDL yet. MK-I host (`kbd_mk1_host`) is unchanged and
still tested by `tb_kbd_mk1_host`.

**Not written or tested:** `hdl/src/kbd/kbd_mk2_host.vhd`,
`hdl/sim/i2c_expander_model.vhd`, `hdl/tb/tb_kbd_mk2_host.vhd`,
`hdl/src/kbd/kbd_phys_host.vhd`, `hdl/tb/tb_kbd_phys_host.vhd`, and the
`sim_files.txt`/`sources.mk` entries.

### MK-II protocol, from reading `third_party/mega65-core/mk2_to_mk1.vhdl`

* I2C: SDA = kb_io0 (KIO8), SCL = kb_io1 (KIO9). Upstream bit-bangs with
  1 tick per 64 cpuclocks (40.5 MHz) and 3 ticks per bit. It drives SCL
  push-pull; we should make SCL open-drain too.
* Expanders: 7-bit address `0100aaa` (0x20 + a), 16-bit port expander with
  PCA9555/TCA9555-style registers (0/1 = input, 2/3 = output, 6/7 = config).
  Which part is fitted is **unverified**: check the MK-II keyboard schematic.
* Order in each scan: write to U1 (a=0) for the LEDs, then read a = 1, 2, 3, 4, 5.
  After the reads, publish `export_keys <= current_keys` (active low) and reset
  `current_keys` to all '1'.
* Read transaction: START, addr+W, ACK, 0x00, ACK (**the master also drives SDA
  low in this slot**), repeated START, addr+R, ACK, byte (port 0 -> bits 7..0),
  master ACK, byte (port 1 -> bits 15..8), master NACK, STOP. Both bytes are
  sent MSB first.
* LED write to U1: START, 0x40, ACK, register byte, ACK, 2 data bytes, ACK.
  The register byte is 0x06 (config) the first time and again every ~1 s
  (re-init), with data 0x00 0x00 (all outputs). Otherwise it is 0x02 (output
  ports). Data byte 0 = {shiftlock, b1, r1, g1, capslock, b0, r0, g0}
  (MSB first). Data byte 1 = {0, b3, r3, g3, 0, b2, r2, g2}. All are active low.
  Upstream ends the write without a real STOP (SDA rises while SCL is low), so
  the next read begins with an effective repeated START. Our port should
  send a proper STOP.
* Upstream race to fix in the port: state 158->159 raises SDA and SCL in the
  same tick before the repeated START. Raise SDA while SCL is low first.
* LED PWM: 4-bit, one step per scan. `ov(i) = leds(95-i)` (same as
  kbd_mk1_device's bit reversal). Nibbles ov(7:4)->led3_r, (15:12)->led3_b,
  (23:20)->led3_g, (31:24)->led2_r, (39:36)->led2_b, (47:44)->led2_g,
  (55:52)->led1_b, (63:60)->led1_r, (71:68)->led1_g, (79:76)->led0_b,
  (87:84)->led0_r, (95:92)->led0_g. An LED is on ('0') when nibble > counter.
* Bit to matrix key mapping (bit n = port bit, 0..7 port 0, 8..15 port 1;
  '0' = pressed):
  * a=3 (U2): 0->67 1->70 2->69 3->68 4->0(+76) 5->51 6->48 7->43 8->41 9->38
    10->33 11->30 12->40 13->35 14->6 15->3
  * a=1 (U3): 7->SHIFTLOCK (toggles shiftlock_toggle on a press edge) 6->10
    5->13 4->18 3->65 2->62 1->9 0->n/c 15->57 14->14 13->58 12->61
    11->15 (ANDed with the shiftlock toggle) 10->12 9->23 8->20
  * a=4 (U4): 7->44 6->47 5->31 4->28 3->39 2->37 1->36 0->42 15->34 14->25
    13->29 12->22 11->26 10->17 9->21 8->60
  * a=2 (U5): 7->52 6->55 5->GPIO2 4->GPIO1 3->74 2->73 1->7 0->2 15->45 14->50
    13->53 12->1(+77) 11->46 10->49 9->54 8->75
  * a=5 (U6): 7->11 6->16 5->19 4->24 3->27 2->32 1->5 0->4 15->64 14->CAPS
    13->66 12->71 11->63 10->56 9->59 8->8
  * CAPS: 78 = raw key. 72 = not caps_lock (so pressed(72) = latched state).
    Toggle when the bit reads '0' after 8 released scans in a row
    (`last_caps_lock = x"FF"`). Toggle again once it has been held for 510 scans.
  * Upstream comments say some ports were "not working" or "reversed". Its
    mapping is assumed correct but is **unverified** on hardware.

### Auto-detect (mega65r6.vhdl ~1600)

* `mk1_connected` resets to '0' and `mkii_counter` resets to 5000.
* KIO10 = '1' -> MK-I immediately (counter cleared). KIO10 low for 5000
  cpuclocks -> MK-II.
* At 125 MHz, use a generic of about 15432 cycles.
* MK-II mode: kio8/kio9 become open-drain (drive '0' only when enabled, else 'Z').

### Next

1. Write `kbd_mk2_host` with a generic tick divider (~400 kHz at 125 MHz is
   about 78 clocks per quarter-bit), using the protocol above.
2. Write the expander model with 'H' pull-ups.
3. Write the testbenches, then `kbd_phys_host` and its testbench.
4. Add the new files to the source lists.
