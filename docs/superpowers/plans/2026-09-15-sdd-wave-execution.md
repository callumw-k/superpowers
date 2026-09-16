# SDD Wave Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (superpowers:executing-plans only where subagents are unavailable). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let subagent-driven-development run independent plan tasks concurrently, one worktree per task, merged into the plan branch in barrier waves, as an opt-in mode that leaves serial SDD unchanged.

**Architecture:** A new `task-worktree` script owns worktree and branch naming. A new `waves.md` reference under the SDD skill carries the wave process (graph, scheduling, dispatch, barrier, ledger, resume). SDD's `SKILL.md` gains the opt-in, the graph checks in pre-flight, and a pointer to `waves.md`. The writing-plans task template gains a `Depends on` line so the controller has an explicit dependency graph.

**Tech Stack:** Bash (scripts and tests, ShellCheck-clean), Markdown skill prose.

**Spec:** `docs/superpowers/specs/2026-09-15-sdd-wave-execution-design.md`

## Global Constraints

- Serial SDD behaviour is unchanged when waves are off: no `Wave` ledger lines, no task worktrees, dispatch one implementer at a time.
- Worktree path: `<main-worktree-root>/.worktrees/<plan-basename>/task-<N>`. Branch: `sdd/<plan-basename>/task-<N>`.
- `task-worktree` exit codes: 0 created or reused, 2 usage or missing plan or bad BASE, 3 `.worktrees` not git-ignored, 4 branch or directory exists in an inconsistent state.
- Wave cap is 4. It may be lowered by ruling, never raised.
- Ledger line shapes (exact): `Execution: waves (cap 4)` on line 2; `Graph: Task <N> <- <deps>`; `Wave <W>: start (base <sha7>, tasks <list>)`; `Wave <W>: undeclared file <path> touched by Task <N>`; `Wave <W>: merged (tasks <list> -> <sha7>, suite pass)` or `Wave <W>: merged (tasks <list> -> <sha7>, suite fail, fix round -> <sha7>, suite pass)`.
- Plan format: `**Depends on:** Task 2, Task 4` or `**Depends on:** none`, placed directly after `**Interfaces:**` in every task. Optional plan header line `**Execution:** waves`.
- Skill prose uses the project's voice: "your human partner", imperative mood, no comments in scripts beyond the header block the sibling scripts already carry.
- Shell scripts pass `scripts/lint-shell.sh <file>` (ShellCheck).
- The Drill eval scenario in the spec's Testing section is out of this plan: `evals/` is a separate repository (`superpowers-evals`) not cloned into this checkout.

---

### Task 1: `task-worktree` script

**Files:**
- Create: `skills/subagent-driven-development/scripts/task-worktree`
- Create: `tests/claude-code/test-task-worktree.sh`
- Modify: `tests/claude-code/run-skill-tests.sh:75-79` (the `tests=(...)` array)

**Interfaces:**
- Consumes: nothing from other tasks. Reuses the `sdd-workspace` style: `set -euo pipefail`, header comment block, usage error exit 2.
- Produces: `scripts/task-worktree PLAN_FILE TASK_NUMBER [BASE]`. Prints the worktree's absolute path on stdout. Creates `<main-root>/.worktrees/<slug>/task-<N>` on branch `sdd/<slug>/task-<N>` at BASE (default: HEAD of the current worktree). Reuses an existing registered worktree on the right branch. Re-adds the worktree for an existing branch whose directory is gone. Exit codes per Global Constraints.

**Depends on:** none

- [ ] **Step 1: Write the failing test**

