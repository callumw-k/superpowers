---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `superpowers:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Task Right-Sizing

A task is the smallest unit that carries its own test cycle and is worth a
fresh reviewer's gate. When drawing task boundaries: fold setup,
configuration, scaffolding, and documentation steps into the task whose
deliverable needs them; split only where a reviewer could meaningfully
reject one task while approving its neighbor. Each task ends with an
independently testable deliverable.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (superpowers:executing-plans only where subagents are unavailable). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** [path to the spec/design doc this plan implements — the plan
argues from the spec, so the spec travels with it; executors read both]

**Execution:** [waves — ONLY when your human partner asked for concurrent
execution during planning or chose it at the handoff menu; otherwise omit
this line entirely, SDD runs tasks serially by default]

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits,
naming and copy rules, platform requirements — one line each, with exact
values copied verbatim from the spec. Every task's requirements implicitly
include this section.]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

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

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task
- A task without a `**Depends on:**` line, or one that names a task whose Produces it does not Consume and whose files it does not touch

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, pick the execution skill yourself and state it in the same message that asks for plan approval. Do not ask which approach.

**Unattended mode.** When
`test -f "$(git rev-parse --show-toplevel)/.superpowers/ticket.json"`
passes and that file's `unattended` is true, there is no one to approve
the plan. Compute the waves and run the pin check as described under "Offer
waves" below. Add `**Execution:** waves` to the plan header only when the
wave count is below the task count and the pin check does not refuse; when
it refuses, leave the line out however the waves came out, as the
interactive path does. Save the plan as
`docs/superpowers/plans/<YYYY-MM-DD>-<key>-<feature-name>.md`, with `<key>`
as `autonomous-ticket` defines it, so the orchestrator's artefact check
finds it. Commit the plan on the current branch and end the turn. No menu,
no "say go", no Herdr offer, no handoff: the orchestrator starts the
executor. A spec requirement the plan cannot cover without a guess is a
blocker under `autonomous-ticket`'s `## Blockers`.

**Default:**
- **REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development
- Fresh subagent per task + two-stage review
- Say: "Plan saved to `docs/superpowers/plans/<filename>.md`. I'll execute it with subagent-driven-development. Review the plan and say go."

**Offer a Herdr tab when running inside Herdr.** Check
`test "${HERDR_ENV:-}" = 1` before the handoff message. When it passes,
the default message and the waves menu also offer to run
subagent-driven-development in a new Herdr tab (Sonnet): the default
message ends `say go, or go herdr to run it in a new Herdr tab (Sonnet)`,
and the waves menu carries the line shown there. If your human partner
picks it, follow `herdr-handoff.md` in this skill's directory as the
executor. The inline path is unaffected. When the check fails, say nothing
about Herdr.

**Offer waves when the graph allows them.** Before the handoff message,
compute the waves from the tasks' `Depends on` and Files the way
subagent-driven-development's `waves.md` ("Scheduling a wave") does: a task
is ready when its dependencies are done, tasks in one wave share no files,
at most four per wave. If the wave count equals the task count, the graph is
a chain and the default message above stands. Also run
subagent-driven-development's pin check (its SKILL.md, Setup): a session
pinned to a native worktree cannot run waves until it leaves it, so when
the check refuses, option 2 ends with `(this session is pinned to a native
worktree; I'd exit it with keep first)`. Otherwise replace the message with
a menu:

```
Plan saved to `<path>`. Review it, then pick how subagent-driven-development runs it:

1. Serial: <N> tasks, one at a time
2. Waves: <W> waves (<sizes>), one worktree per task, full suite after each wave

Append herdr to run it in a new Herdr tab (Sonnet), e.g. "2 herdr".

Which option?
```

Drop the `Append herdr` line when the Herdr check above failed.

Option 2: add `**Execution:** waves` to the plan header, commit, then invoke
subagent-driven-development. Option 1: invoke it as-is. With `herdr`
appended, do the same header edit and commit for option 2, then hand off
via `herdr-handoff.md` instead of invoking the skill here. A Herdr child is
never pinned to a native worktree, so `2 herdr` is available even when the
pin check refused option 2.

**Inline instead, only when one of these observable conditions holds:**
- The harness has no subagent tool
- The plan has one or two tasks that all touch the same files, so a dispatch would cost more context than doing the work

Then:
- **REQUIRED SUB-SKILL:** Use superpowers:executing-plans
- Say: "Plan saved to `<path>`. I'll execute it inline via executing-plans because <condition>. Review the plan and say go."

One reply covers both the plan and the execution choice. Your human partner can redirect the choice in that reply.
