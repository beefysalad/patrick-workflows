# Pipeline Completion: Design

Date: 2026-10-03
Status: Draft for review
Builds on: `docs/superpowers/specs/2026-10-02-ticket-pipeline-design.md` (v7, "the base spec"), implemented through v0.3.0.

## Purpose

Finish the ticket pipeline: UI grading, CLOSE, guardrail hooks, a full review depth, and parallel tasks, plus the minor issues deferred from the 1a and 1b reviews.

### Decisions recorded (from the user, 2026-10-03)
1. Obsidian notes are **out of scope** for this round.
2. Guardrail hooks are **mixed**: the no-attribution guard applies everywhere; push and base-branch guards apply only while a ticket is in progress for that repo.
3. Parallel tasks are **on automatically when safe**, visible in the PLAN brief and switchable off.
4. The separate pluggable integration-test step is **dropped**: the exit pair (`--prove`) already covers it.

### Non-goals
Obsidian or any knowledge base; multi-machine or multi-model setups; changes to the phase machine beyond what CLOSE needs.

## Sub-projects and order

| # | Sub-project | Depends on |
|---|---|---|
| A | UI grading, CLOSE, deferred minors | v0.3.0 |
| B | Guardrail hooks | A (push approval key written by SHIP) |
| C | Full review depth with challenger | v0.3.0 |
| D | Parallel tasks | A, C (stable BUILD) |

Each sub-project gets its own plan, is implemented with subagent-driven development and TDD, ends with a whole-branch review, and starts with a spike for its unknowns.

## A. UI grading, CLOSE, deferred minors

### A1. Graded bar (implements base spec section 9.4)
- **PLAN:** when the ticket has a visual or quality reference, the brief adds a graded bar: `reference` (image, URL, or existing route), `routes` to capture, a `rubric.md` with 3–6 criteria and written anchors for scores 1, 3 and 5, `margin` (default 0.3), `floor` (default 3.5), `min_criterion` (default 3), and the dev command. Stored in state as `graded: <path to graded.md>`.
- **`dev-server.sh start|stop|status`** (review-mine scripts): picks a free port, starts the dev command with `PORT` set, waits for an HTTP response with a timeout, writes a PID file in the workspace, stops on `stop`, and cleans a stale PID file on `start`. Stop is idempotent.
- **`capture.sh <base-url> <routes-file> <out-dir>`**: for each route, screenshots at 1440×900 and 390×844, light and dark, via `npx playwright screenshot --viewport-size=W,H --full-page --color-scheme=S`; falls back to Chrome headless (`--headless --screenshot --window-size`); prints `CAPTURE: ok N` or `CAPTURE: could-not-run <reason>`.
- **`ui-scorer` agent** (read-only, Opus): receives folders `A/` and `B/` (reference and ours, randomly assigned by the orchestrator, recorded in the workspace only), the rubric, and returns scores per criterion for both plus a concrete gap for every criterion of ours below 4. It is never told which folder is ours.
- **Pass rule:** ours ≥ reference − margin, ours ≥ floor, no criterion below `min_criterion`, confirmed by a second fresh scorer. Progress counts only at ≥ 0.2 improvement; plateau after 2 non-improving rounds (standard and full only).
- **Integration:** the review loop treats the graded bar like correctness: unmet → its gaps go to the fixer with the findings; budget +5 per graded bar (standard), +3 (lite). `could-not-run` is reported, never skipped silently, and ends the run BLOCKED rather than looping. The reference is one page, compared with the first route only; a non-2xx page is never captured (final review I3/I4).

### A2. CLOSE (implements base spec section 12a)
- New stage skill `ticket-close`; router sends phase `pr` to it.
- `gh pr view <url> --json state,mergedAt`: not merged → report state, change nothing. Merged → set the ticket Done with the machine's tracker tool (GitHub: `gh issue close <issue_url>` with a comment, by the URL stored at intake, never by bare number; other trackers: an MCP tool if available; otherwise print the one manual step), `git switch <base_branch>` + `git pull --ff-only` when clean, delete the merged local branch (`-D` only when its tip equals the PR's `headRefOid`), remove the worktree via `ExitWorktree`/`git worktree remove` when one was used, `S phase closed`.

