# 0065: Owner TODO and status move to the ai-agent-rendezvous repo

Status: done (owner, 2026-11-28).

## Owner (2026-11-28)

"The owner TODO stuff we're now going to move into a separate private
repo: git@github.com:gardners/ai-agent-rendezvous.git. Don't make it a
sub-module, but have a local checkout so that you can put stuff in there.
You're allowed to make subdirectories in there for your bodies of work, and
your separate TODO tracking for me, and then do pull rebases to be able to
merge and repush that with the top-level TODO with a section for you, among
the sections for other agents. The requests should be priority sorted and
date/time stamped. You should also maintain a section in a STATUS.md in the
top level in the same way where you keep track of where you're up to, and
you can have a longer version in your private directory. So make a skill
from that, and have the skill in a skills/ directory of this new repo, so
that I can share it with my other minions, too."

## Plan

* Checkout at ~/Projects/ai-agent-rendezvous (not a submodule).
* Top level TODO.md / STATUS.md: one marked section per agent; this
  project's agent is `fpga-dut-manager`. Detail in
  agents/fpga-dut-manager/{TODO,STATUS}.md.
* skills/agent-rendezvous/: SKILL.md + rv.py (section replace, sync with
  pull --rebase, conflict-free re-apply of the agent's own sections).
* docs/OWNER-TODO.md here becomes a pointer.

## 2026-11-28 lead: done

Owner (mid-task): check it out inside the work dir, so agents on one
machine don't share a checkout and edits need no permission prompts. So:
`./rendezvous` (git-ignored), skill linked as
`.claude/skills/agent-rendezvous` (git-ignored). Pushed cc5ca96: README,
TODO.md, STATUS.md, agents/fpga-dut-manager/{TODO,STATUS}.md (the 25 old
rows with git-blame times + 4 new), skills/agent-rendezvous/{SKILL.md,rv.py}.
rv.py tested with three agents in two clones against a local bare repo:
rebase conflicts merged per section, unpublished drafts of a second agent
in the same checkout stay uncommitted and intact. docs/OWNER-TODO.md is a
pointer now.

## 2026-11-28 owner: retiring agents

"We do also need a mechanism to retire content from dead/extinct agents
that don't need to return into an attic/ folder of it." Plan: `rv retire
AGENT -r REASON` moves agents/AGENT/ and its TODO/STATUS sections into
attic/AGENT/ and publishes; `rv agents` lists sections with their last
Updated time so stale ones are easy to spot.

2026-11-28 lead: `rv agents` and `rv retire` done and tested (with an
adjacent concurrent edit); published b77d812. Owner (same day): "The TODO
list should have live links for each item" -> every TODO row's Ref is a
GitHub link (rv lint enforces it), files to open/run are linked in the
Item; published 69c44ab. Owner will confirm the hardweb session's setup
once the repo and its use are improved.

2026-11-28 owner: "for any new questions for the owner, the question
should be explicitly written with the recommended and alternative
decisions, and what to do/say/tell to effect each decision". Rule added to
SKILL.md; all our open questions rewritten (Rec/Alt + exact reply),
published 1fb0a76.
