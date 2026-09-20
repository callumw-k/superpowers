---
name: autonomous-ticket
description: Use when a Herdr pane is prompted to work a Linear ticket unattended and `.superpowers/ticket.json` is present in the worktree. Orchestrates spec, plan and implementation in fresh child agents, verifies each stage, and reports to the ticket. Never for interactive sessions.
---

# Autonomous Ticket

Run one Linear ticket from description to pull request with no human in the
loop. You are the orchestrator: you design nothing, plan nothing and
implement nothing yourself. Each stage runs in a fresh Claude child in its
own Herdr tab of this workspace, on this worktree, and you verify what it
produced before starting the next. Your context stays small, which is what
lets you resume this ticket days later.

**Announce at start:** "I'm using the autonomous-ticket skill to orchestrate
ticket <key>."

Invoke the `herdr` skill before the first `herdr` command; the CLI's usage
output is the authority on syntax.

## The gate

Check `test "${HERDR_ENV:-}" = 1` first. If it fails, say that you are not
running inside Herdr and stop: every stage below spawns a Herdr tab, so
there is nothing this skill can do from outside one.

## The marker

Read `.superpowers/ticket.json` from the repo root. If it is missing, or
its `unattended` field is not `true`, say so and stop: this skill only
runs where the daemon put a ticket. Keep
`ticket.key`, `ticket.url`, `git.branch`, `git.base`, `git.forge`,
`linear.states.stuck` and `linear.states.finished` in mind for the rest of
the run.

Every child and subagent in this worktree reads the same file. That is how
`brainstorming`, `writing-plans`, `subagent-driven-development` and
`finishing-a-development-branch` know they are unattended.

## Stages

| Stage | Child name | Model | Child invokes | Artefact you check before the next stage |
|-------|------------|-------|---------------|------------------------------------------|
| spec | `<key>-spec` | opus | `superpowers:brainstorming` | a file matching `docs/superpowers/specs/*-<key>-*.md` committed on `git.branch`, or the ticket in `linear.states.stuck` |
| plan | `<key>-plan` | opus | `superpowers:writing-plans` | a file matching `docs/superpowers/plans/*-<key>-*.md` committed on `git.branch` whose header carries a `**Spec:**` line |
| exec | `<key>-exec` | sonnet | `superpowers:subagent-driven-development` | commits on `git.branch` after the plan commit; the project's analyse step and tests green; the ticket in `linear.states.finished` with a comment containing the PR URL |

`<key>` is `ticket.key` lowercased with any character outside `[a-z0-9_-]`
replaced by `-`. The same `<key>` appears in a child name and in the spec and
plan filenames above, which is what makes those globs match.

## Procedure

1. **Find the stage.** Walk the table top to bottom; the current stage is the
   first whose artefact is absent. If none is absent, post the verification
   comment (step 6) if it is not already on the ticket, and stop.

2. **Read the ticket's comments** through the Linear MCP, by `ticket.url`.
   Comments after the most recent move to `linear.states.stuck` are your
   human partner's answers to earlier questions and carry the same authority
   as the description. Note whether there are any; the child's prompt says
   so.

3. **Start or re-prompt the stage child.** Run `herdr agent list`. If an
   agent with the stage's child name is live in this workspace, prompt it:

   ```
   The ticket has been updated. Read its new comments through the Linear MCP and continue.
   ```

   Otherwise create a tab in this workspace and start a fresh child:

   ```bash
   herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "<key> <stage>" --no-focus
   herdr agent start <child name> --kind claude --pane <root_pane from the create response> -- --model <stage model>
   ```

   If `agent start` returns `agent_not_ready`, read the pane, post
   `🤖 orchestrator: <stage> child could not start` with the last 30 lines
   to the ticket, and stop.

   Then prompt it, one message, without `--wait`:

   - spec: `Ticket <key>, stage spec. Read .superpowers/ticket.json and the ticket's comments through the Linear MCP, then invoke superpowers:brainstorming for the ticket. Name the spec docs/superpowers/specs/<YYYY-MM-DD>-<key>-<topic>-design.md: today's date, then <key>, then the topic.`
   - plan: `Ticket <key>, stage plan. Read .superpowers/ticket.json, then invoke superpowers:writing-plans for the spec at <spec path>. Name the plan docs/superpowers/plans/<YYYY-MM-DD>-<key>-<feature-name>.md: today's date, then <key>, then the feature name.`
   - exec: `Ticket <key>, stage exec. Read .superpowers/ticket.json, then invoke superpowers:subagent-driven-development to execute the plan at <plan path>.`