Create `tests/claude-code/test-task-worktree.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/task-worktree: one worktree and branch per plan task, with
# deterministic naming, reuse on repeat calls, and refusal on inconsistent state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TW="$REPO_ROOT/skills/subagent-driven-development/scripts/task-worktree"

FAILURES=0
TEST_ROOT=""

pass() { echo "  [PASS] $1"; }
fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

cleanup() {
    if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

GIT_ID=(-c user.email=t@example.com -c user.name=t -c commit.gpgsign=false)

expect_exit() {
    local want=$1 desc=$2
    shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq "$want" ]]; then
        pass "$desc"
    else
        fail "$desc"
        echo "    exit: $rc (wanted $want)"
    fi
}

main() {
    echo "=== Test: task-worktree ==="

    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    git init -q -b main "$TEST_ROOT/repo"
    local repo
    repo="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    cat > "$repo/plan-a.md" <<'PLAN'
# Plan A

### Task 1: First thing

Do the first thing.
PLAN
    ( cd "$repo" && git add plan-a.md && git "${GIT_ID[@]}" commit -qm c1 )
    local c1
    c1="$(cd "$repo" && git rev-parse HEAD)"

    # --- argument validation ---
    expect_exit 2 "no arguments errors with exit 2" bash -c "cd '$repo' && '$TW'"
    expect_exit 2 "missing plan file errors with exit 2" bash -c "cd '$repo' && '$TW' nope.md 1"
    expect_exit 2 "non-integer task number errors with exit 2" bash -c "cd '$repo' && '$TW' plan-a.md one"
    expect_exit 2 "unknown BASE errors with exit 2" bash -c "cd '$repo' && '$TW' plan-a.md 1 no-such-ref"

    # --- .worktrees must be ignored ---
    expect_exit 3 "refuses when .worktrees is not git-ignored" bash -c "cd '$repo' && '$TW' plan-a.md 1"
    if [[ ! -e "$repo/.worktrees" ]]; then
        pass "creates nothing when refusing on ignore check"
    else
        fail "creates nothing when refusing on ignore check"
    fi

    ( cd "$repo" && printf '.worktrees/\n' > .gitignore && git add .gitignore && git "${GIT_ID[@]}" commit -qm ignore )
    local c2
    c2="$(cd "$repo" && git rev-parse HEAD)"

    # --- create ---
    local out
    out="$(cd "$repo" && "$TW" plan-a.md 1)"
    if [[ "$out" == "$repo/.worktrees/plan-a/task-1" ]]; then
        pass "prints <main-root>/.worktrees/<plan>/task-<N>"
    else
        fail "prints <main-root>/.worktrees/<plan>/task-<N>"
        echo "    got: $out"
    fi
    if [[ "$(cd "$out" && git rev-parse --abbrev-ref HEAD)" == "sdd/plan-a/task-1" ]]; then
        pass "worktree is on branch sdd/<plan>/task-<N>"
    else
        fail "worktree is on branch sdd/<plan>/task-<N>"
    fi
    if [[ "$(cd "$out" && git rev-parse HEAD)" == "$c2" ]]; then
        pass "default BASE is the caller's HEAD"
    else
        fail "default BASE is the caller's HEAD"
    fi

    # --- reuse ---
    local again
    again="$(cd "$repo" && "$TW" plan-a.md 1)"
    local count
    count="$(cd "$repo" && git worktree list --porcelain | grep -c '^worktree ')"
    if [[ "$again" == "$out" && "$count" -eq 2 ]]; then
        pass "second call reuses the worktree and adds nothing"
    else
        fail "second call reuses the worktree and adds nothing"
        echo "    got: $again, worktrees: $count"
    fi

    # --- explicit BASE ---
    local t2
    t2="$(cd "$repo" && "$TW" plan-a.md 2 "$c1")"
    if [[ "$(cd "$t2" && git rev-parse HEAD)" == "$c1" ]]; then
        pass "explicit BASE is honoured"
    else
        fail "explicit BASE is honoured"
    fi

    # --- inconsistent states ---
    mkdir -p "$repo/.worktrees/plan-a/task-3"
    expect_exit 4 "unregistered directory at the target path errors with exit 4" \
        bash -c "cd '$repo' && '$TW' plan-a.md 3"

    ( cd "$repo" && git worktree add -q "$TEST_ROOT/elsewhere" -b sdd/plan-a/task-4 )
    expect_exit 4 "branch checked out at another path errors with exit 4" \
        bash -c "cd '$repo' && '$TW' plan-a.md 4"

    ( cd "$repo" && git worktree add -q "$repo/.worktrees/plan-a/task-5" -b unrelated )
    expect_exit 4 "target path on the wrong branch errors with exit 4" \
        bash -c "cd '$repo' && '$TW' plan-a.md 5"

    # --- recreate after the directory is removed, keeping the branch's commits ---
    ( cd "$out" && printf 'w\n' > work && git add work && git "${GIT_ID[@]}" commit -qm work )
    local work_sha
    work_sha="$(cd "$out" && git rev-parse HEAD)"
    rm -rf "$out"
    local back
    back="$(cd "$repo" && "$TW" plan-a.md 1)"
    if [[ "$back" == "$out" && -d "$back" && "$(cd "$back" && git rev-parse HEAD)" == "$work_sha" ]]; then
        pass "re-adds a removed worktree on its existing branch, commits intact"
    else
        fail "re-adds a removed worktree on its existing branch, commits intact"
        echo "    got: $back"
    fi

    # --- called from a linked worktree: path under the main root, BASE from the caller ---
    local plan_wt="$TEST_ROOT/plan-wt"
    ( cd "$repo" && git worktree add -q "$plan_wt" -b feature )
    ( cd "$plan_wt" && printf 'f\n' > f && git add f && git "${GIT_ID[@]}" commit -qm feature )
    local feature_sha
    feature_sha="$(cd "$plan_wt" && git rev-parse HEAD)"
    local t6
    t6="$(cd "$plan_wt" && "$TW" plan-a.md 6)"
    if [[ "$t6" == "$repo/.worktrees/plan-a/task-6" && "$(cd "$t6" && git rev-parse HEAD)" == "$feature_sha" ]]; then
        pass "from a linked worktree: path under main root, BASE is the linked worktree's HEAD"
    else
        fail "from a linked worktree: path under main root, BASE is the linked worktree's HEAD"
        echo "    got: $t6"
    fi

    echo ""
    if [[ "$FAILURES" -ne 0 ]]; then
        echo "FAILED: $FAILURES assertion(s)."
        exit 1
    fi
    echo "PASS"
}

main "$@"
```

