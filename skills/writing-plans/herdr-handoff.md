# Herdr Handoff

Hand the next stage of the workflow to a fresh Claude Code agent in a new
Herdr tab on the same checkout, then wait for it and check its work. Read
this only when your human partner chose the Herdr option at a handoff
message. The child gets the same file, next skill and execution mode the
handoff would have used in this session.

**Why a new tab:** a fresh agent reads the file cold instead of carrying
the whole brainstorm in context, and your human partner can watch it work
while still talking to you.

Two roles, fixed by which skill is handing off:

| Role | Handing off from | Child reads | Child invokes | Model |
|------|------------------|-------------|---------------|-------|
| planner | brainstorming (spec approved) | the spec | superpowers:writing-plans | opus |
| executor | writing-plans (plan approved) | the plan | superpowers:subagent-driven-development | sonnet |

Opus for the planner because the child has to design the tasks itself.
Sonnet for the executor because the plan already carries the code.

Invoke the `herdr` skill before the first `herdr` command. The commands
below show the shape, and the CLI's own usage output is the authority on
syntax.

## Procedure

1. **Locate yourself.** Read your own pane, tab and workspace IDs from
   `herdr pane current --current`, not from `$HERDR_WORKSPACE_ID` and
   friends: the injected variables can go stale when a workspace is
   renumbered. Keep `pane_id`, `tab_id`, `workspace_id` and
   `terminal_title_stripped` from the response.

2. **Pick a slug.** Lowercase, hyphenated, from the spec or plan topic,
   short enough that `child-<slug>` fits the 32-character agent name limit
   (`[a-z][a-z0-9_-]{0,31}`). If `herdr agent list` already has
   `child-<slug>` or `parent-<slug>` live, append `-2`.

3. **Create the tab.** Same workspace, same working directory, focus left
   where it is:

   ```bash
   herdr tab create --workspace <workspace_id> --cwd "$PWD" --label "[child] <topic>" --no-focus
   ```

   Take the pane from `.result.root_pane`.

4. **Start the child.**

   ```bash
   herdr agent start child-<slug> --kind claude --pane <root_pane> -- --model <opus|sonnet>
   ```

   Wait for the command to return ready. If it returns `agent_not_ready`,
   read the pane, tell your human partner what the child is stuck on, and
   stop. Do not answer a startup dialog on their behalf.

5. **Rename yourself.** Agent name first, then the tab label:

   ```bash
   herdr agent rename <own pane_id> parent-<slug>
   herdr tab rename <own tab_id> "[parent] <name>"
   ```

   `<name>` is your tab's current label. When the label is just the
   default tab number, use `terminal_title_stripped` instead. Strip a
   leading `[child] ` from the existing label so a handoff chain reads
   `[parent] X`, never `[parent] [child] X`.

6. **Prompt the child.** One message: the file to read, the skill to
   invoke, and for the executor the execution mode already recorded in the
   plan header (serial or waves). Do not paste the file's contents, the
   child reads it. Send without `--wait`:

   ```bash
   herdr agent prompt child-<slug> "Read <path> and invoke <skill> to <write the implementation plan|execute it>. <Execution: waves|serial>."
   ```

7. **Wait in the background.** Run this as a background shell command with
   no timeout so you are woken when the child settles:

   ```bash
   herdr agent wait child-<slug>
   ```

   Tell your human partner the tab label and agent name, and that you will
   report when the child settles. End your turn.

8. **On wake**, read `herdr agent get child-<slug>`:
   - `blocked`: read the pane with
     `herdr agent read child-<slug> --source recent-unwrapped --lines 120`,
     relay the question or approval to your human partner, and wait for
     their answer before sending anything to the child. Then wait again.
   - `idle` or `done`: check the child's work yourself before reporting.
     Read the commits it made, run the project's analyse step and tests,
     and look for collateral: formatter rewraps, files the spec or plan
     never mentioned, a version bump nobody asked for. Report what you
     found with the evidence, not the child's own summary.
   - `unknown`: read the pane before deciding anything. It does not mean
     the child finished.

Do not close the child's tab. Your human partner owns it once it exists.
