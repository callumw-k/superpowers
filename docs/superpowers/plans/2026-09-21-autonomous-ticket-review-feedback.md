# Autonomous Ticket Review Feedback Round Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (superpowers:executing-plans only where subagents are unavailable). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `autonomous-ticket` a `rev` stage so a ticket dragged from In Review back to Todo with comments gets those comments addressed on the same branch and PR by a fresh `ticket-revision` child, verified and reported by the orchestrator, and returned to In Review.

**Architecture:** The exec row's artefact stops including the ticket state, a fourth `rev` row is current whenever exec is complete and the ticket is outside the finished state, and a new step 7 in the orchestrator verifies the round, posts the report, moves the ticket and closes the rev tab on green. The child's procedure lives in a new skill, `ticket-revision`, which reads the feedback by cutoff comment and author, changes code with TDD, pushes, and reports.

**Tech Stack:** Markdown skills in the superpowers plugin voice; bash for the checks the skills run; the Linear MCP (`linear-server`) for ticket reads and writes; Herdr CLI for tabs, agents and waits; `scripts/bump-version.sh` for the release.

**Spec:** `docs/superpowers/specs/2026-09-21-autonomous-ticket-review-feedback-design.md`

## Global Constraints

- Feedback is every comment after the orchestrator's most recent `🤖 orchestrator:` comment whose author is not the user the Linear MCP is authenticated as. Author comes from the MCP's `get_user` for the current user, never from the marker.
- Child name `<key>-rev`, tab label `<key> rev`, model `sonnet`, skill `superpowers:ticket-revision`. `<key>` is `ticket.key` lowercased with any character outside `[a-z0-9_-]` replaced by `-`.
- The child's report comment starts with `🤖 revision:`. The orchestrator's round report starts with `🤖 orchestrator: revision`. The no-feedback comment starts with `🤖 orchestrator: nothing to revise`.
- The orchestrator moves the ticket to `linear.states.finished` after every round, green or red. Only a green round (pushed, analyse pass, tests pass) closes the rev tab.
- The child never changes the ticket state and never opens a PR. Push is authorised by `authorised` listing `push`; force-push, merge and branch deletion remain stops.
- Existing skill text outside the edited passages is left untouched: no rewording, no reformatting, no reflow. Edits below quote the exact current text to replace.
- The plugin voice: "your human partner", not "the user"; imperative; no comments about the change inside the skill text.
- Version bump lands last, as its own commit, through `scripts/bump-version.sh`, to `6.5.0`.

---

### Task 1: The `ticket-revision` skill

**Files:**
- Create: `skills/ticket-revision/SKILL.md`

**Interfaces:**
- Consumes: the marker file `.superpowers/ticket.json` (`ticket.key`, `ticket.url`, `git.branch`, `git.base`, `linear.states.stuck`, `authorised`); the `## Blockers` procedure in `skills/autonomous-ticket/SKILL.md`; the feedback cutoff timestamp the orchestrator passes in the prompt (Task 2).
- Produces: the skill name `superpowers:ticket-revision` that Task 2's stage table and prompt name; the `🤖 revision:` comment format Task 2's step 7 reads.

**Depends on:** none

- [ ] **Step 1: Write the skill file**

`skills/ticket-revision/SKILL.md`:

````markdown
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
   design the feedback is against.

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
   commits: <first sha7>..<last sha7>
   ```

   Then end your turn. The orchestrator verifies the round and moves the
   ticket.

## Rules

- Never call `AskUserQuestion` and never wait in the pane; nobody is
  watching it.
- Never change the ticket's state. The orchestrator does that after
  verifying.
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
````

- [ ] **Step 2: Check the file has the lines the orchestrator relies on**

Run:

```bash
rg -c "^name: ticket-revision$|^\*\*Announce at start:\*\*|🤖 revision: <N> items|get_user|## Blockers|Never change the ticket's state" skills/ticket-revision/SKILL.md
```

Expected: `6`.

- [ ] **Step 3: Commit**

```bash
git add skills/ticket-revision/SKILL.md
git commit -m "Add the ticket-revision skill for review feedback rounds"
```

---

### Task 2: The `rev` stage in `autonomous-ticket`

**Files:**
- Modify: `skills/autonomous-ticket/SKILL.md:42-46` (stage table), `:54-56` (step 1), `:82-86` (step 3 prompts), `:98-106` (step 5), `:111-128` (step 6, add step 7 after it), `:130-136` (Resume), `:162-170` (Rules), `:172-179` (rationalisations)

**Interfaces:**
- Consumes: `superpowers:ticket-revision` and the `🤖 revision:` report format from Task 1.
- Produces: the `rev` prompt, carrying the cutoff timestamp, that Task 1's step 1 reads.

**Depends on:** Task 1

- [ ] **Step 1: Replace the exec row and add the rev row in the stage table**

Replace this line:

```markdown
| exec | `<key>-exec` | sonnet | `superpowers:subagent-driven-development` | commits on `git.branch` after the plan commit; the project's analyse step and tests green; the ticket in `linear.states.finished` with a comment containing the PR URL |
```

with these two:

```markdown
| exec | `<key>-exec` | sonnet | `superpowers:subagent-driven-development` | commits on `git.branch` after the plan commit; the project's analyse step and tests green; a comment on the ticket containing the PR URL |
| rev | `<key>-rev` | sonnet | `superpowers:ticket-revision` | the ticket in `linear.states.finished` |
```

After the paragraph that starts "`<key>` is `ticket.key` lowercased" (ending "which is what makes those globs match."), add one paragraph:

```markdown
The rev row is current whenever exec is complete and the ticket is outside
`linear.states.finished`, which is every resume after a PR exists: the
daemon moves the ticket to In Progress before re-prompting you.
```

- [ ] **Step 2: Extend step 1 for the rev stage**

Replace:

```markdown
1. **Find the stage.** Walk the table top to bottom; the current stage is the
   first whose artefact is absent. If none is absent, post the verification
   comment (step 6) if it is not already on the ticket, and stop.