Note: `plan-a.md` is committed in `$repo` before the linked-worktree case so it exists in `$plan_wt` too.

- [ ] **Step 2: Run the test to verify it fails**

Run: `chmod +x tests/claude-code/test-task-worktree.sh && bash tests/claude-code/test-task-worktree.sh`
Expected: FAIL. The first `expect_exit` calls fail because `$TW` does not exist (exit 127, wanted 2).

- [ ] **Step 3: Write the script**

Create `skills/subagent-driven-development/scripts/task-worktree` (mode 755):

```bash
#!/usr/bin/env bash
# Create or reuse the worktree and branch for one plan task in SDD wave mode,
# and print the worktree's absolute path.
#
# Worktree: <main-worktree-root>/.worktrees/<plan-basename>/task-<N>
# Branch:   sdd/<plan-basename>/task-<N>
#
# Task worktrees hang off the MAIN worktree root, not the caller's, so a plan
# running in .worktrees/feature/ gets siblings under .worktrees/ rather than a
# nested .worktrees/ inside its own tree. BASE resolves in the caller's
# worktree, so "HEAD" means the plan branch's head.
#
# Single source of truth for naming, so resume can find what an earlier run
# created and the merge step knows which branch to merge.
#
# Usage: task-worktree PLAN_FILE TASK_NUMBER [BASE]
# Exit: 0 created or reused; 2 usage, missing plan, bad BASE;
#       3 .worktrees not git-ignored; 4 branch or directory in an
#       inconsistent state (wrong branch at the path, unregistered directory,
#       branch checked out elsewhere).
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: task-worktree PLAN_FILE TASK_NUMBER [BASE]" >&2
  exit 2
fi

plan=$1
n=$2
base=${3:-HEAD}
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
case "$n" in
  ''|*[!0-9]*) echo "TASK_NUMBER must be an integer: $n" >&2; exit 2 ;;
esac

slug=$(basename "$plan" .md)
case "$slug" in
  ''|.|..) echo "cannot derive a name from: $plan" >&2; exit 2 ;;
esac

base_sha=$(git rev-parse --verify --quiet "${base}^{commit}") \
  || { echo "bad BASE: $base" >&2; exit 2; }

main_root=$(git worktree list --porcelain | awk 'NR==1 { sub(/^worktree /, ""); print }')
dir="$main_root/.worktrees/$slug/task-$n"
branch="sdd/$slug/task-$n"
ref="refs/heads/$branch"

git -C "$main_root" check-ignore -q .worktrees \
  || { echo ".worktrees is not git-ignored in $main_root; add it to .gitignore first" >&2; exit 3; }

git -C "$main_root" worktree prune

porcelain=$(git -C "$main_root" worktree list --porcelain)
dir_branch=$(printf '%s\n' "$porcelain" \
  | awk -v d="$dir" '$1 == "worktree" { sub(/^worktree /, ""); cur = $0 } $1 == "branch" && cur == d { print $2 }')
branch_path=$(printf '%s\n' "$porcelain" \
  | awk -v b="$ref" '$1 == "worktree" { sub(/^worktree /, ""); cur = $0 } $1 == "branch" && $2 == b { print cur }')

if [ -n "$dir_branch" ]; then
  [ "$dir_branch" = "$ref" ] \
    || { echo "$dir is a worktree on ${dir_branch#refs/heads/}, expected $branch" >&2; exit 4; }
  printf '%s\n' "$dir"
  exit 0
fi

[ ! -e "$dir" ] || { echo "$dir exists but is not a registered worktree" >&2; exit 4; }

mkdir -p "$(dirname "$dir")"
if git -C "$main_root" rev-parse --verify --quiet "$ref" >/dev/null; then
  [ -z "$branch_path" ] || { echo "$branch is already checked out at $branch_path" >&2; exit 4; }
  git -C "$main_root" worktree add -q "$dir" "$branch"
else
  git -C "$main_root" worktree add -q "$dir" -b "$branch" "$base_sha"
fi

printf '%s\n' "$dir"
```

