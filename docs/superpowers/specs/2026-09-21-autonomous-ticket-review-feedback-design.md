# Review feedback round for autonomous-ticket — design

Let a ticket that has reached In Review come back to the orchestrator with review comments, have a fresh child address them on the same branch and PR, and return the ticket to In Review. Repeatable per round of feedback, with the child closed after each round it completes cleanly.

Pipeline side: `ticket-pipeline/docs/superpowers/specs/2026-09-21-review-feedback-design.md`. The daemon needs no code change; that spec updates the pipeline design doc and README to the contract below.

## Goal

Today the orchestrator's stage table ends at exec, whose artefact includes "the ticket in `linear.states.finished`". A ticket dragged from In Review back to Todo is moved to In Progress by the daemon and the orchestrator is re-prompted; step 1 then reads exec as the current stage, step 3 re-prompts the exec child, an SDD session whose plan is exhausted, with "the ticket has been updated". What it does with review comments is unspecified, and step 6 moves the ticket straight back to In Review because a PR exists. Feedback may or may not be addressed.

After this change the same drag is deterministic: a `rev` child reads the feedback, changes the code, pushes, reports on the ticket, and the orchestrator verifies, reports and moves the ticket back to In Review.

## Non-goals

- Auto-resuming on a new comment while the ticket sits in In Review. The trigger stays "move it back to Todo", the same signal every other resume uses.
- Reading review comments from the PR on the forge. Feedback is Linear ticket comments only.
- Closing spec, plan or exec children after their stage. Only the rev child is closed; the rest stay until the daemon tears the workspace down at Done.
- Re-running spec or plan for feedback. A rev round changes code directly; if feedback contradicts a spec decision, the rev child amends the spec file in the same round.

## Where it lives

- `skills/autonomous-ticket/SKILL.md`: stage table, step 1, step 3 prompt list, a new step 7, the Resume section, the Rules list and the rationalisations table.
- `skills/ticket-revision/SKILL.md`: new. What the rev child does.
- `README.md`: the unattended paragraph and the skill list mention the round and the new skill.

## Stage table

The exec row's artefact loses its ticket-state clause, so a ticket dragged back to Todo no longer reads as an unfinished exec:

| Stage | Child name | Model | Child invokes | Artefact you check before the next stage |
|-------|------------|-------|---------------|------------------------------------------|
| spec | `<key>-spec` | opus | `superpowers:brainstorming` | unchanged |
| plan | `<key>-plan` | opus | `superpowers:writing-plans` | unchanged |
| exec | `<key>-exec` | sonnet | `superpowers:subagent-driven-development` | commits on `git.branch` after the plan commit; the project's analyse step and tests green; a comment on the ticket containing the PR URL |
| rev | `<key>-rev` | sonnet | `superpowers:ticket-revision` | the ticket in `linear.states.finished` |

Step 6 keeps its "not in finished but a PR exists: comment the URL and move it there" clause, which is how a first-time exec still ends in In Review.

The rev row is current whenever exec is complete and the ticket is outside `linear.states.finished`. Because the daemon moves the ticket to In Progress before re-prompting, that is exactly every resume after a PR exists. Tab label `<key> rev`.

## Feedback

Feedback is every comment on the ticket after the orchestrator's most recent round-closing comment whose author is not the bot user. A round-closing comment is one whose first line is `🤖 orchestrator: verification`, `🤖 orchestrator: revision` or `🤖 orchestrator: nothing to revise`; a `🤖 orchestrator: rev child blocked in Herdr` or `rev produced no report` comment closes nothing and does not move the cutoff. If no round-closing comment exists, exec was never verified: the orchestrator goes to step 6, which posts the verification comment and stops, so the next drag has a cutoff. The bot user is whoever the Linear MCP is authenticated as, which the child reads through the MCP's `get_user` for the current user; the marker does not carry it. This assumes the MCP is authenticated with the bot's credentials, not the human's. With the human's credentials every comment shares one author and the filter passes the workers' own comments through as feedback. The daemon's own `🤖 pipeline:` comments are posted with the bot's API key, the same user the MCP is authenticated as, so the author filter drops them too.

The cutoff is the orchestrator's last round-closing comment rather than the last state transition because the orchestrator posts one at the end of every round, and the comment list needs no state history to read.

## Procedure changes in autonomous-ticket

**Step 1.** Unchanged walk, with the new table. Add: when the current stage is `rev`, run `herdr agent list`. If `<key>-rev` is live in this workspace, go to step 3 (it is re-prompted as any live child is). Otherwise collect the feedback: every comment after your most recent round-closing comment (first line `🤖 orchestrator: verification`, `🤖 orchestrator: revision` or `🤖 orchestrator: nothing to revise`) whose author is not the bot user. If the ticket carries no such comment, exec was never verified: go to step 6. If there is no feedback, post

