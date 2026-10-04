# Spike: agent worktree isolation (sub-project D)

Date: 2026-10-04. One Haiku agent was dispatched with `isolation: "worktree"`; it printed its location and made one commit. The main session then inspected the result.

## Answers
- **Path:** `<repo>/.claude/worktrees/agent-<id>`. It shows as untracked (`.claude/`) in the main checkout unless it is ignored.
- **Branch:** `worktree-agent-<id>`. The dispatch result names both the path and the branch.
- **Start commit:** the remote's default branch (`origin/main`, `c510b95`), **not** the local HEAD (`00b3228`). An implementer must be moved to the right commit first: `git reset --hard <sha>` inside the worktree worked, because worktrees share the object database.
- **Lifetime:** a worktree with changes survives the agent and is `locked`. The main checkout can still read its branch.
- **Cherry-pick:** `git cherry-pick <base>..worktree-agent-<id>` from the main session onto the local HEAD worked.
- **Cleanup:** `git worktree remove --force <path>` then `git branch -D worktree-agent-<id>`.

## Consequences
BUILD passes `START: <wave_base>` and the implementer resets to it before working. BUILD then cherry-picks `<wave_base>..<branch>` in plan order, removes the worktree and branch, and adds `.claude/worktrees/` to `info/exclude`. Isolation works, so the spec's sequential fallback is not needed.
