# Autonomous Ticket Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (superpowers:executing-plans only where subagents are unavailable). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `autonomous-ticket` orchestrator skill and an unattended mode to `brainstorming`, `writing-plans`, `subagent-driven-development` and `finishing-a-development-branch`, so a Linear ticket can run through the whole chain in a Herdr worktree with no human gate, stopping only on a genuine blocker.

**Architecture:** One marker file, `.superpowers/ticket.json`, written by the ticket-pipeline daemon, switches the four existing skills into unattended mode through a short paragraph each. The new skill owns all orchestration: it spawns a fresh Herdr child per stage (spec, plan, exec), waits, verifies the stage artefact, and reports to the ticket through the Linear MCP. The existing skills never hand off; they do their job and end the turn.

**Tech Stack:** Markdown skills in the superpowers plugin voice; bash for the checks the skills run; the Linear MCP (`linear-server`) for ticket reads and writes; Herdr CLI for tabs, agents and waits.

**Spec:** `/home/dev/code/active/ticket-pipeline/docs/superpowers/specs/2026-09-19-ticket-pipeline-design.md`, sections "The marker file" and "Superpowers fork changes".

**Execution:** waves

## Global Constraints

- Unattended mode is on when, from the repo root of the current working directory, `.superpowers/ticket.json` exists and its `unattended` field is `true`. The check is `test -f "$(git rev-parse --show-toplevel)/.superpowers/ticket.json"` followed by reading the JSON.
- The marker's shape: `{ version, unattended, ticket: { key, title, url, description, labels, priority }, linear: { states: { stuck, finished } }, git: { branch, base, forge }, authorised: ["push", "pr"] }`.
- The blocker procedure is defined once, in `skills/autonomous-ticket/SKILL.md`, under the heading `## Blockers`. The other skills refer to it by that name; they do not restate it.
- A blocker comment on the ticket starts with `❓`. Orchestrator comments start with `🤖 orchestrator:`.
- No skill in unattended mode calls `AskUserQuestion`, presents a menu, offers the visual companion, or waits for a human reply.
- Stage children are named `<key lowercased>-spec`, `<key lowercased>-plan`, `<key lowercased>-exec`; the orchestrator itself is `tp-<key lowercased>`. Names match `[a-z][a-z0-9_-]{0,31}`.
- Stage models: spec `opus`, plan `opus`, exec `sonnet`.
- Existing skill text outside the inserted paragraphs is left untouched: no rewording, no reformatting, no reflow.
- The plugin voice: "your human partner", not "the user"; imperative; no comments about the change inside the skill text.
- Version bump lands last, as its own commit, touching exactly the nine files the previous bump touched.

---

### Task 1: The `autonomous-ticket` skill

**Files:**
- Create: `skills/autonomous-ticket/SKILL.md`

**Interfaces:**
- Consumes: the marker file shape (Global Constraints); Herdr CLI (`herdr tab create`, `herdr agent start|prompt|wait|get|list|read`); the Linear MCP's issue read, comment list, comment create and issue update tools.
- Produces: the `## Blockers` procedure that Tasks 2 to 5 refer to; the stage table and prompts the children receive.

**Depends on:** none

- [ ] **Step 1: Write the skill file**

`skills/autonomous-ticket/SKILL.md`:

````markdown
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

## The marker

Read `.superpowers/ticket.json` from the repo root. If it is missing, say
so and stop: this skill only runs where the daemon put a ticket. Keep
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

`<key>` in a child name is `ticket.key` lowercased with any character outside
`[a-z0-9_-]` replaced by `-`.

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

   - spec: `Ticket <key>, stage spec. Read .superpowers/ticket.json and the ticket's comments through the Linear MCP, then invoke superpowers:brainstorming for the ticket.`
   - plan: `Ticket <key>, stage plan. Read .superpowers/ticket.json, then invoke superpowers:writing-plans for the spec at <spec path>.`
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
````

