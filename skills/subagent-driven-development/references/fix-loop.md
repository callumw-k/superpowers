# The Fix Loop

Part of superpowers:subagent-driven-development. The task review reported
spec ❌, a finding at any severity, or a ⚠️ item you confirmed as a real gap.

Severity sets the order of the fix message, not whether a finding gets
fixed: a review with only Minor findings still gets a fix round. Small
findings left behind add up across tasks and branches, and nobody comes back
for them.

Before the loop starts, two routes leave it immediately:

- A finding in code this branch has not touched is outside the task. Ledger
  it as `Task <N>: outside branch — <one-liner>` and leave the code alone;
  it reaches your human partner as a mention, not a change.
- A finding labeled plan-mandated — or any finding that conflicts with
  what the plan's text requires — is yours to rule on: weigh the finding
  against the plan text, decide with the spec as the binding authority, and
  ledger the ruling before you act on it. Do not dismiss the finding because
  the plan mandates it, and do not dispatch a fix that contradicts the plan
  without a recorded ruling.
Everything else enters the loop. A fix round is one fix dispatch plus one
scoped re-review. Five rounds maximum per task:

**Rounds 1-3 — resume the original implementer.** Send it the open findings
verbatim. Its context is intact: it knows the task, the code, and its own
choices. If your harness cannot send another message to a live subagent,
dispatch a fresh implementer carrying the brief path, the report-file path,
and the findings — the report file is the persistent memory either way.

**Rounds 4-5 — dispatch a fresh implementer on a more capable model** (per
SKILL.md's Model Selection), with the brief path, the report-file path, the open
findings, and this framing: "A prior implementer attempted this task
[N] times; you own it now. Read the report file for what was tried." A loop
that survives three resumes usually means the implementer cannot see its
own problem — fresh eyes and a capability bump in one move.

**Every round, either way:** the implementer fixes, re-runs the tests
covering the amended code, appends its fix report to the same report file,
and returns the short contract. Before re-dispatching the reviewer, confirm
the fix report contains the covering tests, the command run, and the
output; dispatch the re-review once all three are present. Name the
covering test files in the fix message — a one-line fix does not need the
whole suite.

**The re-review is scoped.** Run `bash scripts/review-package PLAN_FILE FIX_BASE HEAD`
by its absolute path, from the working tree you're executing in, where FIX_BASE is the head the previous review saw, and dispatch
[re-review-prompt.md](../re-review-prompt.md) with the findings list, the
brief, the report file, and the printed diff path. The re-reviewer verdicts
each finding ADDRESSED or NOT ADDRESSED and flags new breakage in the fix
diff only. New breakage in the fix diff, at any severity, joins the open
findings list. Out-of-scope observations never extend the loop: one in code
this branch touched goes to the ledger as `Task <N>: open — <one-liner>`
for the final fix dispatch; one in untouched code goes as `outside branch`.

**After each round,** append to the ledger:
`Task <N>: fix round <R>/5 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>)`

Never fix findings yourself in the controller session — your context stays
clean for coordination, and controller fixes skip review.

**The breaker.** When round 5's re-review still leaves findings open, stop
dispatching. Adjudicate each open finding yourself — you hold the plan and
the cross-task context the reviewer lacks:

- **The reviewer is wrong, or the point is contestable:** park it —
  `Task <N>: parked — <finding> — Ruling: <why the code stands>`. The final
  review sees both sides.
- **Real, but nothing downstream builds on it:** ledger it as
  `Task <N>: open — <finding>`. The final fix dispatch closes it with fresh
  eyes on the most capable model. Real findings are never parked.
- **Real and load-bearing** — a later task builds on it, or it reveals a
  plan defect: rule on the smallest change that unblocks the dependent work,
  ledger it as `Task <N>: Ruling: <finding> — <what you decided and why>`,
  and carry it into the next task's dispatch. Parking a structural failure
  silently lets every dependent task build on it. Stop only when the defect
  leaves every path forward a guess.

Adjudicate only at the cap. Adjudicating earlier to end a loop is
pre-judging with a different name. Every adjudication is a ledger entry —
a silent discard is forbidden.

| Excuse | Reality |
|--------|---------|
| "It's only Minor, it can wait" | Nothing comes back for it. Minors left on every branch become the codebase. Minor sets the order, not the outcome. |
| "The run already cost too much to fix minors" | A minor rides in a fix round you are already paying for. Listing it hands your partner the same fix later, at a higher price. |