```
🤖 orchestrator: nothing to revise
no new comments since the last round
```

move the ticket to `linear.states.finished`, and stop. Otherwise go to step 3.

**Step 3.** The prompt list gains:

- rev: `Ticket <key>, stage rev. Read .superpowers/ticket.json, then invoke superpowers:ticket-revision. Feedback is every comment after <ISO timestamp of the cutoff comment> not authored by the bot user.`

Keep the returned `tab_id` for step 7.

**Step 5.** Unchanged for spec, plan and exec. For `rev` the artefact is the ticket in the finished state, which the child never sets (step 7 does), so the "absent otherwise" branch would always fire. Add to step 5: for `rev`, on `idle` or `done`, stop if the ticket is in `linear.states.stuck` (the child asked a question; the answer returns as a resume), otherwise go to step 7 without an artefact check.

**Step 7 (new). Verify after rev.** In this worktree:

1. Read the child's `🤖 revision:` comment posted after the cutoff comment from step 1, or after your re-prompt when the child was already live. Absent: prompt the child once with "Post your 🤖 revision: comment on the ticket and end your turn", wait as in step 4, and on the next wake, if still absent, post `🤖 orchestrator: rev produced no report` with the child's last 30 lines and stop.
2. `git fetch origin git.branch`; the round is pushed when `git rev-parse HEAD` equals `git rev-parse origin/<git.branch>`. Not pushed: prompt the child once with "Push git.branch to origin", wait, re-check once. A round with no commits is pushed by definition.
3. Run the project's analyse step and full test command, as step 6 does, with the same single retry, prompting the rev child rather than the exec child.
4. The round is green when it pushed and analyse and tests all passed. If green: `herdr tab close <tab_id>`. The `tab_id` comes from the step 3 create response, or from `herdr tab list --workspace "$HERDR_WORKSPACE_ID"` matched on label `<key> rev` if you do not hold it from this round. Anything failed: leave the tab.
5. Post:

   ```
   🤖 orchestrator: revision
   pushed: <yes|no>
   analyse: <pass|fail>
   tests: <N passed, M failed>
   commits: <first sha7>..<last sha7> on <git.branch>, or none
   PR: <url from the earlier verification comment>
   tab: <tab_id> left open for inspection
   ```

   The `tab:` line is present only when the round was not green.

6. Move the ticket to `linear.states.finished` whether or not everything passed, as step 6 does. The comment says what failed; the human decides.
7. Stop.

**Resume section.** Add: a ticket moved back to Todo from In Review lands in the rev stage. Blocked or stuck rev children survive the pause and are re-prompted like any other child; a rev child whose round was closed is gone, and the next round starts a fresh one under the same name.

**Rules.** "Never close a tab, pane or workspace, including ones you created" becomes "Never close a tab, pane or workspace, including ones you created, except the `<key> rev` tab in step 7 after a round that pushed and passed. Your human partner reviews the PR from here."

**Rationalisations.** Add:

| Excuse | Reality |
|--------|---------|
| "The feedback is one line, I'll make the change myself" | You implement nothing. Start the rev child. |
| "Verification is red but the change is what they asked for, close the tab anyway" | Red leaves the tab. The comment says it is open and why. |
| "No live rev child and no new comments, so re-run exec" | Exec is complete. Post nothing to revise and move the ticket back. |

## The ticket-revision skill

`skills/ticket-revision/SKILL.md`, frontmatter description: "Use when an autonomous-ticket orchestrator starts you as the rev child for a ticket that came back from review with comments. Addresses the feedback on the existing branch and PR. Never for interactive sessions."

Announce at start: "I'm using the ticket-revision skill for ticket <key>."

