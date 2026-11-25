# 0031: Claude tooling: test-run skill with a parallel-build check

Status: Done (2026-11-25)
Opened: 2026-11-25 (owner request)

The lead kept running simulations before starting bitstream builds despite
the CLAUDE.md rule. Add a project skill for running simulations / tests
that first checks whether a Vivado build should run at the same time
(HDL/constraints changed since the last build, no build already running,
RAM/CPU headroom), and a hook that reminds/enforces this whenever
`make test` / `make test-hdl` / `scripts/run-hdl-tests.sh` is invoked.

## 2026-11-25 done

* `.claude/skills/run-tests/SKILL.md`: when and how to build in parallel,
  test by exit status, then hardware check / known-good.
* `scripts/claude-test-precheck.sh` + `.claude/settings.json` PreToolUse
  hook on Bash: for test commands it adds a reminder when the synthesised
  sources differ from the last build (build id -> commit) and no Vivado is
  running; silent otherwise; never blocks. Pipe-tested (match / no match /
  changed / unchanged). Live once the settings are reloaded (/hooks or a new
  session: the project had no settings file when this session started).