### A3. Deferred minors folded in
1. `branch-name.sh` refuses IDs that slug to nothing; PLAN validates user-renamed branches with `git check-ref-format --branch`.
2. State key `type` (`feat`/`fix`) set in PLAN, used by SHIP for the PR title.
3. Embedded review-mine keeps its budget across a rerun after a crash (reads the existing `state.md` instead of rewriting it).
4. Ledger timestamps always from `date -u +%Y-%m-%dT%H:%M:%SZ`; skills say so.
5. Non-ASCII file names (done in 1b), round counter (done in 1b), fallback base (done in 1b), exit-pair log labels (done in 1b): verified, no work.

## B. Guardrail hooks

- **Delivery:** `hooks/hooks.json` registers one `PreToolUse` hook on `Bash`, running `bash "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"`. The script reads the hook JSON from stdin, extracts the command, and exits 0 to allow or 2 with a reason on stderr to block (exact contract verified in the B spike).
- **Rules:**
  | Rule | Scope | Blocks |
  |---|---|---|
  | No attribution | always | `git commit` or `gh pr create/edit` whose text contains a co-author trailer for Claude or a "Generated with Claude Code" footer |
  | Push only after approval | a ticket for the current branch is in a phase before `pr` | `git push` unless that ticket's state has `push_approved: yes` |
  | No commits on the base branch | a ticket in this repo with this branch as `base_branch` is between `approved` and `handoff` | `git commit` on that base branch |
- SHIP sets `push_approved: yes` immediately before its push, after the secrets scan and the user's yes.
- The guard finds tickets through `ticket-ws.sh list` and `state.sh`; it never blocks when it cannot find or parse state (fails open, prints nothing), so it cannot break unrelated work.
- Pure bash, no `jq`: the command is taken from the JSON by pattern, with JSON escapes for quotes and backslashes undone.

## C. Full review depth with challenger

- Depth `full`: chosen by the user, or suggested by PLAN when the scope is security-sensitive and the plan has more than 5 tasks.
- Round-1 critics: `impact` (Opus), `security` (Opus), `regression` (Sonnet), `requirements` (Sonnet, verdict), `maintainability` (Sonnet).
- **`finding-challenger` agent** (read-only, Opus): after the evidence filter, receives each Critical/Important finding with the package and tries to refute it with a concrete reason from the code (`REFUTED <reason>` or `STANDS`). Refuted findings are dropped and listed in the report under "Refuted by the challenger"; a refuted Critical is listed first so the user can overrule.
- Budget: review 16 (5 critics + 1 challenger + up to 4 × (fixer + re-review) + 1 protected); `rounds_max` 4; implementation budget 4 × tasks.

## D. Parallel tasks

- **Planner output:** every task lists `Files:` (create/modify) and `Depends on:` (task numbers or `none`). `ticket-planner` is updated to always emit both.
- **Waves:** `waves.sh <plan.md>` prints waves: a task joins the earliest wave after all its dependencies whose file set is disjoint from every other task already in that wave. Tasks with no `Files:` line run alone. Deterministic, unit-tested.
- **Execution:** in a wave of more than one task, BUILD dispatches one `task-implementer` per task in parallel with the agent tool's worktree isolation; each commits on its own worktree branch. After the wave, BUILD merges each task's commits onto the ticket branch in plan order (`git cherry-pick <range>`); a conflict aborts that cherry-pick and the task is re-run sequentially on top of the merged result. Gates, scope check, and the per-task reviewer then run per task as today.
- **Brief:** PLAN shows the waves (e.g. "Wave 1: tasks 1, 2, 3 in parallel; wave 2: task 4") and a `parallel: on|off` switch, default `on`. Budgets are unchanged.
- The worktree-isolation contract (where the worktree lives, how the branch is named, whether it survives the agent) is verified in the D spike; if isolation cannot be made to work, D falls back to sequential execution with waves shown for information only.

## Verification
- Every new script: bash tests under `/bin/bash`, red first.
- Agents and skills: `validate.sh` (read-only agents include `ui-scorer` and `finding-challenger`), `claude plugin validate`.
- Smoke: a UI fixture (a static page plus a reference image) for A1; the existing FX-1 fixture extended for CLOSE (a merged PR cannot be faked locally, so CLOSE's merged path is checked with a stubbed `gh` on `PATH` in a script test); hook tests feed recorded hook JSON to `guard.sh`; a 3-task fixture with two independent tasks for D.

## Spikes
- A: `npx playwright screenshot` flags as installed; image reading by a read-only agent.
- B: plugin hook JSON shape on stdin, block semantics (exit code 2, stderr shown to Claude), `${CLAUDE_PLUGIN_ROOT}` expansion.
- D: agent `isolation: worktree`: worktree path, branch name, lifetime, and whether the main session can cherry-pick from it.
