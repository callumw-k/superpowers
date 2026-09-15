# Faster iteration loop: what changed and what's next

Notes from the 2026-09-15 session on this fork. The goal was fewer stops for the human without losing questioning, review, or the spec and plan artefacts.

## Landed (commit 2e55f5f on main)

- brainstorming: independent clarifying questions go out in one message. The architectural path writes the spec straight after the approach is chosen and takes one approval on the file, with no separate in-chat design step.
- writing-plans: no "which approach?" question. subagent-driven-development is the default. executing-plans is used only when the harness has no subagent tool or the plan is one or two tasks on the same files. The plan-approval message states the choice.
- finishing-a-development-branch: the menu names the branch and its guessed base ("correct me if not"), so the base-branch question is no longer its own message. Squash merge is option 2 and uses `git branch -D`, since squashed commits aren't ancestors of the base.
- test-driven-development: the criterion is "can you name the bug the test would catch". Plumbing, config, generated code and prototypes are skipped with a one-line note, no permission request.
- requesting-code-review: `HEAD~1` removed as the base SHA. Record the pre-work commit instead.
- using-git-worktrees: baseline test failures are recorded as pre-existing and work continues. Ask only if a failing test covers the code being changed.

`~/.claude/CLAUDE.md` lost the lines these skills now carry (commit 17115b2 in claude-config): the SDD-over-executing-plans preference, the TDD bound, and the build/install-scripts clause of the flutter rule.

## Declined

- Folding the visual companion offer into the first visual question. The skill marks the separate message as tuned behaviour and it fires rarely.
- Skipping the approaches stop when one approach is clearly best. Left as is for now, since the trade-off is a decision the human owns.

## Open: plugin loading

Sessions load superpowers from the plugin cache (`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0`), not this checkout. None of the above takes effect until the marketplace points at this fork or a local path.

## Open: running SDD without blocking the session

The controller must own every dispatch (subagents can't spawn subagents in Claude Code), so SDD can't be pushed into one background agent. Two routes:

1. A second session in the worktree, which is what the skill already means by "parallel session". In a Herdr or tmux pane: `claude "use superpowers:subagent-driven-development to execute docs/superpowers/plans/<plan>.md" --permission-mode acceptEdits`. The ledger makes it resumable and there is nothing to build.
2. A `Workflow` script (`.claude/workflows/sdd.js`) reimplementing the task loop as `agent()` calls. Runs in the background of the session and notifies on completion. The fix loop, ledger and rulings all move into JS, and it needs the "use a workflow" opt-in each run.

Try route 1 first. Route 2 is worth a spike only if the session being blocked is still the problem after that.

## Open: wave execution for independent tasks

Sketch for running several plan tasks at once. Needs a proper brainstorm and spec before touching SDD, as it changes the process graph, the ledger format and the setup section.

- The input already exists: each task lists Files and Consumes/Produces interfaces, and SDD's pre-flight scan already builds the table of task pairs sharing a file or interface.
- Build a dependency graph from that table. A task is ready when everything it consumes is merged. Ready tasks with disjoint file sets form a wave. Ten tasks typically collapse to two or three waves of three to five.
- One worktree per task in a wave, branched from the current head (the Agent tool's `isolation: "worktree"` does this). Commits, test runs and fix loops stay separate. Reviews are read-only and file-based already, so they run in parallel for free.
- When every branch in a wave is clean: merge them into the plan branch (disjoint files, so no conflicts by construction), run the full suite once on the merged head, and start the next wave from there.
- Costs: dependency install per worktree (share `node_modules` or use pnpm's store), the controller handling several reports at once (the report-file discipline covers it), and interfaces that must be exact because neighbours are built blind to each other (the plan format already demands this).
- Ledger needs a wave line: which tasks ran together, the merge commit, and the suite result on the merged head.
