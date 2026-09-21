---
name: ticket-revision
description: Use when an autonomous-ticket orchestrator starts you as the rev child for a ticket that came back from review with comments. Addresses the feedback on the existing branch and PR. Never for interactive sessions.
---

# Ticket Revision

Address one round of review feedback on a ticket that already has a branch
and a pull request. The orchestrator started you, will verify what you push,
and will move the ticket. You change the code, push, and report.

**Announce at start:** "I'm using the ticket-revision skill for ticket
<key>."

## The gate

Check `test "${HERDR_ENV:-}" = 1` first. If it fails, say that you are not
running inside Herdr and stop.

## The marker

Read `.superpowers/ticket.json` from the repo root. If it is missing, or its
`unattended` field is not `true`, say so and stop. Keep `ticket.key`,
`ticket.url`, `git.branch`, `git.base`, `linear.states.stuck` and
`authorised` in mind for the rest of the run.

## Procedure

1. **Read the feedback.** Your prompt carries a cutoff timestamp. Through
   the Linear MCP, by `ticket.url`, list the ticket's comments and keep
   every one created after that timestamp whose author is not the user the
   MCP is authenticated as (`get_user` for the current user). Those are the
   feedback items; number them in the order they were posted. Also read the
   spec and plan under `docs/superpowers/` on this branch: they are the
   design the feedback is against. On a re-prompt that carries no
   timestamp, the feedback is every new comment by anyone other than that
   user since your last report, plus the failures named in the latest
   `🤖 orchestrator: revision` comment.

2. **Rule on each item.**
   - A request you can carry out: carry it out.
   - A request that contradicts a decision in the spec: carry it out and
     amend the spec's section, and its `## Rulings` line if one covers the
     decision, in the same commit, so the spec still describes the branch.
   - A question rather than a request: answer it in the report and change
     nothing.
   - An item that meets the blocker test in `autonomous-ticket`'s
     `## Blockers`: gather every such item first, then stop by that
     procedure, one `❓` comment for all of them.

3. **Make the changes** with `superpowers:test-driven-development`, one
   commit per feedback item or per coherent group, on `git.branch`. Run the
   project's analyse step and full test command (from `package.json`,
   `Makefile`, `pubspec.yaml` or the README, in that order of discovery)
   before each commit. A failing baseline that covers the code the feedback
   touches is a blocker.

4. **Push** `git.branch` to `origin`. `authorised` listing `push` covers it.
   Never force-push, never merge into `git.base`, never delete a branch;
   those remain stops. If the push is rejected, do not retry with force:
   say so in the report.

5. **Report.** Post one comment on the ticket through the Linear MCP:

   ```
   🤖 revision: <N> items
   1. <feedback item, one line> — <what changed, or the answer, or "not changed: <why>">
   2. …
   commits: <first sha7>..<last sha7>, or none
   ```

   Then end your turn. The orchestrator verifies the round and moves the
   ticket.

## Rules

- Never call `AskUserQuestion` and never wait in the pane; nobody is
  watching it.
- Never move the ticket to `linear.states.finished`; the orchestrator does
  that after verifying. The only state you set is `linear.states.stuck`, by
  the blocker procedure.
- Never open a pull request. The branch's PR updates when you push.
- Touch nothing the feedback does not ask for, beyond the spec amendment in
  step 2.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "The reviewer is wrong, I'll explain in the report and skip it" | Disagreement on a design choice is a blocker question, with options. A request you can carry out, you carry out. |
| "Small change, tests can wait" | TDD applies. The orchestrator re-runs the suite either way. |
| "I'll move the ticket to In Review myself when I'm done" | The orchestrator moves it after verifying. You post the report and end the turn. |
| "The push was rejected, a force-push will sort it" | Force-push is a stop. Report the rejection and end the turn. |