1. **Gate and marker.** Same checks as `autonomous-ticket`: `HERDR_ENV` is 1, `.superpowers/ticket.json` exists with `unattended` true. Keep `ticket.key`, `ticket.url`, `git.branch`, `git.base`, `linear.states.stuck` and `authorised` in mind.
2. **Read the feedback.** Through the Linear MCP, by `ticket.url`: every comment after the timestamp in your prompt whose author is not the user the MCP is authenticated as (`get_user` for the current user). Also read the spec and plan under `docs/superpowers/` on this branch; they are the design the feedback is against. Number the feedback items. On a re-prompt that carries no timestamp, the feedback is every new comment by anyone other than that user since your last report, plus the failures named in the latest `🤖 orchestrator: revision` comment.
3. **Rule on each item.** An item that asks for a change: do it. An item that contradicts a decision in the spec: make the change and amend the spec's section (and its `## Rulings` line if one covers it) in the same commit, so the spec still describes the branch. An item that meets the blocker test in `autonomous-ticket`'s `## Blockers` stops the run by that procedure; gather every such item first and post them in one `❓` comment. An item that is a question rather than a request: answer it in the report and change nothing.
4. **Make the changes** with `superpowers:test-driven-development`, one commit per feedback item or per coherent group, on `git.branch`. Run the project's analyse step and full test command before each commit; a failing baseline that covers the code the feedback touches is a blocker.
5. **Push** `git.branch` to `origin`. `authorised` listing `push` covers it. Never force-push, never merge into `git.base`, never delete branches; those remain stops.
6. **Report.** Post one comment:

   ```
   🤖 revision: <N> items
   1. <feedback item, one line> — <what changed, or the answer, or "not changed: <why>">
   2. …
   commits: <first sha7>..<last sha7>, or none
   ```

   End the turn. The orchestrator verifies and moves the ticket.

Rules: never call `AskUserQuestion`, never wait in the pane, never move the ticket to `linear.states.finished` (the orchestrator does that after verifying; the only state the child sets is `linear.states.stuck`, by the blocker procedure), never open a new PR (the branch's PR updates on push), never touch files outside what the feedback asks for beyond the spec amendment in step 3.

Rationalisations:

| Excuse | Reality |
|--------|---------|
| "The reviewer is wrong, I'll explain in the report and skip it" | Disagreement on a design choice is a blocker question, with options. A request you can carry out, you carry out. |
| "Small change, tests can wait" | TDD applies. The orchestrator re-runs the suite either way. |
| "I'll move the ticket to In Review myself when I'm done" | The orchestrator moves it after verifying. You post the report and end the turn. |

## Chained skills

`test-driven-development`, `finishing-a-development-branch` and `subagent-driven-development` are unchanged. The rev child does not invoke `finishing-a-development-branch`; the PR already exists and the push is direct.

## Error handling

- Rev child blocked (approval or question UI): step 5's `blocked` branch as today. Tab stays open; the human answers in the pane and drags the ticket to Todo.
- Rev child hit a blocker: `❓` comment, ticket in stuck, turn ended. Step 5's "absent and stuck" branch stops the orchestrator; the answer returns as a resume and step 3 re-prompts the live child.
- Rev child exited without a report: step 7.1 retries once, then reports and stops. The ticket stays in In Progress; the daemon's stall path flags it after `stall_minutes`, as it does for any silent worker.
- Push rejected (branch moved on the remote): the child's push fails, its report says so, step 7.2 reports `pushed: no`, ticket returns to In Review with the tab open.

## Testing

Skills are prose; the fork's `tests/` has no harness for orchestrator flows. Verification is a real run: a ticket in In Review on the pipeline, one comment asking for a visible change, dragged to Todo. Expected: a `<key> rev` tab appears, a `🤖 revision:` comment lists the item, a `🤖 orchestrator: revision` comment follows, the ticket is back in In Review, the PR has the new commit, and the rev tab is gone. Then a second comment and drag, to see the round repeat and the tab name reuse. Then a comment that raises a design question, to see the `❓` path and the re-prompt after answering.

## Rulings

- Trigger is the existing "move to Todo" resume — no daemon change, and the human batches comments before triggering — a stray drag with no comments costs one "nothing to revise" comment.
- Feedback is Linear comments after the last `🤖 orchestrator:` comment, by author — the Linear MCP will run under the bot's credentials, so author separates the two — until that swap happens the workers' own comments read as feedback.
- Direct change, no revision plan — feedback is usually concrete and a plan child per round doubles the tabs — a large redesign in feedback becomes a blocker question rather than a plan.
- Sonnet for the rev child — same as exec, the work is scoped by the comments — feedback that reopens design gets a `❓` instead of an Opus rethink.
- Only the rev tab is closed, and only on green — the human asked for no stale rev agents across rounds and to keep the other stage tabs — a red round leaves one tab, named in the comment.
- The orchestrator, not the child, moves the ticket to In Review — one place sets the finishing state after verification — a child that finishes while the orchestrator is dead leaves the ticket in In Progress until the next resume.
- Cutoff is the most recent round-closing orchestrator comment, and no such comment sends the orchestrator to step 6 — a blocked-child comment or a dead orchestrator otherwise hides the feedback — costs one extra verification round when the orchestrator died before step 6.