Then `chmod +x skills/subagent-driven-development/scripts/task-worktree`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/claude-code/test-task-worktree.sh`
Expected: every line `[PASS]`, final `PASS`.

If "from a linked worktree" fails on macOS with a `/private/var` vs `/var` mismatch, the test already resolves `$repo` via `git rev-parse --show-toplevel`; check `main_root` in the script is what `git worktree list` prints and compare against that rather than against `$TEST_ROOT`.

- [ ] **Step 5: Lint**

Run: `scripts/lint-shell.sh skills/subagent-driven-development/scripts/task-worktree tests/claude-code/test-task-worktree.sh`
Expected: no ShellCheck findings. Fix any that appear before continuing.

- [ ] **Step 6: Register the test**

In `tests/claude-code/run-skill-tests.sh`, change:

```bash
tests=(
    "test-worktree-path-policy.sh"
    "test-sdd-workspace.sh"
    "test-subagent-driven-development.sh"
)
```

to:

```bash
tests=(
    "test-worktree-path-policy.sh"
    "test-sdd-workspace.sh"
    "test-task-worktree.sh"
    "test-subagent-driven-development.sh"
)
```

- [ ] **Step 7: Commit**

```bash
git add skills/subagent-driven-development/scripts/task-worktree tests/claude-code/test-task-worktree.sh tests/claude-code/run-skill-tests.sh
git commit -m "Add task-worktree script for SDD wave mode"
```

---

### Task 2: `Depends on` and `Execution` in the writing-plans template

**Files:**
- Modify: `skills/writing-plans/SKILL.md:63-79` (plan header) and `skills/writing-plans/SKILL.md:85-97` (task structure)

**Interfaces:**
- Consumes: nothing.
- Produces: the plan-format lines `**Depends on:** Task 2, Task 4` / `**Depends on:** none` and the optional header line `**Execution:** waves`, which `waves.md` (Task 3) and SDD `SKILL.md` (Task 4) read.

**Depends on:** none

- [ ] **Step 1: Add the optional Execution header line**

In `skills/writing-plans/SKILL.md`, inside the "Plan Document Header" code block, change:

```markdown
**Spec:** [path to the spec/design doc this plan implements — the plan
argues from the spec, so the spec travels with it; executors read both]

## Global Constraints
```

to:

```markdown
**Spec:** [path to the spec/design doc this plan implements — the plan
argues from the spec, so the spec travels with it; executors read both]

**Execution:** waves [ONLY when your human partner asked for concurrent
execution during planning; otherwise omit this line entirely — SDD runs
tasks serially by default]

## Global Constraints
```

- [ ] **Step 2: Add Depends on to the task structure**

In the "Task Structure" code block, change:

```markdown
**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]

- [ ] **Step 1: Write the failing test**
```

to:

```markdown
**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]

**Depends on:** [Task 2, Task 4 — or `none`. Every task whose Produces
this task Consumes, and every earlier task that creates or modifies a
file this task modifies. Nothing else. A dependency that isn't one costs
parallelism; a missing one costs a broken build, so when unsure, list it.]

- [ ] **Step 1: Write the failing test**
```

- [ ] **Step 3: Add the Depends on rule to the No Placeholders list**

Change:

```markdown
- References to types, functions, or methods not defined in any task
```

to:

```markdown
- References to types, functions, or methods not defined in any task
- A task without a `**Depends on:**` line, or one that names a task whose Produces it does not Consume and whose files it does not touch
```

- [ ] **Step 4: Verify**

Run: `rg -n "Depends on|Execution:" skills/writing-plans/SKILL.md`
Expected: two hits for `Depends on` (the template line and the No Placeholders bullet) and one for `Execution:`.

- [ ] **Step 5: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "Add Depends on and Execution lines to the plan template"
```

