# Unattended Mode

Part of superpowers:subagent-driven-development. A
`.superpowers/ticket.json` marker exists at the repo root.

When that file's `unattended` is true, "stop and ask" means the
blocker procedure in `autonomous-ticket`'s `## Blockers`: a `❓` comment on
the ticket through the Linear MCP, the ticket moved to `linear.states.stuck`,
and the turn ended. Never a question in the terminal. When the file's
`authorised` lists `push` and `pr`, pushing `git.branch` to `origin` and
opening a pull request against `git.base` are not stop classes; merging
into `git.base`, force-pushing, and deleting branches still are. The
worktree holding that file is the workspace: treat it as a preference
already declared, so Setup skips using-git-worktrees' Step 0 consent
question, never creates another worktree, and commits on `git.branch`. The
pin check's "ask" in waves.md goes the same way — a refusal there is not a
blocker, serial is the documented fallback, and only a genuine ambiguity
left over from that check takes the `❓` path, never a question in the terminal.