```

with:

```markdown
1. **Find the stage.** Walk the table top to bottom; the current stage is the
   first whose artefact is absent. If none is absent, post the verification
   comment (step 6) if it is not already on the ticket, and stop.

   When the stage is rev, run `herdr agent list`. If `<key>-rev` is live in
   this workspace, go to step 3. Otherwise collect the feedback: every
   comment after your most recent `🤖 orchestrator:` comment whose author is
   not the user the Linear MCP is authenticated as (`get_user` for the
   current user). If there is none, post

   ```
   🤖 orchestrator: nothing to revise
   no comments since the ticket was last moved to <linear.states.finished>
   ```

   move the ticket to `linear.states.finished`, and stop. Otherwise note the
   cutoff comment's timestamp for the prompt in step 3.
```

- [ ] **Step 3: Add the rev prompt and keep the tab id**

Replace:

```markdown
   - exec: `Ticket <key>, stage exec. Read .superpowers/ticket.json, then invoke superpowers:subagent-driven-development to execute the plan at <plan path>.`
```

with:

```markdown
   - exec: `Ticket <key>, stage exec. Read .superpowers/ticket.json, then invoke superpowers:subagent-driven-development to execute the plan at <plan path>.`
   - rev: `Ticket <key>, stage rev. Read .superpowers/ticket.json, then invoke superpowers:ticket-revision. Feedback is every comment after <ISO timestamp of the cutoff comment> not authored by the bot user.`

   For rev, keep the `tab_id` from the create response; step 7 closes it.
```

- [ ] **Step 4: Route rev through step 7 instead of the artefact check**

Replace:

```markdown
   - `idle` or `done`: check the stage's artefact.
     - Present: go to step 3 for the next stage, or to step 6 after exec.
```

with:

```markdown
   - `idle` or `done`: for rev, stop if the ticket is in
     `linear.states.stuck` (the child asked a question; the answer returns
     as a resume), otherwise go to step 7. For any other stage, check the
     stage's artefact.
     - Present: go to step 3 for the next stage, or to step 6 after exec.
```

- [ ] **Step 5: Add step 7 after step 6**

After the last line of step 6 (`   Then stop.`, following "comment the URL and move the ticket there yourself.") and before the `## Resume` heading, add:

````markdown
7. **Verify after rev.** In this worktree:

   1. Read the child's `🤖 revision:` comment on the ticket. Absent: prompt
      the child once with "Post your 🤖 revision: comment on the ticket and
      end your turn", wait as in step 4, and on the next wake, if it is
      still absent, post `🤖 orchestrator: rev produced no report` with the
      child's last 30 lines and stop.
   2. Run `git fetch origin <git.branch>`. The round is pushed when
      `git rev-parse HEAD` equals `git rev-parse origin/<git.branch>`. Not
      pushed: prompt the child once with "Push git.branch to origin", wait
      as in step 4, and check once more.
   3. Run the project's analyse step and its full test command as in step
      6, with the same single retry through the child.
   4. Post:

      ```
      🤖 orchestrator: revision
      pushed: <yes|no>
      analyse: <pass|fail>
      tests: <N passed, M failed>
      commits: <first sha7>..<last sha7> on <git.branch>
      PR: <url from the earlier verification comment>
      ```

   5. Move the ticket to `linear.states.finished`, whether or not everything
      passed. The comment says what failed; your human partner decides.
   6. If pushed, analyse and tests all passed, run
      `herdr tab close <tab_id>`. The `tab_id` is the one from step 3, or,
      when another orchestrator created the tab, the entry in
      `herdr tab list --workspace "$HERDR_WORKSPACE_ID"` whose label is
      `<key> rev`. If anything failed, leave the tab and add
      `tab: <tab_id> left open for inspection` to the comment.
   7. Stop.
````

- [ ] **Step 6: Extend the Resume section**

Replace:

```markdown
ticket back to the trigger state. Start again at step 1: the artefacts on
disk say which stage you are in, and step 3 re-prompts a child that is still
alive rather than starting a new one, so its context survives the pause.
```

with:

