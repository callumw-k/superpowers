# SDD wave execution — design

Run independent plan tasks concurrently inside subagent-driven-development (SDD), each in its own worktree, merged into the plan branch in waves. Opt-in per run. Serial SDD stays the default and is unchanged when waves are off.

Source: the "wave execution" sketch in `docs/superpowers/notes/2026-09-15-iteration-loop.md`.

## Goal

A ten-task plan whose tasks mostly don't depend on each other currently runs as ten serial implement-review-fix loops. With waves it runs as two or three rounds of three to five concurrent loops, with one full-suite run per round. The per-task loop (brief, implementer, task review, fix rounds, breaker, rulings) is untouched; waves change only what happens around it.

## Non-goals

- A rolling scheduler that starts a task the moment its dependencies merge. Barrier waves first; revisit after a few real plans.
- Harness-native isolation (Claude Code's `isolation: "worktree"`). The controller owns worktrees so branch names, paths and cleanup are deterministic on every harness.
- Changing the per-task review or fix loop, model selection, or the final whole-branch review.
- Cross-task parallelism inside a single task (an implementer still never spawns subagents).

## Where it lives

- `skills/subagent-driven-development/waves.md`: the wave process, loaded only when waves are on. SKILL.md gets a short "Waves" subsection that states the opt-in, the invariants, and points here.
- `skills/subagent-driven-development/SKILL.md`: the line "Never dispatch multiple implementation subagents in parallel (conflicts)" becomes "Dispatch implementers serially unless the run is in wave mode (see waves.md); a wave is the only sanctioned concurrent dispatch, and it exists because each task has its own worktree." The Setup section says where the opt-in is read and that the pre-flight scan now also builds the graph. The Task Loop's step 1 gets one line: in wave mode, BASE is the wave base and the dispatch names the task's worktree.
- `skills/subagent-driven-development/scripts/task-worktree`: creates or reuses one task's worktree and branch and prints the path. Single source of truth for naming, the same reason `sdd-workspace` exists.
- `skills/writing-plans/SKILL.md`: task template gains a `**Depends on:**` line.
- The ledger format gains `Wave <W>:` lines.

## Opt-in

Waves run when any of these holds:

- Your human partner asks for it when handing over the plan ("execute this in waves", "run independent tasks in parallel").
- The plan header carries `**Execution:** waves`. writing-plans adds this line when your human partner asked for it during planning or chose it at the handoff menu; the default plan header has no Execution line.
- Their standing instructions (CLAUDE.md or equivalent) say to run plans in waves.

writing-plans offers the choice at the plan handoff when the graph allows it: it computes the waves from `Depends on` and Files the way "Scheduling a wave" does, and if the wave count is below the task count it replaces the "say go" line with a two-option menu (serial, or waves with the wave sizes shown). A chain graph gets no menu.

Absent both, SDD runs serially exactly as today. Wave mode is recorded as the second line of the ledger: `Execution: waves (cap 4)`. A later `Execution: serial (<reason>)` line records a fallback. On resume, the last `Execution:` line, not the conversation, says which mode the run is in.

Wave mode also falls back to serial, with a ledger note, when the harness can't run subagents concurrently, when worktree creation is denied (the sandbox case using-git-worktrees already covers), when the session is already inside a native worktree (Claude Code's EnterWorktree pins every subagent to it, so wave mode creates the plan worktree with plain `git worktree add` and stays in the launch directory), when a pre-wave probe shows subagents still cannot run git in a task worktree, or when the graph never yields two ready tasks with disjoint files.

## Plan format: `Depends on`

Every task in the writing-plans template gets, after `**Interfaces:**`:

```
**Depends on:** Task 2, Task 4
```

or `**Depends on:** none`. The rule for the plan writer: a task depends on every task whose Produces it Consumes, and on every earlier task that creates or modifies a file this task modifies. Nothing else. Listing a dependency that isn't one costs parallelism; omitting one costs a broken build, so when unsure, list it.

The line is required in every plan, whether or not waves are on. In serial mode it's documentation; the controller's pre-flight scan checks it either way (below), so plan defects surface early regardless of mode.

## Pre-flight: building the graph

SDD's pre-flight scan already produces a table with one row per pair of tasks sharing a file or interface. Three checks join the scan in both modes (the table already holds the inputs, and a wrong `Depends on` is a plan defect whether or not anything runs concurrently), each ruled on and ledgered like every other scan finding:

1. **Consumes without a dependency.** A task's Consumes names something a task produces that isn't in its `Depends on`. Ruling: add the edge. Ledger it.
2. **Shared file without a dependency.** Two tasks both list the same file under Files and neither depends on the other. Ruling: add an edge from the later task to the earlier. Ledger it.
3. **Cycle.** The plan is broken in the "every path forward is a guess" sense. Stop and ask.

