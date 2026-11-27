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
