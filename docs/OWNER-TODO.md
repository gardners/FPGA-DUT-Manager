# Things the lead needs from the owner — moved

Since 2026-11-28 (issue 0065) the owner TODO and status live in the private
rendezvous repo `git@github.com:gardners/ai-agent-rendezvous.git`, section
and directory **`fpga-dut-manager`**:

* top level: `TODO.md` / `STATUS.md` (one section per agent)
* detail: `agents/fpga-dut-manager/TODO.md` / `STATUS.md`

The lead keeps its own checkout at `./rendezvous` (git-ignored, not a
submodule) and edits it with the `agent-rendezvous` skill
(`rendezvous/skills/agent-rendezvous/`). The last version of this file is
in git history (`git log -- docs/OWNER-TODO.md`).
