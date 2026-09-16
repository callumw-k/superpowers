# Wave Execution

Run independent plan tasks concurrently, each in its own worktree, and merge
them into the plan branch in barrier waves. Read this only when the run is in
wave mode (see SKILL.md, Setup). Everything not described here is unchanged:
the brief, the implementer, the task review, the fix loop, the breaker,
rulings, model selection, the final review.

**Why waves:** a ten-task plan whose tasks mostly don't depend on each other
is ten serial implement-review-fix loops. In waves it is two or three rounds
of up to four concurrent loops, with one full-suite run per round.

**The invariant that makes it safe:** tasks in one wave touch disjoint files
and branch from the same commit, so their merges cannot conflict. Every rule
below exists to keep that true or to notice when it wasn't.

## Pre-flight: the graph

The pre-flight scan in SKILL.md already tables every pair of tasks sharing a
file or interface. Three checks join it (in wave mode and serial mode alike;
a wrong `Depends on` is a plan defect either way), each ruled on and ledgered
like every other scan finding:

1. **Consumes without a dependency.** A task Consumes something another task
   Produces, and that task is not in its `Depends on`. Ruling: add the edge.
2. **Shared file without a dependency.** Two tasks list the same file under
   Files and neither depends on the other. Ruling: the later task depends on
   the earlier.
3. **Cycle.** Every path forward is a guess. Stop and ask.

The graph you execute is the plan's `Depends on` lines plus the edges your
rulings added. Write it to the ledger, one line per task:

```
Graph: Task 3 <- 1, 2
Graph: Task 4 <- none
```

Tasks you batch under SKILL.md's "Batch small same-shape work" are one node:
its branch and worktree take the lowest task number in the batch, and the
`Wave` line lists every number.

## Scheduling a wave

Repeat until every task has a `Task <N>: complete` line:

1. **Ready set:** tasks with no `complete` line whose every dependency has
   one.
2. **Select:** walk the ready set in plan order. Add a task if its Files
   (Create, Modify, Test) share nothing with any task already selected.
   Stop at 4. The rest wait for the next wave.
3. **One task selected:** run it as the serial loop in the plan worktree.
   No task worktree, no merge, no separate suite run. Still write the
   `Wave <W>: start` and `Wave <W>: merged` lines so the wave count in the
   ledger matches what happened — the `merged` line reads
   `Wave <W>: merged (tasks 5 -> <sha7>, no barrier)`, since no barrier
   suite ran.
4. **Two or more:** run the wave.

The cap is 4. Lower it by ruling when per-worktree setup is expensive (a
heavy dependency install, a slow code generation step) and ledger the ruling.
Never raise it: past four, you are reconciling reports faster than you can
read them, and the barrier waits on the slowest task anyway.

## Running a wave

**Wave base.** `WAVE_BASE=$(git rev-parse HEAD)` on the plan branch. Every
task in the wave branches from it, and every task's review BASE is it.

**Worktrees.** From the plan worktree, for each task N in the wave:

```
scripts/task-worktree PLAN_FILE N
```

It prints the worktree path (`<main-root>/.worktrees/<plan>/task-N`, branch
`sdd/<plan>/task-N`, at your HEAD). It reuses a worktree that already exists
on the right branch and re-adds one whose directory was removed, so it is
safe to run on resume. Exit 3 means `.worktrees` is not git-ignored: fix that
the way using-git-worktrees says, then rerun. Exit 4 means the branch or
directory is in a state this run did not create: inspect before continuing.
Worktree creation denied by the sandbox means this wave, and the rest of the
run, goes serial; ledger it. If your harness cannot run subagents
concurrently, the run is serial from the start; ledger it and skip this
file.

Run the project's setup in each worktree as using-git-worktrees Step 2
describes (install dependencies, generate what needs generating). Skip that
step's baseline test run when the previous barrier ran the full suite on the
wave base; its ledger line says what, if anything, was still failing. Before
the first multi-task wave, or after a `no barrier` wave, run the baseline
once in the plan worktree and ledger any pre-existing failures.
Per-worktree setup is the wave's main cost; a shared package store (pnpm,
uv, a global cache) is what makes it cheap.

Ledger: `Wave <W>: start (base <sha7>, tasks 3, 4, 6)`.

**Dispatch.** Dispatch every implementer in the wave in one message, each
built from implementer-prompt.md exactly as in serial mode, with two changes:

- `Work from:` names the task's worktree path.
- The Context section ends with this paragraph, filled in:

  > Your working directory is `<worktree path>`, a git worktree on branch
  > `sdd/<plan>/task-N`. Run every command there. Commit on that branch.
  > Do not touch `<plan worktree path>` or any other worktree. Write your
  > report to `<plan workspace>/task-N-report.md` (absolute path).

Briefs, reports and review packages stay in the plan workspace under the plan
worktree. Nothing is created in a task worktree except the task's own code.

**Per-task loop.** Unchanged, running against the task's branch:

- Review package: `scripts/review-package PLAN_FILE WAVE_BASE sdd/<plan>/task-N`
  from the plan worktree. Worktrees share one object store, so the branch is
  visible there. Give the reviewer the task worktree path as well, for files
  the diff doesn't show.
- Fix rounds resume the implementer, which is still in its worktree.
  FIX_BASE is the task branch head the previous review saw.
- Ledger lines are the existing `Task <N>:` lines. Which wave a task ran in
  is recoverable from the `Wave <W>: start` line that lists it.

Reports arrive in any order. Handle each as it lands; one task in a fix round
does not hold the others. SKILL.md's bounded-wait guidance applies.

