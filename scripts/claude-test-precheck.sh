#!/usr/bin/env bash
# Claude Code PreToolUse hook (issue 0031): when a Bash command runs the
# simulations/tests, remind Claude to start a Vivado build in parallel if the
# synthesised sources changed since the last build and no build is running
# (CLAUDE.md "Build bitstreams early"). Never blocks; prints hook JSON with
# additionalContext, or nothing.
repo=$(cd "$(dirname "$0")/.." && pwd)
cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[[ $cmd =~ (make[^|;&]*[[:space:]]test(-hdl)?([[:space:]]|$)|run-hdl-tests\.sh) ]] || exit 0

paths=(hdl/src hdl/sources.mk boards vivado third_party/digilent-dvi2rgb)
idf=$repo/build/vivado/build_id_pkg.vhd
built=$(grep -o 'x"[0-9a-f]*"' "$idf" 2>/dev/null | tr -d 'x"')
changed=1
if [[ -n $built ]] && git -C "$repo" cat-file -e "${built:0:7}^{commit}" 2>/dev/null; then
	git -C "$repo" diff --quiet "${built:0:7}" -- "${paths[@]}" && changed=0
fi
if pgrep -x vivado >/dev/null; then
	msg="A Vivado build is already running (fine: tests and build in parallel)."
elif ((changed)); then
	msg="Synthesised sources (hdl/src, boards, vivado, ...) differ from the last Vivado build (${built:-none}) and no build is running. CLAUDE.md rule: start 'make bitstream' in the background NOW, in parallel with these tests (unless the change does not compile yet or a build would be pointless)."
else
	exit 0
fi
jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
