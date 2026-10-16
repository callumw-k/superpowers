# Herdr Handoff

Hand the next stage of the workflow to a fresh Claude Code agent in a new
Herdr tab on the same checkout, then wait for it and check its work. Read
this only when your human partner picked a Herdr option at a handoff menu.
The child gets the same file, next skill and execution mode the handoff
would have used in this session.

**Why a new tab:** a fresh agent reads the file cold instead of carrying
the whole brainstorm in context, and your human partner can watch it work
while still talking to you.

**The conversation stays with you.** The child does its stage and stops.
The question that follows the stage (plan review, how to finish the
branch) comes from you, so your human partner answers in one place and a
handoff never chains into a grandchild.

Two roles, fixed by which skill is handing off:

| Role | Handing off from | Child reads | Child invokes | Child stops when | Model |
|------|------------------|-------------|---------------|------------------|-------|
| planner | brainstorming (spec approved) | the spec | superpowers:writing-plans | the plan is saved, self-reviewed and committed | opus |
| executor | writing-plans (plan approved) | the plan | the skill picked at the handoff: superpowers:subagent-driven-development or superpowers:executing-plans | the final review is clean and its fixes are committed | sonnet |

Opus for the planner because the child has to design the tasks itself.
Sonnet for the executor because the plan already carries the code.

Invoke the `herdr` skill before the first `herdr` command. The commands
below show the shape, and the CLI's own usage output is the authority on
syntax.

## Procedure

1. **Locate yourself.** Read your workspace ID from
   `herdr pane current --current`, not from `$HERDR_WORKSPACE_ID`: the
   injected variable can go stale when a workspace is renumbered.

2. **Pick a name.** `<role>-<slug>`, with the slug lowercase, hyphenated,
   from the spec or plan topic, and short enough to fit the 32-character
   agent name limit (`[a-z][a-z0-9_-]{0,31}`). If `herdr agent list`
   already has that name live, append `-2`.

3. **Create the tab.** Same workspace, same working directory, focus left
   where it is. Run from your pane, the new tab nests under yours, so the
   label needs no parent or child marker:

   ```bash
   herdr tab create --workspace <workspace_id> --cwd "$PWD" --label "<role>: <topic>" --no-focus
   ```

   Take the pane from `.result.root_pane` and keep `.result.tab.tab_id`:
   finishing-a-development-branch closes this tab once the branch is
   merged.

4. **Start the child.**

   ```bash
   herdr agent start <name> --kind claude --pane <root_pane> -- --model <opus|sonnet>
   ```

   Wait for the command to return ready. If it returns `agent_not_ready`,
   read the pane, tell your human partner what the child is stuck on, and
   stop. Do not answer a startup dialog on their behalf.

5. **Prompt the child.** One message, built from the template for its
   role. Do not paste the file's contents, the child reads it. Send
   without `--wait`:

   - planner: `Read <spec path> and invoke superpowers:writing-plans to write the implementation plan. End your turn once the plan is saved, self-reviewed and committed. Skip the Execution Handoff: I take the plan to review.`
   - executor: `Read <plan path> and invoke <skill> to execute it. Execution: <waves|serial>. End your turn once the final review is clean and its fixes are committed. Skip finishing-a-development-branch: I run it.`

   The executor's execution mode is the one recorded in the plan header:
   `waves` when the header carries `**Execution:** waves`, otherwise
   `serial`. Leave the sentence out for executing-plans.

   ```bash
   herdr agent prompt <name> "<prompt>"
   ```

6. **Wait in the background.** Run this as a background shell command with
   no timeout so you are woken when the child settles:

   ```bash
   herdr agent wait <name>
   ```

   Tell your human partner the tab label and agent name, and that you will
   report when the child settles. End your turn.

7. **On wake**, read `herdr agent get <name>` and the pane with
   `herdr agent read <name> --source recent-unwrapped --lines 120`:
   - `blocked`, or `idle` with the stage unfinished and a question as the
     child's last message: tell your human partner the question and that
     it waits in the tab. They answer it there; do not answer it yourself.
     If they give the answer to you instead, send it with
     `herdr agent prompt` when the child asked in plain text, or ask them to
     answer in the tab when it is a dialog. Then wait again in the
     background with `herdr agent wait <name> --until working && herdr agent wait <name>`:
     a plain wait matches the state the child is already in and returns at
     once.
   - `idle` or `done` with the stage finished: check the child's work
     yourself, then carry on as the role says.
     - planner: the plan file exists, is committed, carries a `**Spec:**`
       line, and every spec requirement has a task. Then invoke
       superpowers:writing-plans and go straight to its Execution Handoff
       for this plan: the plan is written and self-reviewed, so the
       handoff menu is the next thing your human partner sees. A Herdr
       option there runs this procedure again as the executor.
     - executor: read the commits the child made, run the project's
       analyse step and tests, and look for collateral: formatter
       rewraps, files the plan never mentioned, a version bump nobody
       asked for. Report what you found with the evidence, not the child's
       own summary, then invoke superpowers:finishing-a-development-branch
       here. It is the same checkout.
   - `unknown`: read the pane before deciding anything. It does not mean
     the child finished.

Do not close the child's tab yourself. It stays open for your human
partner until finishing-a-development-branch closes it after a local
merge.
