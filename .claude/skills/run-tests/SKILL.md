---
name: run-tests
description: Run this project's simulations and unit tests (make test / make test-hdl / scripts/run-hdl-tests.sh), and start a Vivado bitstream build in parallel when the synthesised sources changed. Use whenever you are about to run tests after an HDL, constraint, C or Python change in FPGA-DUT-Manager.
---

# Run tests (with a parallel bitstream build)

Owner rule (CLAUDE.md "Build bitstreams early"): a Vivado build takes only a
few minutes on the build box, so builds and simulations run **at the same
time**, never one after the other.

1. **Decide whether to build.** Build in parallel when all hold:
   - something under `hdl/src`, `hdl/sources.mk`, `boards/`, `vivado/` or
     `third_party/digilent-dvi2rgb` differs from the last build — check with
     `scripts/claude-test-precheck.sh` (fed a `make test` hook payload) or
     `git diff --quiet <first 7 hex of build/vivado/build_id_pkg.vhd> -- hdl/src boards vivado`;
   - the change at least analyses (a syntax error wastes the build);
   - no Vivado build is already running (`pgrep -x vivado`) and RAM allows
     (about 3 GB per build; at most ~4 at once on the build box).
   Commit first: the build id is the git short hash, so an uncommitted build
   is ambiguous.
2. **Start the build in the background** (Bash `run_in_background: true`):
   ```
   make bitstream > build/vivado-run.log 2>&1; echo exit=$?; cat build/vivado/timing_verdict.txt
   id=$(grep -o 'x"[0-9a-f]*"' build/vivado/build_id_pkg.vhd | tr -d 'x"')
   grep -q 'write_bitstream completed successfully' build/vivado/vivado.log && \
     cp build/vivado/supervisor.bit build/bits/supervisor-$id.bit
   ```
3. **Run the tests in the foreground at the same time**, judging by the
   exit status, never by grepping the output:
   ```
   make test > build/test.log 2>&1; echo test_exit=$?
   grep -E 'Failure|ERROR|HDL tests|checks,' build/test.log
   ```
   Single testbench: `scripts/run-hdl-tests.sh tb_name`.
4. **When both are done:** tests green + `TIMING MET` -> load and check on the
   board (`scripts/hwcheck.sh build/bits/supervisor-<id>.bit`, then
   `scripts/hwtest.sh` or `--quick`), and only then record it as known-good
   (`bits/`, `bits/README.md`) and fast-forward `main`.

A PreToolUse hook (`.claude/settings.json` -> `scripts/claude-test-precheck.sh`)
adds a reminder to the context whenever tests run while a build is warranted
but not running (issue 0031).