## The barrier

The wave is done when every task in it has a `complete` line, clean or parked
at cap. Then, in the plan worktree:

1. **Disjointness check.** For each task,
   `git diff --name-only WAVE_BASE sdd/<plan>/task-N`. A file changed by two
   branches, or by one branch outside its declared Files, gets a ledger line:
   `Wave <W>: undeclared file <path> touched by Task <N>`. This is a
   plan-quality signal for the final review, not a stop.
2. **Merge**, in plan order:
   `git merge --no-ff sdd/<plan>/task-N -m "Merge Task N: <task name>"`.
   Disjoint files cannot conflict, so a conflict means step 1 found an
   overlap. On conflict: `git merge --abort`, then one fix round on that
   task: resume its implementer with "rebase `sdd/<plan>/task-N` onto
   `<current plan head>`, resolve the conflict in `<files>`, re-run the
   covering tests", then
   `scripts/review-package PLAN_FILE <current plan head> sdd/<plan>/task-N`
   and a re-review scoped to "new breakage in the conflict files only" —
   the task's own findings were already closed before its `complete` line
   — and retry the merge. The round counts toward the task's five. After
   the retried merge succeeds, append a fresh
   `Task <N>: complete (commits <plan-head7>..<branch-head7>, conflict
   round)` line so SKILL.md's "last line is a fix round means mid-loop"
   resume rule does not misfire. A second conflict on the same task is a
   graph defect: stop and ask.
3. **Suite.** Run the project's full test command once on the merged head.
4. **Suite failure.** As the final-review fix dispatch in SKILL.md: ONE
   integration fixer (fresh implementer, standard model, `Work from:` the
   plan worktree, given the failing output, the wave's task list and their
   report paths), one scoped re-review over its diff, then adjudicate
   residuals as the breaker does. No second fix dispatch. If the suite is
   still red, adjudicate the residual failures as the breaker does: rule,
   ledger, and carry the failing test names into every dispatch of the next
   wave as pre-existing failures, the way using-git-worktrees treats a
   dirty baseline. Stop only if the failures leave every path forward a
   guess.
5. **Cleanup.** For every task in the wave:
   `git worktree remove <the path task-worktree printed>` and
   `git branch -d sdd/<plan>/task-N`. Both are safe: the branch is merged
   and the worktree holds nothing uncommitted. If `worktree remove` refuses
   because the tree is dirty, the implementer broke its contract; look at
   what is there, and stop if it is real work.

Ledger: `Wave <W>: merged (tasks 3, 4, 6 -> <sha7>, suite pass)`, or
`Wave <W>: merged (tasks 3, 4, 6 -> <sha7>, suite fail, fix round -> <sha7>, suite pass)`, or
`Wave <W>: merged (tasks 3, 4, 6 -> <sha7>, suite fail, fix round -> <sha7>, suite fail: <failing test names>)`.

The next wave's base is the merged head.

**Stop conditions.** SKILL.md's four classes, unchanged, with two
clarifications:

- Merging a task branch into the plan branch is this run's own bookkeeping,
  not the "merge to a shared branch" class. It never asks.
- A conflict that survives one rebase round, or a cycle in the graph, is "a
  plan so broken that every path forward is a guess". Stop and ask.

## Ledger and resume

New line shapes, alongside the existing `Task <N>:` lines:

```
# SDD ledger — plan: docs/superpowers/plans/feature.md
Execution: waves (cap 4)
Graph: Task 3 <- 1, 2
Wave 2: start (base a1b2c3d, tasks 3, 4, 6)
Wave 2: undeclared file src/x.ts touched by Task 4
Wave 2: merged (tasks 3, 4, 6 -> e4f5a6b, suite pass)
```

Resume rules, on top of SKILL.md's:

- `Execution: waves` on line 2 means wave mode. No such line means serial,
  whatever the conversation remembers.
- A `Wave <W>: start` with no matching `merged` line is a wave in flight.
  For a wave listing two or more tasks, run `task-worktree` for each first;
  it reuses what exists and re-adds what a crash or `git clean` removed. A
  wave listing one task resumes under SKILL.md's rules, in the plan
  worktree. Then, per task: a `complete` line means the branch is done and
  waiting for the barrier; fix-round lines mean resume the loop at the next
  round; nothing means dispatch it.
- `git worktree list` and `git branch --list 'sdd/<plan>/*'` are the ground
  truth for what exists, as `git log` is for commits.

## Finish

Before deleting the plan workspace, remove any `<main-root>/.worktrees/<plan>/`
directory and any `sdd/<plan>/*` branch still present, after confirming each
branch is merged (`git branch --merged`). Report an unmerged one under
"Rulings I made" instead of deleting it. Task worktrees left by an abandoned
run are this step's to clean, never the next plan's.

The final whole-branch review is unchanged: MERGE_BASE is the commit the plan
branch started from, and the package covers every wave.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "These two tasks only share a test helper, run them together" | Shared file means same wave is forbidden. The later one waits, or the plan gets an edge. |
| "Five ready tasks, the cap is arbitrary" | The cap is where report handling stops being reliable. Spill to the next wave. |
| "The merges were clean, skip the suite" | Disjoint files still interact at runtime. One suite run per wave is the whole safety net. |
| "The worktree is dirty, I'll just `--force` the remove" | Dirt after a `complete` line is either a broken contract or lost work. Look first. |
| "I remember which wave we were in" | The ledger's `Wave` lines and `git worktree list` remember. You were compacted. |
