# Herdr Handoff

Hand the next stage of the workflow to a fresh Claude Code agent in a new
Herdr terminal on the same checkout, then wait for it and check its work.
Read this only when your human partner picked a Herdr option at a handoff
menu. The child gets the same file, next skill and execution mode the
handoff would have used in this session.

**Why a new terminal:** a fresh agent reads the file cold instead of
carrying the whole brainstorm in context, and your human partner can watch
it work (`hc attach <name>`) while still talking to you.

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

Run `hc --skill` before the first `hc` command. The commands below show
the shape, and `hc <command> --help` is the authority on syntax.

## Procedure

1. **Pick a name.** `<role>-<slug>`, with the slug lowercase, hyphenated,
   from the spec or plan topic, and short enough to fit hc's 32-character
   name limit (`a-z`, `0-9`, `-`, `_`). If `hc get <name>` shows a
   terminal by that name with `state` `live`, append `-2`. It exits 3 when
   there is none.

2. **Start the child.** Same working directory, no task yet:

   ```bash
   hc run --bg --outlive-parent --no-notify --name <name> --cwd "$PWD" -- claude --model <opus|sonnet>
   hc wait <name>
   ```

   `--outlive-parent` keeps the child for your human partner if this
   session ends, and `--no-notify` leaves the waits below as your only
   wake-up. When `hc wait` reports `idle`, the child is ready. Any other
   status (`blocked` on a trust or startup dialog, `error`, an exit): read
   it with `hc read <name> --lines 40`, tell your human partner what the
   child is stuck on, and stop. Do not answer a startup dialog on their
   behalf.

3. **Prompt and wait.** One message, built from the template for its
   role. Do not paste the file's contents, the child reads it.

   - planner: `Read <spec path> and invoke superpowers:writing-plans to write the implementation plan. End your turn once the plan is saved, self-reviewed and committed. Skip the Execution Handoff: I take the plan to review.`
   - executor: `Read <plan path> and invoke <skill> to execute it. Execution: <waves|serial>. End your turn once the final review is clean and its fixes are committed. Skip finishing-a-development-branch: I run it.`

   The executor's execution mode is the one recorded in the plan header:
   `waves` when the header carries `**Execution:** waves`, otherwise
   `serial`. Leave the sentence out for executing-plans.

   Send it as a background shell command, so you are woken when the turn
   it starts has ended:

   ```bash
   hc send --wait --timeout 86400 <name> "<prompt>"
   ```

   Tell your human partner the terminal name, that `hc attach <name>`
   shows it (Ctrl+\ detaches), and that you will report when the child
   settles. End your turn.

4. **On wake**, read `hc get <name>` (its `status.state`, and `status.msg`
   for the child's last words) and the screen with
   `hc read <name> --lines 120`:
   - `blocked`, or `idle`/`done` with the stage unfinished and a question
     as the child's last message: tell your human partner the question and
     that it waits in the terminal. They answer it there; do not answer it
     yourself. If they give the answer to you instead, send it with
     `hc send --wait --timeout 86400 <name> "<answer>"` in the background
     when the child asked in plain text, or ask them to answer in the
     terminal when it is a dialog. When they answer in the terminal, wait
     in the background with `hc wait --children any --timeout 86400`,
     which returns on the child's next news.
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
   - `error`, or the terminal finished: read the screen before deciding
     anything, and tell your human partner what it shows.
   - `not_started` from the send: read the screen. The prompt may still
     have arrived; do not send it again blindly.

Do not end the child yourself. It stays live for your human partner until
finishing-a-development-branch ends it after a local merge.