---

### Task 3: `waves.md` reference

**Files:**
- Create: `skills/subagent-driven-development/waves.md`

**Interfaces:**
- Consumes: `scripts/task-worktree PLAN_FILE N [BASE]` (Task 1): prints the worktree path, exit codes 0/2/3/4. Plan lines `**Depends on:**` and `**Execution:** waves` (Task 2). Existing scripts `sdd-workspace`, `task-brief`, `review-package`, and templates `implementer-prompt.md`, `re-review-prompt.md`, `task-reviewer-prompt.md`.
- Produces: the file `waves.md`, whose section headings SDD `SKILL.md` (Task 4) points at: "Pre-flight: the graph", "Scheduling a wave", "Running a wave", "The barrier", "Ledger and resume", "Finish".

**Depends on:** Task 1, Task 2

- [ ] **Step 1: Write the file**

Create `skills/subagent-driven-development/waves.md`:

````markdown
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

Tasks you batch under SKILL.md's "Batch small same-shape work" are one node
whose Files is the union of the batch.

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
   ledger matches what happened.
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
run, goes serial; ledger it.

Run the project's setup in each worktree as using-git-worktrees Step 2
describes (install dependencies, generate what needs generating). Skip that
step's baseline test run: the wave base passed the full suite at the previous
barrier, or at the plan worktree's own baseline. Per-worktree setup is the
wave's main cost; a shared package store (pnpm, uv, a global cache) is what
makes it cheap.

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
   covering tests", run a scoped re-review over the rebased diff, and retry
   the merge. The round counts toward the task's five. A second conflict on
   the same task is a graph defect: stop and ask.
3. **Suite.** Run the project's full test command once on the merged head.
4. **Suite failure.** As the final-review fix wave in SKILL.md: ONE
   integration fixer (fresh implementer, standard model, `Work from:` the
   plan worktree, given the failing output, the wave's task list and their
   report paths), one scoped re-review over its diff, then adjudicate
   residuals as the breaker does. No second fix wave.
5. **Cleanup.** For every task in the wave:
   `git worktree remove .worktrees/<plan>/task-N` and
   `git branch -d sdd/<plan>/task-N`. Both are safe: the branch is merged
   and the worktree holds nothing uncommitted. If `worktree remove` refuses
   because the tree is dirty, the implementer broke its contract; look at
   what is there, and stop if it is real work.

Ledger: `Wave <W>: merged (tasks 3, 4, 6 -> <sha7>, suite pass)`, or
`Wave <W>: merged (tasks 3, 4, 6 -> <sha7>, suite fail, fix round -> <sha7>, suite pass)`.

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
  Run `task-worktree` for every task it lists first; it reuses what exists
  and re-adds what a crash or `git clean` removed. Then, per task: a
  `complete` line means the branch is done and waiting for the barrier;
  fix-round lines mean resume the loop at the next round; nothing means
  dispatch it.
- `git worktree list` and `git branch --list 'sdd/<plan>/*'` are the ground
  truth for what exists, as `git log` is for commits.

## Finish

Before deleting the plan workspace, remove any `.worktrees/<plan>/` directory
and any `sdd/<plan>/*` branch still present, after confirming each branch is
merged (`git branch --merged`). Report an unmerged one under "Rulings I made"
instead of deleting it. Task worktrees left by an abandoned run are this
step's to clean, never the next plan's.

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
````

- [ ] **Step 2: Verify**

Run: `rg -n "^## " skills/subagent-driven-development/waves.md`
Expected headings, in order: Pre-flight: the graph, Scheduling a wave, Running a wave, The barrier, Ledger and resume, Finish, Common Rationalizations.

Run: `rg -n "task-worktree|review-package|Depends on|Execution: waves" skills/subagent-driven-development/waves.md | wc -l`
Expected: at least 6.

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/waves.md
git commit -m "Add wave execution reference for subagent-driven-development"
```

---

### Task 4: Wire waves into SDD `SKILL.md`

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:124-182` (Setup), `:246-249` (Task Loop step 1), `:282` (parallel-dispatch rule), `:444` (before Final Review), `:471-487` (Finish)