The graph the controller executes is `Depends on` plus the edges the rulings added. In wave mode, write it to the ledger as one line per task: `Graph: Task 3 <- 1, 2`. In serial mode the rulings alone are recorded; the graph isn't consulted. Batched same-shape tasks (SDD's existing "Batch small same-shape work") are one node whose Files is the union of the batch.

## Scheduling a wave

Repeat until every task is complete:

1. **Ready set:** every task whose dependencies all have a `Task <N>: complete` line and which has no `complete` line itself.
2. **Wave selection:** walk the ready set in plan order. Add a task to the wave if its Files (Create, Modify, Test) share nothing with any task already in the wave. Stop at 4. Everything not selected waits for the next wave.
3. If the wave has one task, run it as the serial loop in the plan worktree. No task worktree, no merge, no separate suite run. The ledger still gets `Wave <W>:` lines so the wave count stays honest.
4. Otherwise run the wave (below).

The cap is 4. Lower it by ruling when project setup per worktree is expensive (a heavy dependency install, a slow build) and ledger the ruling. Never raise it.

## Running a wave

**Wave base.** `WAVE_BASE = git rev-parse HEAD` on the plan branch. Every task in the wave branches from it and every task's review BASE is it.

**Worktrees.** For each task N in the wave, from the plan worktree, run `scripts/task-worktree PLAN_FILE N` (default base: HEAD). It:

- creates `.worktrees/<plan-slug>/task-N` with branch `sdd/<plan-slug>/task-N` at the given base, or prints the existing path if both already exist (resume);
- refuses if the branch exists but points at a different worktree, or the directory exists without being a registered worktree;
- verifies `.worktrees` is git-ignored the way using-git-worktrees requires, and fails with that skill's message if not;
- prints the absolute worktree path.

Then run the project's setup in each worktree, as using-git-worktrees Step 2 describes (install dependencies, generate what needs generating). Skip that step's baseline test run: the wave base already passed the full suite at the previous barrier, or the initial worktree baseline. This is the cost the note called out; sharing a package store (pnpm, uv, a global cache) is the mitigation, and the skill says so once.

Ledger: `Wave <W>: start (base <sha7>, tasks 3, 4, 6)`.

**Dispatch.** Dispatch every implementer in the wave in a single message. Each dispatch is the existing implementer brief plus one paragraph:

> Your working directory is `<absolute worktree path>`, a git worktree on branch `sdd/<slug>/task-N`. Run every command there. Commit on that branch. Do not touch `<plan worktree path>` or any other worktree. Your report file is `<plan workspace>/task-N-report.md` (absolute path).

Briefs, reports and review packages stay in the plan workspace (`<plan worktree>/.superpowers/sdd/<slug>/`). The implementer writes its report by absolute path; nothing is created under the task worktree except the task's own code.

**Per-task loop.** Unchanged. Each task's review, fix rounds and breaker run against its own branch:

- Review package: `scripts/review-package PLAN_FILE WAVE_BASE sdd/<slug>/task-N`, run from the plan worktree. Worktrees share the object store, so the task branch's commits are visible there. The reviewer gets the task worktree path in case it needs to read a file the diff doesn't show.
- Fix rounds resume the implementer, which is still sitting in its worktree. FIX_BASE is the task branch head the previous review saw.
- Ledger lines are the existing `Task <N>: ...` lines. The wave a task ran in is recoverable from the `Wave <W>: start` line that lists it.

Handle reports as they arrive; while one task is in a fix round, others in the wave are still running or already complete. SDD's bounded-wait guidance applies unchanged.

**Barrier.** The wave is done when every task in it has a `complete` line (clean or parked at cap). Then, in the plan worktree:

