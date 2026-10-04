---
name: ticket-workspace
description: Reference for the /ticket pipeline - workspace layout, state keys, phase machine, ruling and finding formats, and the shared scripts. Read by every ticket stage skill; use when any /ticket stage starts.
---

# Ticket workspace

`SKILL_DIR` is this skill's base directory; its scripts run as `bash "$SKILL_DIR/scripts/<name>.sh"`. Stage skills call them as `bash "$SKILL_DIR/../ticket-workspace/scripts/<name>.sh"`.

## Location
`bash "$SKILL_DIR/scripts/ticket-ws.sh" path <id>` → `~/.patrick-workflows/tickets/<repo>/<id>/` (`TICKETS_HOME` overrides the root). The same path from every worktree of the repo. Never inside the project, never under `~/.claude/` (Claude Code refuses writes there).

## Layout
```
state.md        machine-readable "key: value" lines (below); change only via state.sh
ticket.md       ticket text verbatim
bar.md          acceptance criteria AC1..ACn, plus a "Deferred:" list
design.md       approved design
plan.md         approved plan (round 2 appends tasks under "## Round 2")
rulings.md      binding rulings
scope.txt       allow:/forbid: lines for scope-check.sh
ledger.md       one line per completed step; state.sh appends phase changes
baseline.md     gate results on the base commit
briefs/task-N.md, reports/task-N.md
review-mine/    the review loop's own workspace (state, logs, rounds, report.md)
handoff.md      the SHIP report; pr-body.md the draft PR body
```

## State keys
`ticket`, `title`, `phase`, `branch`, `base` (sha), `base_branch`, `checkout` (`main` or the worktree path), `depth` (`lite`|`standard`), `tasks_total`, `tasks_done`, `round2` (`no`|`yes`), `budget_impl_max`, `budget_impl_used`, `budget_review_max`, `gate.<name>` (command), `gate_timeout`, `exit_pair` (`none` or the exit-pair flags), `pr_target`, `pr_url`, `preflight` (`done`), `type` (`feat`|`fix`), `graded` (path to `graded.md`), `issue_url` (GitHub issue URL, set at intake; CLOSE closes the issue by it).

## Phases
`bash state.sh <WS>/state.md phase <new>` is the only way to change phase; it refuses illegal jumps and logs every change.
```
intake → designed → planned → approved → implementing → reviewing ⇄ fixing → ready
implementing | reviewing | fixing → blocked
ready | blocked → handoff → round2 → implementing ...      handoff → pr → closed
```
| Phase | Stage skill |
|---|---|
| none, intake, designed, planned | `patrick-workflows:ticket-plan` |
| approved, round2, implementing, reviewing, fixing | `patrick-workflows:ticket-build` |
| ready, blocked, handoff | `patrick-workflows:ticket-ship` |
| pr | `patrick-workflows:ticket-close` |
| closed | nothing left to do |

## Worktrees
If `checkout` is a worktree path and the session is not inside it, call the `EnterWorktree` tool with `path` set to it before running any stage. A worktree created with plain `git worktree add` outside the repo is not writable from the session.

## Formats
Ruling (`rulings.md`):
```
R3 — <title> (source: user | orchestrator)
Decision: ... / Why: ... / Cost if wrong: ... / Applies to: all | task N
```
Finding: the format in `patrick-workflows:final-reviewer` (ID, Severity, Kind, Location, Trigger, Expected, Actual).
Ledger line: `<UTC time> <step> <result>`. Ledger time: always `date -u +%Y-%m-%dT%H:%M:%SZ`.

## Scripts
| Script | Use |
|---|---|
| `state.sh <state.md> get/set/incr/phase ...` | state and phases |
| `ticket-ws.sh path/init/list` | workspace location |
| `branch-name.sh <type> <id> <title...>` | branch name |
| `pr-state.sh <pr>` | merged / open / closed-unmerged / could-not-run |
| `pr-state.sh --head-matches <pr> <branch>` | same / differs / could-not-run: local branch tip vs the PR head |
| `secret-scan.sh [--deny-file f] <file or ->...` | secrets before a PR |
