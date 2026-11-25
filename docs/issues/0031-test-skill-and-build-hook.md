# 0031: Claude tooling: test-run skill with a parallel-build check

Status: Open
Opened: 2026-11-25 (owner request)

The lead kept running simulations before starting bitstream builds despite
the CLAUDE.md rule. Add a project skill for running simulations / tests
that first checks whether a Vivado build should run at the same time
(HDL/constraints changed since the last build, no build already running,
RAM/CPU headroom), and a hook that reminds/enforces this whenever
`make test` / `make test-hdl` / `scripts/run-hdl-tests.sh` is invoked.
