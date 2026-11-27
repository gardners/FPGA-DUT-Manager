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
