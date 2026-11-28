# 0066: Bench settings that survive a supervisor reload

Status: done, verified on a real reload (2026-11-28).

## Settings the bench depends on today

All MGMT keys are volatile (RAM in the FPGA): a JTAG load, reconfiguration
from flash or brown-out returns them to the build defaults. Of the keys
the bench uses, only one differs from its default:

| Board | Key | Name | Bench value | Default | Why |
|---|---|---|---|---|---|
| supervisor B0 (DNA 00124c296998c854, .86/.87) | 0x0044 | hdmi-owner | **1** (DUT0 owns HDMI IN) | 0 (both DUTs share it) | DUT1 (K325T) has no HDMI cable: with 1 its slot shows the relayed HWVS picture instead of DUT0's input |

Already right by default (listed so they are not "fixed" twice): 0x0043
relay VLAN 1650, 0x0045 relay-view 1, 0x0046 host-vlan 0, 0x0047
vlan-base 10.231.50.16. Telemetry destinations (0x0003/0x0004) and capture
(0x0040) are set and restored by hwtest/dutctl per run and must stay
default.

## Proposal

`duts.conf` gets board sections keyed by DNA (stable across DHCP):

    [board 00124c296998c854]
    set = hdmi-owner 1

`dutctl apply [--conf F]` sends them to every board heard. A user systemd
unit `dutctl keeper` listens to heartbeats and re-applies when a board's
boot id changes (heartbeat `boot` field), so nobody has to remember. No
HDL change; build defaults stay the vendor-neutral ones.

## 2026-11-28 owner: approved ("bench-settings persistence sounds good")

Recommended option taken: `[board <dna>]` sections in duts.conf, `dutctl
apply`, and a user systemd `dutctl keeper` re-applying on a heartbeat
boot-id change. Status: approved, to implement.

## 2026-11-28 progress: implemented (branch `feature/dutctl-keeper`)

Host-only, no wire-protocol or HDL change.

* `sw/dutctl/src/dutset.c` (`ds_encode`): the `dutctl set` name table
  moved out of `main.c` so duts.conf can check settings when it is parsed.
  Values are now checked strictly: the whole string must parse and the
  value must fit the key's width. So `dutctl set IP hdmi-owner 300` is now
  refused (exit 2); before, it was silently truncated.
* duts.conf (`include/dutconf.h` header comment, `dutctl duts --help`):
  `[board <dna>]` sections (1..16 hex digits, the `dna` that heartbeats
  show) with any number of `set = NAME VALUE` lines, sent in file order.
  Unknown setting names, bad values, other keys, duplicate or bad DNAs
  are reported with line numbers. `[dut]` sections are unchanged, and
  `[board]` with no DNA is still an ordinary DUT section.
  `dutctl duts` lists the board sections.
* `dutctl apply [-t S] [--any]` (default 5 s): sends each configured
  board's settings once to the endpoint whose heartbeat was heard
  (dut = any), prints one line per board and exits 1 if any set got no ack
  or was rejected. A board that is not heard is reported but is not a
  failure.
* `dutctl keeper [--min-interval S] [--any]`: runs until stopped. It
  re-applies when a board is first heard, whenever its heartbeat `boot`
  id changes, and for every board after SIGHUP (duts.conf re-read).
  Sends to one board are at least 5 s apart; a failed send is retried
  with backoff 10/20/40/60 s. It logs one timestamped line per action.
  The decision logic is in `src/keeper.c`, which has no network code and
  is unit-tested.
* Running alongside other dutctl commands: apply and keeper bind the heartbeat port
  to 255.255.255.255 (SO_REUSEADDR+REUSEPORT). So they get every
  broadcast heartbeat (the default telemetry destination) alongside
  `dutctl listen`. They never take a share of heartbeats a board sends
  unicast to this host while `dutctl screenshot` has pointed its telemetry
  here: REUSEPORT load-balances unicast between the INADDR_ANY sockets
  of a port. Checked on the bench host: a broadcast-bound and an
  INADDR_ANY socket each got all 201 heartbeats of B0 (.86/.87) in 2 s.
  5 unicast datagrams all went to the INADDR_ANY socket. `--any` binds
  INADDR_ANY instead.
* `sw/dutctl/systemd/dutctl-keeper.service`: a user unit. ExecStart is
  `%h/.local/bin/dutctl keeper`, with Restart=always and
  `systemctl --user reload` = SIGHUP.

Tests: `make test` gave HDL tests: 38 passed, 0 failed; dutctl tests:
981 checks, 0 failures (was 917: named settings, [board] parsing and
error cases, re-apply decision for first seen / boot change / unchanged /
rate limit / backoff / reload / forget); relay_core tests: 52 checks, 0
failures. Loopback smoke test with a fake supervisor (made-up DNA,
127.0.0.2, `--any`): apply sent both settings and exited 0. With no
acks it exited 1. The keeper applied on first sighting, on each boot-id
change and after SIGHUP, and on nothing else. A passive `apply` against
B0 with an empty `[board 00124c296998c854]` section found the board
(boot 4cda5eb9).

### Install (not done; lead/owner)

Add to `~/.config/dutctl/duts.conf`:

    [board 00124c296998c854]
    set = hdmi-owner 1

Then:

    make -C sw/dutctl install            # -> ~/.local/bin/dutctl
    dutctl apply                         # one-off check
    install -D -m644 sw/dutctl/systemd/dutctl-keeper.service \
        ~/.config/systemd/user/dutctl-keeper.service
    systemctl --user daemon-reload
    systemctl --user enable --now dutctl-keeper
    loginctl enable-linger "$USER"       # optional: keep it running without a login
    journalctl --user -u dutctl-keeper -f
    systemctl --user reload dutctl-keeper   # after editing duts.conf

## 2026-11-28 lead: integrated and running

Merged into feature/foundation; `make test` green (38 HDL, 981 dutctl, 52
relay). Installed dutctl (~/.local/bin and the ~/bin copy), added to
~/.config/dutctl/duts.conf:

    [board 00124c296998c854]
    set = hdmi-owner 1

`dutctl apply` -> "via 203.28.176.86 (boot 4cda5eb9): hdmi-owner 1 -
applied". User unit installed and enabled; journal: "first seen, boot
4cda5eb9: hdmi-owner 1 - applied". Note: systemctl --user needs
XDG_RUNTIME_DIR=/run/user/1001 in agent shells. Linger is off, so the
keeper runs only while the owner is logged in on bob (owner question).
Still to see on hardware: a "boot X -> Y" re-apply after a JTAG load.

## 2026-11-28 lead: verified on a reload

JTAG load of 9f4cebd2: keeper journal "board 00124c296998c854 via
203.28.176.86 (boot 4cda5eb9 -> 4cdbd847): hdmi-owner 1 - applied"; hwtest
69/0 and its exit re-apply worked. Done.
