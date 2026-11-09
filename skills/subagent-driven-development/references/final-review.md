# Final Review and Finish

Part of superpowers:subagent-driven-development. Every task in the plan is
complete.

The final whole-branch review gets a package too: run
`bash scripts/review-package PLAN_FILE MERGE_BASE HEAD` by its absolute path,
from the working tree you're executing in (MERGE_BASE = the commit the
branch started from, e.g. `git merge-base main HEAD`) and include the
printed path in the final review dispatch, so the final reviewer reads
one file instead of re-deriving the branch diff with git commands. Dispatch
on the most capable available model (see SKILL.md's Model Selection), using
superpowers:requesting-code-review's
[code-reviewer.md](../../requesting-code-review/code-reviewer.md), with the
ledger's `open`, `parked` and `outside branch` lines as its
`[CARRIED_FINDINGS]`. It marks each one FIX or LEAVE.

The fix list is every final finding in code this branch touched, at every
severity, plus every `open` ledger line and every carried line the reviewer
marked FIX. Findings in untouched code go to the ledger as
`Final: outside branch — <one-liner>`. Dispatch ONE fix subagent with the
complete list — not one fixer per finding.
Per-finding fixers each rebuild context and re-run suites; a real
session's final-review fix dispatch cost more than all its tasks combined.
Then run one scoped re-review of the fix dispatch
(`bash scripts/review-package PLAN_FILE FIX_BASE HEAD` by its absolute path,
from the working tree you're executing in, over the fix range,
[re-review-prompt.md](../re-review-prompt.md)).

Residuals are the findings still NOT ADDRESSED plus new breakage in the fix
diff, at any severity. If any remain, run one more fix round with the
residuals and the report file: resume the first fixer when every residual is
breakage in its own diff, otherwise dispatch a fresh fixer on the most
capable model. Then one more scoped re-review. Park a residual only when the
reviewer is wrong (`Final: parked — <finding> — Ruling: <why the code
stands>`). Anything real still open after the second round goes to the
ledger as `Final: still open — <finding> — <why two rounds did not close
it>`.
Only the four things that stop a running plan (top of SKILL.md) stop you
here.

### Finish

Before you delete anything, collect every ledger line containing `Ruling:` —
preflight rulings, parked findings, breaker adjudications, all of them — into
your final message under "Rulings I made", in the order you made them, each
with what it costs if wrong. The list is exhaustive: if the ledger holds a
ruling, the list holds it. That list is the only place the decisions you
took on your human partner's behalf reach them — they read it and rework
whatever you got wrong. A ruling that dies with the workspace was a decision
made in secret. Then list every `outside branch` line under "Outside this
branch", and every `still open` line under "Still open", which is empty in
a run that went well.

Before you send it, ask of every line in those lists: if your human partner
asked "should we fix this now?", would you say yes? Then it is not a
leftover. Dispatch the fix before you report.

When the final whole-branch review is clean and its fixes are merged,
delete this plan's workspace (`rm -rf <workspace>`) — the git history is
the record now. Sibling directories belong to other plans; leave them
alone. In wave mode, first remove any `<main-root>/.worktrees/<plan>/`
directory and `sdd/<plan>/*` branch still present (waves.md, "Finish").

Use superpowers:finishing-a-development-branch.

| Excuse | Reality |
|--------|---------|
| "The skill allows one fix dispatch, so I'll park the rest" | Residuals get a second dispatch. Park only what the reviewer got wrong. |
| "I'll list it; they can ask me to fix it" | If you would say yes when they ask, the answer is already yes. Fix it before you report. |
