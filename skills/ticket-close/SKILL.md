---
name: ticket-close
description: CLOSE stage of /ticket - once the ticket's PR is merged, marks the ticket done, cleans up the branch and worktree, and closes the workspace. Changes nothing while the PR is not merged.
---

# CLOSE

Read `patrick-workflows:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`. Ask nothing; running `/ticket <id>` is the request.

1. Phase must be `pr`. `STATE=$(bash "$SKILL_DIR/../ticket-workspace/scripts/pr-state.sh" <pr_url>)`.
   - `open` → say the PR is still open (and its URL); change nothing.
   - `closed-unmerged` → say it was closed without merging; change nothing; suggest reopening or starting a new round with `/ticket <id>` after reopening.
   - `could-not-run` → say `gh` could not read the PR; change nothing.
2. `merged`:
   1. Mark the ticket done with what the machine offers: a GitHub issue → `gh issue close <n> --comment "Done in <pr_url>"`; another tracker → its MCP tool if available; otherwise print the one manual step. Report which happened.
   2. If the session is in the ticket's worktree, `ExitWorktree` with `action: "keep"` first.
   3. If `checkout` is a worktree path: `git worktree remove <path>` (never with `--force`; report a refusal).
   4. In the main checkout, if its tree is clean (this is where `git switch` runs): `git switch <base_branch>` and, when a remote exists, `git pull --ff-only`.
   5. Delete the local branch with `git branch -d <branch>` (never `-D`). If git refuses, report it and tell the user they may delete it themselves with `git branch -D <branch>` after checking it was merged (e.g. squash merges).
   6. Ledger line with `date -u +%Y-%m-%dT%H:%M:%SZ`; `S phase closed`. Tell the user the ticket is closed.