- [ ] **Step 2: Check the frontmatter parses and the file is discoverable**

Run: `head -4 skills/autonomous-ticket/SKILL.md`
Expected: `---`, `name: autonomous-ticket`, a one-line `description:`, `---`.

Run: `grep -c '^## ' skills/autonomous-ticket/SKILL.md`
Expected: `7` (The marker, Stages, Procedure, Resume, Blockers, Rules, Common Rationalizations).

- [ ] **Step 3: Commit**

```bash
git add skills/autonomous-ticket/SKILL.md
git commit -m "Add autonomous-ticket orchestrator skill"
```

---

### Task 2: Unattended mode in `brainstorming`

**Files:**
- Modify: `skills/brainstorming/SKILL.md:20-22` (insert between `</HARD-GATE>` and `## Three Paths`)

**Interfaces:**
- Consumes: the `## Blockers` procedure in `skills/autonomous-ticket/SKILL.md` (Task 1), the marker shape.
- Produces: a spec with a `## Rulings` section, committed on `git.branch`, and the turn ended.

**Depends on:** Task 1

- [ ] **Step 1: Insert the unattended section**

Immediately after the line `</HARD-GATE>` and its blank line, before `## Three Paths`, insert:

````markdown
## Unattended Mode

When `.superpowers/ticket.json` exists at the repo root with `unattended`
true, there is no human partner in the pane and the gate above is replaced
by rulings. Check with:

```bash
test -f "$(git rev-parse --show-toplevel)/.superpowers/ticket.json"
```

In unattended mode:

- The request is the ticket in that file plus its comments on Linear.
  Classify it as architectural whatever its size, so a spec is always
  written. Explore project context as written.
- Answer each clarifying question from the ticket and its comments. A
  question they settle uses their answer. A question with a sensible
  default gets a ruling. A question that meets the blocker test in
  `autonomous-ticket`'s `## Blockers` stops the run by that procedure:
  gather every such question first and post them in one comment.
- Propose the approaches to yourself and take the recommended one. No
  approval message.
- The spec gets a `## Rulings` section, one line per ruling in the form
  `<what was decided> — <why> — <what it costs if wrong>`, the approach
  choice included. It is the first thing the PR reviewer reads.
- Never offer the visual companion.
- Run the spec self-review, commit the spec on the current branch, and end
  the turn. No user review gate, no Herdr offer, no writing-plans: the
  orchestrator starts the next stage.

Everything below this section describes the interactive flow.

````

- [ ] **Step 2: Verify the insertion and that nothing else changed**

Run: `git diff --stat`
Expected: one file, insertions only.

Run: `sed -n 20,24p skills/brainstorming/SKILL.md`
Expected: `</HARD-GATE>`, blank, `## Unattended Mode`, blank, `When ...`.

Run: `grep -n '^## Three Paths' skills/brainstorming/SKILL.md`
Expected: the heading still present, now after the inserted section.

- [ ] **Step 3: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "Add unattended mode to brainstorming"
```

---

### Task 3: Unattended mode in `writing-plans`

**Files:**
- Modify: `skills/writing-plans/SKILL.md:163-166` (insert after the first paragraph of `## Execution Handoff`)

**Interfaces:**
- Consumes: the marker shape.
- Produces: a committed plan with `**Execution:** waves` when the graph allows, and the turn ended.

**Depends on:** Task 1

- [ ] **Step 1: Insert the unattended paragraph**

After the paragraph that begins `After saving the plan, pick the execution skill yourself` (and its blank line), before `**Default:**`, insert:

````markdown
**Unattended mode.** When
`test -f "$(git rev-parse --show-toplevel)/.superpowers/ticket.json"`
passes and that file's `unattended` is true, there is no one to approve
the plan. Compute the waves as described under "Offer waves" below. If the
wave count is below the task count, add `**Execution:** waves` to the plan
header; otherwise leave the line out. Commit the plan on the current branch
and end the turn. No menu, no "say go", no Herdr offer, no handoff: the
orchestrator starts the executor. A spec requirement the plan cannot cover
without a guess is a blocker under `autonomous-ticket`'s `## Blockers`.