4. **Wait.** Run `herdr agent wait <child name>` as a background command
   with no timeout so you are woken when the child settles. Tell nobody;
   there is nobody to tell. End your turn.

5. **On wake**, read `herdr agent get <child name>`:
   - `blocked`: read the pane with `herdr agent read <child name> --source
     recent-unwrapped --lines 30`, post `🤖 orchestrator: <stage> child
     blocked in Herdr <pane id>` followed by those lines in a code fence,
     and stop. The daemon reports it too; your human partner answers in the
     pane and the ticket comes back to you as a resume.
   - `idle` or `done`: check the stage's artefact.
     - Present: go to step 3 for the next stage, or to step 6 after exec.
     - Absent and the ticket is in `linear.states.stuck`: stop. The child
       asked a question on the ticket; the answer returns as a resume.
     - Absent otherwise: prompt the child once with exactly what is missing
       (the path pattern, or the commit, or the ticket state), wait again as
       in step 4, and on the next wake, if it is still absent, post
       `🤖 orchestrator: <stage> produced no artefact` with the child's last
       30 lines and stop.
   - `unknown`: read the pane before deciding anything. It does not mean
     the child finished. If the pane shows a completed response, treat it as
     `idle`; if it shows an approval or question UI, treat it as `blocked`.

6. **Verify after exec.** In this worktree run the project's analyse step
   and its full test command (from `package.json`, `Makefile`, `pubspec.yaml`
   or the README, in that order of discovery). On failure, prompt the exec
   child once with the failing output, wait as in step 4, and re-run once.
   Then, whether green or not, post the result as a ticket comment:

   ```
   🤖 orchestrator: verification
   analyse: <pass|fail>
   tests: <N passed, M failed>
   commits: <first sha7>..<last sha7> on <git.branch>
   PR: <url>
   ```

   If the ticket is not in `linear.states.finished` but a PR for
   `git.branch` exists on the forge (`gh pr view <branch>` or
   `tea pr list`), comment the URL and move the ticket there yourself.
   Then stop.

## Resume

The daemon re-prompts you with "The ticket has been updated. Invoke
superpowers:autonomous-ticket to resume." when your human partner moves the
ticket back to the trigger state. Start again at step 1: the artefacts on
disk say which stage you are in, and step 3 re-prompts a child that is still
alive rather than starting a new one, so its context survives the pause.

## Blockers

At any stage, in any of the chained skills, a blocker is one of:

- a question the ticket and its comments do not settle, where different
  answers lead to materially different work: architecture, data model, an
  irreversible trade-off, or a contradiction inside the ticket itself;
- one of subagent-driven-development's four stop classes;
- a failing baseline test that covers the code the ticket touches.

A question that has a sensible default is not a blocker. Rule on it, record
the ruling where the skill you are in keeps rulings (the spec's `## Rulings`
section, the SDD ledger), and continue.

On a blocker, the agent that hit it, child or orchestrator:

1. Posts one comment on the ticket through the Linear MCP, starting with
   `❓`, containing every open question (batch them; do not stop on the
   first) and for each the options it sees and which it would pick if
   forced.
2. Moves the ticket to `linear.states.stuck`.
3. Ends its turn. It never calls `AskUserQuestion` and never waits in the
   pane; nobody is watching it.

## Rules

- Never design, plan, implement or fix anything in this session. Prompt the
  stage child instead.
- Never present a menu or ask a question in the pane.
- Never close a tab, pane or workspace, including ones you created. Your
  human partner reviews the PR from here.
- One retry per stage, as written in steps 5 and 6. A second failure is a
  comment and a stop, not a third attempt.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "The spec is nearly right, I'll fix the one section myself" | Your context is the orchestrator's. Prompt the spec child with what is wrong. |
| "The child is idle but I'm sure it finished, skip the artefact check" | Idle proves the turn ended, nothing more. Check the file, the commit, the ticket state. |
| "Nobody answered the blocker, I'll pick the option I'd have chosen" | The ticket is in Needs Info. The answer comes back as a resume; until then there is nothing to do. |
| "Tests failed on something the ticket didn't touch, so verification passed" | Report what ran. A failing suite is a failing suite; the comment says so and your human partner decides. |
