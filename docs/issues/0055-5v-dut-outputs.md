# 0055: Three 5 V DUT outputs on the power board

Status: open (owner request 2026-11-27). Related: 0047 (power board), 0049
(shield power control), 0051 (KVM deck).

## Request (owner, 2026-11-27)

Some FPGA boards want 5 V instead of 12 V, so the power board should have
**three outputs that can power 5 V DC barrels**. The owner dislikes
compatible, fryable plugs but accepts them for now; the leads will use
different barrel shank lengths (shorter shank = lower voltage). Feed the 5 V
through from the **Molex** (and the PC PSU connector) input. The banana input
has no 5 V, and that's accepted: banana is really only for bring-up testing
of the 12 V side.

## Lead notes / defaults (veto if wrong)

* Source: the Molex 8981 pin 4 (+5 V, until now unused), through its own
  fuse, independent of the LTC4417 12 V selector. The PCIe 6-pin carries no
  5 V, so in practice "PC PSU" means the Molex lead. No 12 V to 5 V converter
  (owner: no 5 V on banana, such is life).
* Each 5 V output gets its own eFuse (the TPS259470 family runs from 2.7 V,
  with its own OVLO set for 5 V) and its own current limit.
* Control: the shield's 8 CTRL lines are all used by the 12 V DUT outputs,
  so the three 5 V outputs share CTRL5-7. A per-channel selector (jumper)
  decides whether CTRLn enables the 12 V or the 5 V output of that channel,
  so only one of the two is ever live on a channel.