````

- [ ] **Step 2: Verify**

Run: `git diff --stat`
Expected: one file, insertions only.

Run: `grep -n -A1 'Unattended mode' skills/writing-plans/SKILL.md | head -3`
Expected: the paragraph sits inside `## Execution Handoff`, before `**Default:**`.

- [ ] **Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "Add unattended mode to writing-plans"
```

---

### Task 4: Unattended mode in `subagent-driven-development`

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:27-31` (insert after the "Four things stop you" paragraph)

**Interfaces:**
- Consumes: the marker's `git.branch`, `git.base`, `authorised`; the `## Blockers` procedure.
- Produces: an SDD run that pushes and opens a PR without asking, and stops only through the blocker procedure.

**Depends on:** Task 1

- [ ] **Step 1: Insert the unattended paragraph**

After the paragraph ending `For those,\nstop and ask.` and its blank line, before `## When to Use`, insert:

````markdown
**Unattended mode.** When
`test -f "$(git rev-parse --show-toplevel)/.superpowers/ticket.json"`
passes and that file's `unattended` is true, "stop and ask" means the
blocker procedure in `autonomous-ticket`'s `## Blockers`: a `❓` comment on
the ticket through the Linear MCP, the ticket moved to `linear.states.stuck`,
and the turn ended. Never a question in the pane. When the file's
`authorised` lists `push` and `pr`, pushing `git.branch` to `origin` and
opening a pull request against `git.base` are not stop classes; merging
into `git.base`, force-pushing, and deleting branches still are.

````

- [ ] **Step 2: Verify**

Run: `git diff --stat`
Expected: one file, insertions only.

Run: `grep -n -B2 '^## When to Use' skills/subagent-driven-development/SKILL.md`
Expected: the inserted paragraph's last line, a blank line, then the heading.

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "Add unattended mode to subagent-driven-development"
```

---

### Task 5: Unattended mode in `finishing-a-development-branch`

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md:80-84` (insert before the paragraph `Present the menu exactly as written`)

**Interfaces:**
- Consumes: the marker's `git.branch`, `git.base`, `git.forge`, `authorised`, `linear.states.finished`, `ticket.url`.
- Produces: a pushed branch, a PR, the PR URL commented on the ticket, and the ticket in the finished state.

**Depends on:** Task 1

- [ ] **Step 1: Insert the unattended paragraph**

In `## Step 4: Present Options`, immediately before the paragraph that begins `Present the menu exactly as written`, insert:

````markdown
**Unattended mode.** When
`test -f "$(git rev-parse --show-toplevel)/.superpowers/ticket.json"`
passes, that file's `unattended` is true, and its `authorised` lists both
`push` and `pr`, your human partner has already chosen option 3. Do not
present the menu. Run Option 3 with `<feature-branch>` = `git.branch` and
`<base-branch>` = `git.base`, using `gh` when `git.forge` is `github` and
`tea` when it is `gitea`. When the PR exists, through the Linear MCP,
comment its URL on the ticket at `ticket.url` and move the ticket to
`linear.states.finished`. A failing suite in Step 1 is a blocker under
`autonomous-ticket`'s `## Blockers`, not a report in the pane.

````

- [ ] **Step 2: Verify**

Run: `git diff --stat`
Expected: one file, insertions only.

Run: `grep -n -A1 'Unattended mode' skills/finishing-a-development-branch/SKILL.md | head -2`
Expected: inside `## Step 4: Present Options`, above `Present the menu exactly as written`.

