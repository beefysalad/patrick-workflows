---
name: ticket-build
description: BUILD stage of /ticket - runs the approved plan task by task with fresh implementers and reviewers, then the review-mine loop, without asking the user anything. Ends at ready or blocked and hands over to SHIP.
---

# BUILD

Read `patrick-workflows:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`; `R` = `$SKILL_DIR/../review-mine/scripts`.

## Rules
- Ask the user nothing. Stop only for: an irreversible or destructive action, a security-sensitive action, an outside side effect (push, publish, send), or a plan so broken that every path is a guess. Every other decision is a ruling in `WS/rulings.md` (`source: orchestrator`, with cost if wrong).
- Never push. Never edit settings. Commit messages carry no trailers.
- Never trust a subagent's claim of green: re-run the gates yourself.
- Ledger: one line per completed step in `WS/ledger.md`.
- Resume: after a crash or `/clear`, read `state.md`, `ledger.md` and `git log`; a task with a `task N complete` ledger line is done.

## 0. Every entry, including resumes
`git branch --show-current` must equal `branch`. If it does not and the tree is clean, `git switch <branch>`; if the tree is dirty, stop and tell the user (another branch has uncommitted work). Never commit on any other branch.

## 1. Pre-flight (skip if `preflight` is `done`)
1. Phase must be `approved` or `round2`; HEAD on `branch`; tree clean.
2. `bash "$R/workspace.sh" --at "<WS>/review-mine"` (sets the pointer every review script uses).
3. Baseline, only when `round2` is `no` and HEAD equals `base`: run each gate as `bash "$R/run-gate.sh" baseline-<name> <gate_timeout> -- "<command>"`; write `WS/baseline.md` (status per gate, citing `review-mine/logs/baseline-<name>.status`; failing gates are known reds). For a known-red gate, also list the names of the failing tests from its log, so later runs can tell old failures from new ones. Write `WS/gates.txt` with one `<name>: <command>` line per gate. A gate that is `could-not-run` → `S phase implementing`, `S phase blocked`, ledger the reason, and go to section 4.
4. If `exit_pair` is not `none`: `bash "$R/exit-pair.sh" --check <flags>`; refused → drop it with a ruling and `S set exit_pair none`.
5. `S phase implementing`, then `S set preflight done` (in this order, so a crash in between reruns pre-flight instead of leaving the phase behind).

In round 2, `ticket-ship` resets `preflight`; this stage then repeats steps 1, 2, 4 and 5 and keeps the original baseline.

## 2. Task driver
For each `### Task N` in `plan.md` (and the tasks under `## Round 2` when `round2` is `yes`; their numbers continue from round 1) without a `task N complete` ledger line, in order:
1. Record `task_base` = `git rev-parse HEAD`.
2. Write `WS/briefs/task-N.md`: the task text verbatim; the rulings that apply; one gate line per gate (`bash "$R/run-gate.sh" task<N>-<name> <gate_timeout> -- "<command>"`); the scope file `WS/scope.txt`; `REPORT: WS/reports/task-N.md`.
3. Before any dispatch: if `budget_impl_used` ≥ `budget_impl_max`, add a ruling, stop the task driver, and go to section 3 (the review budget is separate).
4. **standard:** dispatch `patrick-workflows:task-implementer` (model sonnet) with `BRIEF`; `S incr budget_impl_used`. **lite:** implement the task yourself under `superpowers:test-driven-development` and write the same report.
5. Report says `BLOCKED` → ruling; if the plan cannot continue without the task, that is stop condition 4: `S phase blocked`, go to section 4.
6. Re-run every gate as `task<N>-<name>`, and run the test named in the report's GREEN line yourself: it must pass at HEAD. The reviewer checks that the RED test would fail without the change. A gate counts as **new red** when it fails now but passed in the baseline, **or** when it was a known red and its log now names a failing test that the baseline did not. A new red is triaged: product bug → fix round; test defect → fix the test, not the product; environment → record a blocker and do not touch product code; hung → one retry with a longer timeout only if a ruling allows. Then `bash "$R/scope-check.sh" <task_base> "<WS>/scope.txt"`: `forbidden` → fix round; `out-of-scope` → ruling.
7. **standard:** `bash "$R/review-package.sh" <task_base> HEAD "<WS>/review-mine/tasks/task-N"`; dispatch `patrick-workflows:task-reviewer` with `BRIEF`, `REPORT`, `PACKAGE`, `RULINGS`; `S incr budget_impl_used`. `CHANGES` → fix round.
8. **Fix round** (at most 2 per task): a new `task-implementer` dispatch with `BRIEF` plus `FINDINGS` (the open Critical/Important findings and gate failures, written to `WS/briefs/task-N-fix<k>.md`), then steps 6–7 again with a new reviewer. Still open after 2 rounds → append them to `WS/bar.md` under `Known open issues to verify:` so the review loop checks them again.
9. Ledger: `task N complete <task_base>..<HEAD> gates <summary> review <verdict>`; `S incr tasks_done`.

## 3. Review loop
1. `S phase reviewing`.
2. Invoke `patrick-workflows:review-mine` in embedded mode: base = `base`, `--workspace "<WS>/review-mine"` (round 2: `"<WS>/review-mine-r2"`, so round-1 evidence is kept), `--criteria "<WS>/bar.md"`, `--scope "<WS>/scope.txt"`, `--baseline "<WS>/baseline.md"`, `--gates "<WS>/gates.txt"`, `--gate-timeout <gate_timeout>`, `--depth <depth>`, `--budget <budget_review_max>`, plus the `exit_pair` flags when set. The review covers the whole branch in both rounds, so every bar is judged on the whole feature. When the loop starts a fix round, `S phase fixing`; when it re-reviews, `S phase reviewing`.
3. Read `status` from that review workspace's `state.md`: `ready` → `S phase ready`; anything else → `S phase blocked`.

## 4. Hand over
Ledger: `build finished <phase>`. Invoke `patrick-workflows:ticket-ship`.
