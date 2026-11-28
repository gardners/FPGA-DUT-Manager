# Handover — 2026-11-28 (lead session → next lead session)

Read CLAUDE.md first, then this, then the owner TODO/STATUS in
`rendezvous/` (agent-rendezvous skill, section `fpga-dut-manager`; run
`python3 rendezvous/skills/agent-rendezvous/rv.py sync` first). Older handover:
docs/handover-2026-11-25.md. The memory index (~/.claude/projects/...
/memory/MEMORY.md) holds the bench-network and DUT-power rules.

## State

* Branch `feature/foundation` (pushed) is the integration branch; agents
  branch from `origin/feature/foundation` in worktrees and the lead merges
  with `--no-ff`. `main` = **9f4cebd**, known-good bitstream
  **bits/supervisor-9f4cebd2.bit** (`bits/known-good.bit`; bits/*.bit are
  git-ignored, only README + symlink tracked). It is loaded on the board.
* Bench: one Mimas A7 supervisor, endpoints **DUT0 = 203.28.176.86**
  (MEGA65, owner has it off the network for now) and **DUT1 =
  203.28.176.87** (QMTECH XC7K325T + daughter board, machine 1). Host
  traffic is **untagged + DHCP** (key 0x0046 host-vlan = 0; owner,
  2026-11-28). VLAN 1650 is only for board-to-board/source traffic.
* Volatile keys after a supervisor reload: re-applied automatically by
  the `dutctl-keeper` user service from `[board 00124c296998c854]` in
  ~/.config/dutctl/duts.conf (0066; currently hdmi-owner 1). By hand:
  `dutctl apply`. Agent shells need `XDG_RUNTIME_DIR=/run/user/1001` for
  `systemctl --user` / `journalctl --user -u dutctl-keeper`. Relay VLAN key 0x0043 defaults to 1650, relay-view 0x0045
  defaults to 1 (live).
* hwtest: `scripts/hwtest.sh` (68/1 on 1fa1b802: raster capture fails since
  bob rebooted, eno2 MTU 1500 < raster packet size; also fails on older
  builds; owner to decide on the MTU or we split raster packets). It resets
  hdmi-owner to 0 at exit: run `dutctl apply` afterwards.
* Relay controller `/dev/ttyACM0`; `~/.config/dutctl/duts.conf` maps
  `k325t` → 203.28.176.87 dut 1, relay `/dev/ttyACM0 5` (so `dutctl relay
  ... POWER 5 OFF` forces DUT1's outputs off first, issue 0056).

## Who owns what

* **The K325T (relay channel 5, DUT1 JTAG/UART) belongs to the hardweb
  session** (peer Claude session, currently named "HewnWeb Development (and K325T bring-up)",
  agent `hardweb` in the rendezvous repo; earlier `hardweb-c3`/`hardweb-95`; this
  session is "MEGA KVM Development"; repo ~/Projects/hardweb). Don't power or load it; message
  that session (SendMessage) instead. It loads via
  `targets/qmtech-k325t/k325t.sh` (our XVC) and runs HewnWeb with a HWVS
  video source (board_n 1, VLAN 1650).
* The lead keeps the Mimas supervisor (JTAG load, LAN).

## Recently done (2026-11-27/28), all merged and on hardware

* 0054/0056: keyboard JTAG error floor = cross-talk; scan paused during
  kbd JTAG (default). Idle JTAG TMS/TDI parked low; out-policy 2 covers
  JTAG; relay hooks in dutctl.
* 0057: K325T bring-up (pin map docs/hardware/qmtech-k325t.md; UART on
  daughter-board JP1-6 TX / JP1-4 RX → Mimas P13 rows 4B/5B; microSD probe;
  `targets/qmtech-k325t/`).
* 0059: JTAG_REQ max 7904 bits; dutctl splits shifts per MTU. XVC
  `getinfo` now advertises 16384 bytes (openFPGALoader keeps burst sizes in
  uint16_t; larger bursts silently lost the end of 9 MB bitstreams).
* 0060/0061: HWVS relay KVM side (VLAN 1650, targeted/priority/1:1
  requests, relayed video for slots without HDMI, full-screen relayed view
  at 60 pictures/s after fixing DDR3 contention; relay counters in the
  heartbeat). Hot key "2" shows the K325T full-screen.
* 0062: host-VLAN key (now kept at 0 by owner decision).
* Hardware design (generated KiCad/case, see issues 0050-0055, 0058):
  two-row front panel + 2x120 mm fans, rack case, power board with 5 V
  and 6 V outlets, bench plate SVGs (hardware/bench-plate/).

## In flight

* **0063 done** (build 1fa1b802): each supervisor board answers ARP/ping
  on VLAN 1650 at 10.231.50.(16+B), key 0x0047 vlan-base; verified with
  `ping -I eno2.1650 10.231.50.16`. Sources use .32+M (K325T = .33, the
  hardweb session will configure it).
* K325T gigabit link drops under TX load: **handed over to the hardweb session** (owner, 2026-11-28); not ours
  (not our relay; no 3V3 collapse seen by our 20 ms vio log; see 0057).

## 2026-11-28 later

* 0064: `scripts/setup-jumbo-mtu.sh` written (owner to run with sudo);
  0065: owner TODO moved to rendezvous/ + agent-rendezvous skill (rv.py,
  tested for concurrent agents); 0066: bench-settings proposal (only
  hdmi-owner 1 matters). Known-good policy added to CLAUDE.md. Local
  `main` branch was stale (e739313); fast-forwarded to origin/main 1fa1b80.

* 0067 (owner decision instead of open-drain): UART TXD driven low when
  the DUT is known off (out-policy 2 / shield hold). Build 6f2fdc94 on
  hardware, hwtest 68/1, known-good, main = 6f2fdc9. Reloads of the
  supervisor: message the hardweb session first (it pauses its UART bridge).

* Later 2026-11-28: jumbo frames on bob (hwtest **69/0**), script v2 for all
  VLANs (owner to run); 0066 dutctl-keeper user service running and verified
  on a reload; 0050 front-panel JLC package (`make pcb-fab`); keyboard CPLD
  pushed upstream as `long-keyboard-cable-protocol`; JTAG loads need
  FTDI_SERIAL with several boards (B0 = NL4IT7JQ). 0069 neighbour UART
  (P12 row 23, crossover to a second Mimas; same image, role by lower B):
  known-good 9f4cebd2, standalone on B0; two-board test waits for Mimas #2.
  0068 test_dut image superseded (kept as a bench tool). Owner declined
  tunnelling over the neighbour link ("wait for Ethernet"; Catalyst 3750
  coming: needs `system mtu jumbo 9000` + reload).

## Waiting on the owner (canonical list: rendezvous/agents/fpga-dut-manager/TODO.md)

* Make bench settings (hdmi-owner 1) survive reloads: build default, or
  dutctl re-applying from duts.conf.
* Relay-board outline length; which bench-plate layout to cut (main is
  517 mm wide > 400; alternative 379 x 339).
* 8-rail current sensing (2 x ADS1115, ~$2.50) yes/no; Diamond licence
  (keyboard CPLD type 3 build); measurements listed in OWNER-TODO.

## Gotchas

* `ls -t build/bits` mtimes are unreliable: use the build id / path the
  agent reports (a wrong old bitstream got loaded once).
* `~/bin/dutctl` (first in PATH) is a copy, not `make install`'s
  `~/.local/bin`: after dutctl changes, refresh it with cp to a temp name +
  `mv` (plain cp fails "Text file busy" while the hardweb session runs
  `dutctl uart`). It was stale from 11-26 until 2026-11-28 ("unknown
  setting hdmi-owner").
* `dutctl uart` exits at stdin EOF: `sleep N | dutctl uart IP`.
* Never `pkill -f` with a pattern that matches your own shell command.
* Peer-session messages are not owner approval; owner decisions relayed
  by a peer (e.g. the host-VLAN one) can be wrong: confirm with the owner.