* The board-side connector for the 5 V outputs differs from the 12 V screw
  terminals (keyed, so a 5 V lead can't land on a 12 V terminal by mistake).
* A "5 V present" sense into the status path if a spare expander input
  exists, so the host can see that the Molex 5 V is absent (banana-only
  operation).

## 2026-11-27 Progress: designed on the power board (agent, feature/power-5v)

Done in the generator (`hardware/mega-kvm-power/tools/five_volt.py`, plus
`gen_main.py`, `input_stage.py`, `parts.py`, `placement.py`); details,
sizing and justifications in `docs/hardware/power-board.md`, section
"5 V DUT outputs (issue 0055)".

* **Input:** J53 pin 4 -> **F4 10 A ATO** (same holder as F3; 3 x 3 A
  limits = 9.1 A < 10 A; Molex contact ~11 A) -> **SMBJ5.0A** TVS
  (C2758500) -> +5V. Reverse polarity: TVS conducts and blows F4, the
  eFuses block down to -15 V meanwhile. Independent of the LTC4417.
* **Outputs:** 3 x **TPS259470L** (latch-off, same part as the 12 V DUT
  eFuses): ILIM **3.03 A** (1.1 k), shared OVLO **5.90 V** rising / 5.36 V
  falling (392 k / 100 k; >= 350 k on the supply side for reverse
  polarity), dV/dt 2.2 nF (~0.8 V/ms, 0.4 A into 470 uF), ITIMER 4.7 nF.
* **Selector:** JP5-JP7, a 1x3 2.54 mm header + shunt per channel:
  CTRLn -> 1 k -> pin 2; **1-2 = 12 V, 2-3 = 5 V, no shunt = both off**
  (fail-safe; each EN has its own 20 k pull-down; one shunt cannot select
  both, unlike a 3-pad solder jumper). Fit the shunts on 1-2 at box assembly
  to keep 12 V as the default.
* **Connectors:** **JST VH 2-pin** vertical (B2P-VH, C160315, 10 A,
  latching, polarised) J61-J63 on the rear edge at x 171-210, silk
  "DUTn 5V ONLY". No other VH on the board.
* **Status:** 5 V /FLT wire-ORed onto /FLTn (only one of a channel's pair
  can be on); **5V_PRESENT** (divider) on the optional TCA9535 U11 P1.1, and
  EN5V5-7 on P1.2-1.4 (selection readback). The shield has no spare
  expander input and the CTRL cable is full, so U11 (DNP by default) is the
  only host path. A green "5V" LED D601 sits by J53.
* **Board:** outline 230 x 138.5 mm and mounting holes unchanged; the fan
  block moved 39 mm forward (y 40-111) to free the rear edge. The case reads
  only the outline, holes, J10-J17 and J50-J54, so its fit is unchanged
  (rebuilt: "Conflicts / problems: none").
* **Results:** ERC 0, DRC 0 (unrouted only), schematic parity clean; BOM,
  CPL, PDF and renders regenerated.

Open for the owner (also in power-board.md): TPS259470L has no JLC stock
(shared with the 12 V outputs; TPS259470A / TPS259474L are stocked
alternatives); fit U11 by default; shunt default 1-2; 8 rear lead holes are
enough only for one lead per channel; 3 A per output and 0.2-0.4 V drop at
full load.

### 2026-11-27 owner (round 14) and lead

* **Auto-retry is fine.** All 12 eFuses (8 x 12 V DUT, 3 x 5 V, always-on)
  are now TPS259470ARPWR (C3662799, stocked); the latch-off L part showed 0
  stock. Same footprint, so latch-off stays a drop-in. ERC 0 / DRC 0
  (unrouted only) after the rebuild.
* **First 5 V board: a K325T board** that prefers **6 V** and probably needs
  at least 5 V. It claims 2 A; the owner expects ~3 A with gigabit
  Ethernet, SD card and GPIO loads. The owner will try it at about 4.5 V on
  the bench: if it only draws more current, the Molex 5 V path stays; if it
  misbehaves, add a 12 V -> 6 V step-down.
* Lead notes for that decision:
  * Through the Molex path the board sees about 4.6-4.8 V at 3 A (PSU
    regulation ±5 %, 18 AWG lead, fuse, eFuse), so 4.5 V is the right
    worst case to test. Watch for resets when the gigabit link comes up and
    under SD/GPIO load, not just at idle (that is when the Mimas browned
    out on USB power).
  * 3 A per output is too tight for a board that may draw 3 A: the ILIM
    would trip on peaks. If the 5 V path stays, raise ILIM to about 4 A
    (R_ILM about 820 R), but three of those can reach 12 A, beyond the
    Molex 5 V contact (~11 A) and the 10 A fuse.
  * A 12 V -> 6 V buck per output fixes all three at once: correct
    voltage, works from every input including banana, and moves the load
    onto the 12 V bus (3 x 18 W = 54 W, about 5 A at 12 V). Pad-free 3-4 A
    bucks with ≥ 17 V input exist in SOT-23-6 / TSOT-23-8 (TPS563201-,
    MP2315-class; to be checked for stock). The 5 V eFuse OVLO (5.9 V)
    would then move to about 6.9 V.

### 2026-11-27 owner (round 15): dedicated 6 V outlet

* Better to have an **on-board 12 V -> 6 V step-down for the K325T board**,
  as a **dedicated 6 V outlet** (a 9th output), still behind an eFuse so it
  can be switched off, controlled from the I2C IO expander if it has a GPIO
  for it. The owner will still report the K325T at 4.5 V.
* Lead: the power board's TCA9535 (U11, 0x24) has P1.5-P1.7 spare. P1.5
  drives the 6 V enable (the expander powers up with all pins as inputs, so
  a pull-down keeps the outlet off until the host turns it on); a spare pin
  reads back its /FLT or power-good. U11 becomes fitted by default. The 5 V
  outputs stay as they are. Host control needs a supervisor change (the
  shield I2C master must write U11; today it only runs the shield
  expanders): follow-up together with the fan control.

### 2026-11-27 Progress: 6 V outlet designed (agent, feature/power-6v)

Generator `hardware/mega-kvm-power/tools/six_volt.py` (+ `gen_main.py`,
`placement.py`, `pcb_build.py`); details, sizing, thermal and the host
register sequence in `docs/hardware/power-board.md`, section "6 V outlet".

* **Chain:** VBUS -> **U71 TPS259470A** (5 A, shared 14.8 V OVLO) -> VIN6 ->
  **U73 TPS565201DDCR** (C327676, 9.96k stock, $0.78; 5 A, 500 kHz,
  TSOT-23-6 without pad) -> L70 4.7 uH FXL1040 (C167230, 20 mOhm, Isat
  15 A) -> +6V (27.0 k / 3.92 k 0.1 %: 5.995 V, +-1.1 %) -> **U72
  TPS259470A** (ILIM 4.66 A = 715 R, OVLO 6.90 V, UVLO 5.38 V) -> J70.
* **Why a 17 V buck:** no leaded (pad-free) synchronous buck >= 24 V and
  >= 4 A is stocked (SY8205, TPS54540/531/560, LMR33640, AOZ1284 have
  exposed pads; LMR51440/50, JW5068, TPS56637 are QFN/WSON; the SOT-23
  parts >= 24 V stop at 3 A). U71 keeps VBUS spikes (TVS clamp up to
  24.4 V) off it, like every other VBUS load, isolates a failed buck from
  VBUS, and leaves the buck unpowered while the outlet is off.
* **Control:** U11 TCA9535 (0x24) **fitted by default** now (with R5-R7,
  C7). **P1.5** -> 1 k -> 6V_EN (20 k pull-down: off while P1.5 is an input,
  i.e. after every expander reset) -> U71 EN, and through a 1N4148WS holds
  U72 off; **P1.6** = /FLT of U71 and U72; **P1.7** = 6V_PG (OUT6V > ~4.6 V).
  Host: write 03h <- DFh before 07h <- DFh (the output latch defaults to 1),
  then 03h bit 5 = on/off. U11 runs from the board's own 3V3; JP1 not needed.
* **Connector:** **Molex Micro-Fit 3.0 2x2 right-angle 43045-0400**
  (C122413, 44.5k, $0.34; 8.5 A per contact, latching), pins 1-2 GND, 3-4
  +6 V, on the rear edge between J63 and H5 (x 211-222). Silk "DUT 6V ONLY
  (K325T)", green "6V" LED D741 beside it. Cannot mate with the 5 V VH, the
  Mimas Mini-Fit Jr or the 12 V screw terminals.
* **Budget / heat (4 A out):** ~2 W lost in the chain (~92 %), VBUS +2.2 A
  at 12 V (2.5 A at 10.5 V). U73 ~0.75 W, ~+40-45 K on the 2 oz pours; L70
  ~0.45 W; U72 0.45-0.72 W.
* **Board:** fan block moved another 20 mm forward (y 60-131) for the buck
  (x 171-229, y 40-58); U71 on the VBUS pour by the always-on cell, VIN6 on a
  B.Cu strip. Outline, holes, J10-J17, J50-J54 unchanged; case rebuilt:
  "Conflicts / problems: none".
* `pcb_build.py` now builds connectivity before filling zones: island
  removal had been nondeterministic and left the VBUS, AON12 and OUTn pours
  (and sometimes VS1-3, V2/V3) unfilled in earlier outputs.
* **Results:** ERC 0, DRC 0 (unrouted only), schematic parity clean; BOM,
  CPL, PDF and renders regenerated.

Open (power-board.md "6 V outlet: open questions"): a 9th rear lead hole
in the case; 6.0 V at the buck vs ~6.1 V to offset the eFuse/lead drop at
4 A; cable gauge/plug for the K325T; LCSC numbers for the 0.1 % feedback
resistors. Host control (supervisor I2C writes to 0x24) is a follow-up with
the fan control.