**Interfaces:**
- Consumes: `waves.md` (Task 3) and its headings; `**Execution:** waves` header line and `**Depends on:**` (Task 2); `scripts/task-worktree` (Task 1).
- Produces: nothing downstream.

**Depends on:** Task 1, Task 2, Task 3

- [ ] **Step 1: Opt-in in Setup**

In `skills/subagent-driven-development/SKILL.md`, Setup section, directly after the paragraph that begins "Read the plan once, note its context and Global Constraints" and ends "rulings made without one are provisional.", insert this paragraph:

```markdown
Decide the execution mode now and write it as the ledger's second line.
Wave mode (`Execution: waves (cap 4)`) is on only when your human partner
asked for concurrent execution when handing you the plan, or the plan
header carries `**Execution:** waves`. Otherwise the run is serial and the
ledger has no `Execution:` line. On resume, that line decides the mode, not
your memory. Wave mode is described in [waves.md](waves.md); read it before
the pre-flight scan, because the scan's graph checks feed it.
```

- [ ] **Step 2: Graph checks in the pre-flight scan**

Change the pre-flight bullet list:

```markdown
- tasks that contradict each other or the plan's Global Constraints
- anything the plan explicitly mandates that the review rubric treats as a
  defect (a test that asserts nothing, verbatim duplication of a logic block)
```

to:

```markdown
- tasks that contradict each other or the plan's Global Constraints
- anything the plan explicitly mandates that the review rubric treats as a
  defect (a test that asserts nothing, verbatim duplication of a logic block)
- `Depends on` lines that disagree with Files and Interfaces: a Consumes
  whose producer isn't listed, a shared file with no edge between the two
  tasks, or a cycle (waves.md, "Pre-flight: the graph"). Rule on the first
  two by adding the edge; a cycle stops you.
```

- [ ] **Step 3: BASE in wave mode**

Change:

```markdown
Record BASE (`git rev-parse HEAD`) before dispatching — the review package
and fix-round diffs need it.
```

to:

```markdown
Record BASE (`git rev-parse HEAD`) before dispatching — the review package
and fix-round diffs need it. In wave mode BASE is the wave base, and the
dispatch's `Work from:` names the task's worktree (waves.md, "Running a
wave").
```

- [ ] **Step 4: Replace the parallel-dispatch rule**

Change:

```markdown
- Never dispatch multiple implementation subagents in parallel (conflicts).
```

to:

```markdown
- Dispatch implementers serially unless the run is in wave mode. A wave is
  the only sanctioned concurrent dispatch, and it is safe only because each
  task has its own worktree and the tasks share no files (waves.md).
```

- [ ] **Step 5: Waves section**

Insert before `## Final Review`:

```markdown
## Waves

In wave mode the task loop runs for several tasks at once, one worktree per
task, and the wave ends with a barrier: merge every task branch into the plan
branch, run the full suite once, clean up the worktrees, start the next wave
from the merged head. Up to four tasks per wave; tasks in a wave share no
files and branch from the same commit, so their merges cannot conflict. The
per-task loop above is unchanged inside a wave. The process, the `Wave <W>:`
ledger lines and the resume rules are in [waves.md](waves.md).
```

- [ ] **Step 6: Finish cleanup**

Change:

```markdown
When the final whole-branch review is clean and its fixes are merged,
delete this plan's workspace (`rm -rf <workspace>`) — the git history is
the record now. Sibling directories belong to other plans; leave them
alone.
```

to:

```markdown
When the final whole-branch review is clean and its fixes are merged,
delete this plan's workspace (`rm -rf <workspace>`) — the git history is
the record now. Sibling directories belong to other plans; leave them
alone. In wave mode, first remove any `.worktrees/<plan>/` directory and
`sdd/<plan>/*` branch still present (waves.md, "Finish").
```

- [ ] **Step 7: Verify**

Run: `rg -n "waves.md|Execution: waves|wave mode" skills/subagent-driven-development/SKILL.md`
Expected: hits in Setup (two), pre-flight list, Task Loop step 1, the dispatch rule, the Waves section, and Finish. Seven or more lines.

Run: `rg -n "Never dispatch multiple" skills/subagent-driven-development/SKILL.md`
Expected: no output.

Run: `bash tests/claude-code/test-task-worktree.sh && bash tests/claude-code/test-sdd-workspace.sh`
Expected: both print `PASS`.

- [ ] **Step 8: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "Wire opt-in wave execution into subagent-driven-development"
```