1. **Disjointness check.** `git diff --name-only WAVE_BASE sdd/<slug>/task-N` for each task. Any file changed by two branches, or by one branch outside its declared Files, is ledgered: `Wave <W>: undeclared file <path> touched by Task <N>`. This is a plan-quality signal for the final review, not a stop.
2. **Merge.** In plan order: `git merge --no-ff sdd/<slug>/task-N -m "Merge Task N: <task name>"`. Files were disjoint by construction, so conflicts don't happen unless step 1 found an overlap. On conflict: `git merge --abort`, then one fix round on that task, resuming its implementer with "rebase `sdd/<slug>/task-N` onto `<current plan head>`, resolve the conflict in `<files>`, re-run the covering tests", followed by a scoped re-review of the rebased diff and a retried merge. That round counts toward the task's five. A second conflict on the same task is a graph defect: stop and ask.
3. **Suite.** Run the project's full test command once on the merged head.
4. **Suite failure.** Mirror the final-review pattern: ONE integration fixer (fresh implementer, standard model, working in the plan worktree, given the failing output, the wave's task list and the report paths), one scoped re-review over its diff, then adjudicate residuals as the breaker does. No second fix wave. Residual failures are adjudicated the same way the breaker adjudicates open findings, and are carried into every dispatch of the next wave as pre-existing failures.
5. **Cleanup.** `git worktree remove .worktrees/<slug>/task-N` and `git branch -d sdd/<slug>/task-N` for every task in the wave. Both are safe: the branch is merged, and the worktree holds nothing uncommitted (an implementer that ended with a dirty tree failed its own contract; if `worktree remove` refuses, inspect, and stop if the dirt is real work).

Ledger: `Wave <W>: merged (tasks 3, 4, 6 -> <sha7>, suite pass)` or `... suite fail, fix round -> <sha7>, suite pass)` or `... suite fail, fix round -> <sha7>, suite fail: <failing test names>)`.

The next wave's base is the merged head.

## Stop conditions

SDD's four stop classes are unchanged. Two clarifications the skill states outright:

- Merging a task branch into the plan branch is internal bookkeeping of this run, not the "merge to a shared branch" stop class. It never asks.
- A merge conflict that survives one rebase round, or a cycle in the graph, falls under "a plan so broken that every path forward is a guess". Stop and ask.

## Ledger and resume

New line shapes, all at the top level of the ledger alongside the existing `Task <N>:` lines:

```
Execution: waves (cap 4)
Graph: Task 3 <- 1, 2
Wave 2: start (base a1b2c3d, tasks 3, 4, 6)
Wave 2: undeclared file src/x.ts touched by Task 4
Wave 2: merged (tasks 3, 4, 6 -> e4f5a6b, suite pass)
```

A wave whose fix round leaves the suite red instead ledgers
`Wave 2: merged (tasks 3, 4, 6 -> e4f5a6b, suite fail, fix round -> f6a7b8c, suite fail: <failing test names>)`.

Resume rules, in addition to the existing ones:

- `Execution: waves` on line 2 means wave mode. No such line means serial, even if the conversation remembers otherwise.
- A `Wave <W>: start` with no matching `merged` line is a wave in flight. For each task it lists: a `complete` line means the branch is done and awaiting the barrier; fix-round lines mean resume the loop at the next round; nothing means dispatch (or re-dispatch) it. Run `task-worktree` for every task in the wave first; it reuses what exists and recreates what `git clean` or a crash removed, from the recorded base.
- `git worktree list` and `git branch --list 'sdd/<slug>/*'` are the ground truth for what exists, the same way `git log` is for commits.
- Task worktrees left behind by an abandoned run are cleaned up by the Finish step below, never by the next plan.

## Finish

Before deleting the plan workspace, the Finish step also removes any `.worktrees/<plan-slug>/` directory and any `sdd/<slug>/*` branch still present, after confirming each branch is merged (`git branch --merged`). An unmerged one is reported to your human partner under "Rulings I made" rather than deleted.

The final whole-branch review is unchanged: MERGE_BASE is the commit the plan branch started from, and the package covers every wave.

## Interfaces changed

- `writing-plans` task template: `**Depends on:**` line, required. Plan header: optional `**Execution:** waves`.
- `subagent-driven-development` SKILL.md: opt-in wording, the graph checks in pre-flight, the concurrent-dispatch rule, the pointer to `waves.md`.
- New `scripts/task-worktree PLAN_FILE N [BASE]`. Prints the worktree path. Exit codes: 0 created or reused, 2 usage or missing plan, 3 `.worktrees` not ignored, 4 branch or directory exists in an inconsistent state.
- Ledger: three new line shapes above. Existing `Task <N>:` lines unchanged, so a serial-mode ledger is still valid.

## Testing

- `tests/`: shell tests for `task-worktree` covering create, reuse, the inconsistent-state refusal, the not-ignored refusal, and an explicit BASE. These are the branches where a wrong exit would silently reuse the wrong worktree.
- `evals/`: one Drill scenario with a six-task plan whose graph is `1, 2 -> 3; 4 -> 5; 6` with disjoint files, run with waves on. The verifier checks: the ledger has an `Execution: waves` line, exactly two `Wave <W>: start` lines (tasks 1, 2, 4, 6 then 3, 5), a `merged` line per wave, and no task dispatched before its dependencies' `complete` lines. A second run of the same plan with waves off must produce no `Wave` lines and six serial dispatches, confirming the default is untouched.

## Costs and known trade-offs

- Project setup runs once per task worktree per wave. For a heavy install this can exceed the time saved; the cap-lowering ruling is the knob.
- Tasks in a wave are built blind to each other, so Produces/Consumes signatures must be exact. The plan format already demands this; waves make a sloppy interface line fail at the barrier instead of at the next task.
- The controller handles up to four reports arriving in any order. The report-file discipline keeps each one small; the risk is bookkeeping mistakes, which the ledger lines are designed to make visible.
- Merge commits accumulate on the plan branch. finishing-a-development-branch already offers squash, and the `--no-ff` commits give `git log` the wave boundaries until then.