```markdown
ticket back to the trigger state. Start again at step 1: the artefacts on
disk say which stage you are in, and step 3 re-prompts a child that is still
alive rather than starting a new one, so its context survives the pause.

A ticket moved back from In Review lands in the rev stage. A rev child that
blocked or asked a question survives the pause and is re-prompted like any
other child; one whose round was closed is gone, and the next round starts
a fresh child under the same name.
```

- [ ] **Step 7: Amend the never-close rule**

Replace:

```markdown
- Never close a tab, pane or workspace, including ones you created. Your
  human partner reviews the PR from here.
```

with:

```markdown
- Never close a tab, pane or workspace, including ones you created, except
  the `<key> rev` tab in step 7 after a round that pushed and passed. Your
  human partner reviews the PR from here.
```

- [ ] **Step 8: Add the rationalisations**

After the table row that starts `| "Tests failed on something the ticket didn't touch`, add:

```markdown
| "The feedback is one line, I'll make the change myself" | You implement nothing. Start the rev child. |
| "Verification is red but the change is what they asked for, close the tab anyway" | Red leaves the tab. The comment says it is open and why. |
| "No live rev child and no new comments, so re-run exec" | Exec is complete. Post nothing to revise and move the ticket back. |
```

- [ ] **Step 9: Check the edits landed and nothing else moved**

Run:

```bash
rg -c "^\| rev \| |superpowers:ticket-revision|nothing to revise|^7\. \*\*Verify after rev|herdr tab close <tab_id>|left open for inspection|lands in the rev stage" skills/autonomous-ticket/SKILL.md
```

Expected: `8` (the count is of matching lines: the rev row, the rev prompt, two "nothing to revise" lines, the step 7 heading, the tab close, the left-open note, the Resume sentence).

Run: `git diff --stat skills/autonomous-ticket/SKILL.md`
Expected: one file; the insertion count exceeds the deletion count, and the deletion count is at most 12. A larger deletion count means a passage outside the edits above was rewritten; revert it.

Run: `rg -n "the ticket in \`linear.states.finished\` with a comment containing the PR URL" skills/autonomous-ticket/SKILL.md`
Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add skills/autonomous-ticket/SKILL.md
git commit -m "Add a rev stage to autonomous-ticket for review feedback rounds"
```

---

### Task 3: Document the round and bump the version

**Files:**
- Modify: `README.md:305` (unattended paragraph), `README.md:339` (skills list)
- Modify, through the script: `package.json`, `.hermes-plugin/plugin.yaml`, `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.devin-plugin/plugin.json`, `.kimi-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `gemini-extension.json`

**Interfaces:**
- Consumes: the skill names from Task 1 and Task 2.
- Produces: version `6.5.0` in every file `.version-bump.json` declares.

**Depends on:** Task 1, Task 2

- [ ] **Step 1: Extend the unattended paragraph**

Replace:

```markdown
Unattended: when `.superpowers/ticket.json` is present in a worktree, brainstorming, writing-plans, subagent-driven-development and finishing-a-development-branch replace their human gates with recorded rulings, and **autonomous-ticket** runs the chain stage by stage. See that skill for the blocker rule.
```

with:

```markdown
Unattended: when `.superpowers/ticket.json` is present in a worktree, brainstorming, writing-plans, subagent-driven-development and finishing-a-development-branch replace their human gates with recorded rulings, and **autonomous-ticket** runs the chain stage by stage. See that skill for the blocker rule. A ticket sent back from review with comments gets a **ticket-revision** round on the same branch and PR, and returns to review when the orchestrator has verified it.
```

- [ ] **Step 2: Add the skill to the skills list**

After the line:

```markdown
- **autonomous-ticket** - Orchestrates a Linear ticket through spec, plan and implementation in fresh Herdr children with no human gate
```

add:

```markdown
- **ticket-revision** - Addresses one round of review feedback on a ticket's existing branch and PR, started by autonomous-ticket
```

- [ ] **Step 3: Commit the README**

```bash
git add README.md
git commit -m "Document the ticket-revision skill and the review feedback round"
```

- [ ] **Step 4: Bump the version**

Run: `scripts/bump-version.sh 6.5.0`

Run: `scripts/bump-version.sh --audit`
Expected: every declared file reports `6.5.0` and the audit finds no `6.4.2` outside the excluded paths.

Run: `git diff --stat`
Expected: exactly 9 files, 9 insertions, 9 deletions.

- [ ] **Step 5: Commit the bump**

```bash
git add package.json .hermes-plugin/plugin.yaml .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json .devin-plugin/plugin.json .kimi-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json
git commit -m "Bump version to 6.5.0"
```

---

## Verification after the plan (manual, by your human partner)

The spec's Testing section: with the plugin reinstalled at 6.5.0 and the Linear MCP authenticated as the bot user, take a ticket that is in In Review on the pipeline, post one comment asking for a visible change, and drag it to Todo. Expect a `<key> rev` tab, a `🤖 revision:` comment listing the item, a `🤖 orchestrator: revision` comment, the ticket back in In Review, the PR carrying the new commit, and the rev tab gone. Repeat with a second comment to see the round run again under the same child name. Then post a comment that raises a design question to see the `❓` path and the re-prompt after answering.
