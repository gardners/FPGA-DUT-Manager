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

## 2026-11-25 progress (MK-II host, auto-detect and integration; branch `feature/mk2-keyboard`)

**Works in simulation (`make test`: 12 HDL testbenches + C + firmware pass):**

* `hdl/src/kbd/kbd_mk2_host.vhd`: byte-level open-drain I2C master
  (quarter-bit ticks, `QUARTER_CYCLES` = 125 -> 250 kHz SCL at 125 MHz; a
  scan is ~1.1 ms). Same result interface as `kbd_mk1_host` plus `enable`.
  Implements the analysis above: LED write to U1 (reg 6 = all outputs on the
  first scan and every 2**`REINIT_LOG2` = 1024 scans, else reg 2), reads of
  0x21..0x25, the full bit-to-key map, DEL/RETURN duplicated to 76/77, SHIFT
  LOCK toggle ANDed into LSHIFT (15), CAPS LOCK latch (72) / raw key (78) /
  re-toggle after `CAPS_HOLD` = 510 held scans, 4-bit LED PWM, commit id
  "MKII". `present` = some expander ACKed its address in the last scan.
  Upstream fixes applied: proper STOP after the LED write, SDA raised while
  SCL is low before the repeated START, SCL open drain, slave ACK slots
  released by the master. Deliberate deviation: led2_r compares nibble
  ov(31:28) (upstream compared the 8 bits ov(31:24)).
* `hdl/sim/i2c_expander_model.vhd`: behavioural TCA9555 (register pairs with
  pointer toggle, ACK/NACK, `connected` input, counts of reg 6/reg 2 writes,
  error count for START/STOP inside a byte).
* `hdl/tb/tb_kbd_mk2_host.vhd`: every port bit of all five key expanders,
  multi-key, GPIO lines ignored, SHIFT LOCK + LED, CAPS LOCK latch / bounce /
  hold re-toggle + LED, exact PWM duty of all 12 LED nibbles at their U1 bit
  positions, U1 config at start and periodically, key expanders never
  written, no bus errors, bus released when disabled.
* `hdl/src/kbd/kbd_phys_host.vhd`: R6 rule (start MK-II; KIO10 high -> MK-I
  at once; KIO10 low for `MK2_DETECT_CYCLES` = CLK_HZ/8100 = 123 us -> MK-II).
  Outputs o/oe per pin, all registered. `kbd_type` 0 none / 1 MK-I / 2 MK-II
  feeds heartbeat `phys_type` (ADR 0005 already defines 2 = MK-II). An MK-II
  port with no ACKs reports type 0 and an all-zero bitmap.
  `tb_kbd_phys_host`: empty -> MK-II -> MK-I (`kbd_mk1_device`) -> MK-II ->
  unplugged. Note: the detect time must exceed the longest run of '0' bits
  in an MK-I frame (the 14-bit zero date stamp is 5600 clocks at 400
  clocks/bit); a 3000-cycle test value flipped back to MK-II mid-frame.
* `supervisor_core` uses `kbd_phys_host` (new ports `pk_kio8_oe`,
  `pk_kio9_oe`, `pk_kio8_in`); `mimas_a7_top` makes `pk_kio8`/`pk_kio9`
  `inout` with tri-state on the **same pins as before** (J20/J21, K21 for
  KIO10). XDC: weak `PULLUP` on pk_kio8/9 so an empty port reads idle rather
  than floating (a floating SDA could fake ACKs and key presses); timing XDC:
  false path from them as well. `tb_supervisor_core` still passes.
* Confirmed from `~/Projects/mega65/mega65-kbd-pcb` (MK-II KiCad): the parts
  are TCA9555DBR (400 kHz max), and R13/R14 (1k) are SDA/SCL pull-ups on the
  keyboard PCB.

**Not done / not verified:** nothing on hardware (no Vivado build, no JTAG
load from this session). Not synthesised here either (no Vivado/GHDL synth
in this session); the lead should check timing of the new blocks in the next
Vivado build.

**Open questions for the owner (hardware facts):**

1. How is the physical keyboard wired to J20/J21/K21 (P12 X block)? MK-II
   needs KIO8 (SDA) **bidirectional** and both lines open drain. A
   unidirectional buffer/level shifter in that path breaks MK-II; series
   resistors are fine only if small: with the keyboard's 1k pull-ups, the low
   level is 3.3 V * R/(R + 1k), e.g. 0.8 V at 330 ohm, near TCA9555 V_IL
   (0.3 * VCC = 1.0 V). TODO in the adapter design (issue 0008) once known.
2. Power: the MK-II PCB's parts and pull-ups are on +3.3V while ADR 0006 says
   the physical keyboard takes +5 V from the supervisor cable. Which supply
   pins of the keyboard connector does the supervisor cable provide, and does
   the MK-II get its 3.3 V from them?
3. Is the weak FPGA PULLUP on pk_kio8/pk_kio9 acceptable (the MK-I keyboard
   is then also pulled up while the pins are driven push-pull; harmless)?

**Next:** owner answers 1-3; lead runs `make bitstream` and tests with a real
MK-II (and MK-I) keyboard; check `phys_type` = 2 in `dutctl listen`.