- [ ] **Step 3: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "Add unattended mode to finishing-a-development-branch"
```

---

### Task 6: Document the skill and bump the version

**Files:**
- Modify: `README.md:267-275` (the numbered workflow list) and `README.md:300-306` (the skills list)
- Modify: `.claude-plugin/plugin.json:4`, `.claude-plugin/marketplace.json:12`, `.codex-plugin/plugin.json:3`, `.cursor-plugin/plugin.json:5`, `.devin-plugin/plugin.json:3`, `.hermes-plugin/plugin.yaml:2`, `.kimi-plugin/plugin.json:3`, `gemini-extension.json:4`, `package.json:3`

**Interfaces:**
- Consumes: the skill name from Task 1.
- Produces: version `6.4.0` everywhere the previous bump touched.

**Depends on:** Task 1, Task 2, Task 3, Task 4, Task 5

- [ ] **Step 1: Add the skill to the README**

In the skills list near line 300 (the block of `- **<skill>** - <one line>` entries), add after the `finishing-a-development-branch` entry:

```markdown
- **autonomous-ticket** - Orchestrates a Linear ticket through spec, plan and implementation in fresh Herdr children with no human gate
```

After the numbered workflow list (the item `7. **finishing-a-development-branch** ...`), add one paragraph:

```markdown
Unattended: when `.superpowers/ticket.json` is present in a worktree, brainstorming, writing-plans, subagent-driven-development and finishing-a-development-branch replace their human gates with recorded rulings, and **autonomous-ticket** runs the chain stage by stage. See that skill for the blocker rule.
```

- [ ] **Step 2: Commit the README**

```bash
git add README.md
git commit -m "Document the autonomous-ticket skill and unattended mode"
```

- [ ] **Step 3: Bump the version in the nine files**

Run:

```bash
sed -i 's/"version": "6\.3\.4"/"version": "6.4.0"/' .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json .cursor-plugin/plugin.json .devin-plugin/plugin.json .kimi-plugin/plugin.json gemini-extension.json package.json
sed -i 's/^version: 6\.3\.4$/version: 6.4.0/' .hermes-plugin/plugin.yaml
```

Run: `grep -rn '6\.3\.4' --exclude-dir=node_modules --exclude-dir=docs --exclude-dir=.git .`
Expected: no output.

Run: `git diff --stat`
Expected: exactly 9 files, 9 insertions, 9 deletions.

- [ ] **Step 4: Commit the bump**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json .cursor-plugin/plugin.json .devin-plugin/plugin.json .hermes-plugin/plugin.yaml .kimi-plugin/plugin.json gemini-extension.json package.json
git commit -m "Bump version to 6.4.0"
```

---

## Verification after the plan (manual, by the human partner)

Skill behaviour cannot be unit-tested; the fork verifies changes with a real
session. After merging and pushing the branch, and updating the installed
plugin (`claude plugin update superpowers@superpowers-dev`, or whatever
`claude plugin` reports as the update command):

1. In a scratch repo with a `main` branch and a trivial test suite, create a
   worktree on branch `probe-1-hello` and write
   `.superpowers/ticket.json` by hand with `unattended: true`, a ticket key
   `PROBE-1`, a description like "Add a `hello()` function returning
   'hello' with a test", `git.base: main`, `git.forge: github`,
   `authorised: ["push", "pr"]`, and the real URL of a throwaway Linear
   ticket in a test team.
2. In a Herdr pane in that worktree, start a Claude agent named `tp-probe-1`
   and prompt it `Invoke superpowers:autonomous-ticket.`.
3. Expect, in order: a `probe-1-spec` tab whose session writes and commits a
   spec with a `## Rulings` section and ends without asking anything; a
   `probe-1-plan` tab that commits a plan and ends; a `probe-1-exec` tab
   that implements, pushes, opens a PR and moves the Linear ticket to In
   Review with the URL commented; then the orchestrator's verification
   comment.
4. Then edit the ticket description to contradict itself (say, "returns
   'hello'" and "returns 'goodbye'"), delete the spec commit, prompt the
   orchestrator to resume, and expect a `❓` comment and the ticket in
   Needs Info with no pane question anywhere.

Any pane question during either run is a skill defect: note which skill and
which gate, and fix that paragraph.
