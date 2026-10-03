---
name: review-mine
description: Use when reviewing a branch before a PR, or when /review-mine runs. Runs a builder/critic loop - fresh critics by concern, evidence rule, fix rounds proven by red tests, fresh re-review, explicit PASS verdict, optional exit pair - without asking questions once started.
---

# Review Mine

A builder/critic review loop on gauntlet principles: the builder never grades its own work, every critic is a fresh agent, critics grade against a written bar, and the loop runs until the bar is met, progress stalls, or the budget ends.

`SKILL_DIR` below means the base directory shown when this skill loaded. Run every script as `bash "$SKILL_DIR/scripts/<name>.sh"`. Agents are dispatched as `patrick-workflows:final-reviewer` and `patrick-workflows:ticket-fixer`.

## Rules for the whole run
- After setup succeeds, ask the user nothing. Stop only for: an irreversible or destructive action, a security-sensitive action, an outside side effect (push, publish, send), or a situation where every path is a guess. Everything else is your decision, recorded as a ruling.
- Never push. Never edit settings. Never downgrade a Critical. Commit messages carry no trailers.
- Every claim in the report must point to a file in the workspace (a log, a finding, a fixer report).
- Append one line to `ledger.md` for every completed step: `<UTC time> <step> <result>`.

## 1. Parse arguments
- `base`: first positional argument; default `git merge-base HEAD origin/<default>` where `<default>` comes from `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback: the local `main` branch, then local `master`, when there is no `origin`).
- `--depth`: `lite` or `standard`. Default: `lite` if the diff has at most 3 files and 150 changed lines and no path contains auth, security, crypto, payment, billing, session, token, password or permission; otherwise `standard`.
- `--criteria <file>`: acceptance criteria. Without it, build the bar from the PR description (`gh pr view --json title,body` if it works) and the branch's commit messages, and mark it `inferred` in `bar.md`.
- `--scope <file>`: scope file for `scope-check.sh`. Optional.
- `--no-fix`: run round 1 only and report.
- `--prove/--reset/--env-file/--db-pattern/--allow-remote`: passed straight to `exit-pair.sh`.
- Embedded mode (used by `/ticket`): `--workspace <dir>` uses that directory (`bash "$SKILL_DIR/scripts/workspace.sh" --at <dir>`) instead of creating one; `--baseline <file>` copies that file to `<WS>/baseline.md` and skips setup step 7; `--budget <n>` and `--rounds-max <n>` override the depth defaults. In embedded mode the caller has already checked the tree and branch, so setup steps 0–2 are skipped.

## 2. Setup (the only point where you may stop with a message to the user)
0. **Recover from an interrupted run first.** If `$(git rev-parse --git-path patrick-workflows-review-ws)` exists, read the workspace path in it. If that workspace's `state.md` says `status: running` and HEAD is detached, run `git checkout -- . && git clean -fd` (this only discards what a baseline gate wrote on the detached base commit) and then `git switch <restore_branch>`. Note the recovery in the new run's report.
1. Must be on a branch (`git symbolic-ref -q HEAD` succeeds); refuse a detached HEAD: "Check out the branch you want reviewed, then run /review-mine again." Must be inside a git repository with a clean working tree (`git status --porcelain` empty). Otherwise stop: "Commit or stash your changes, then run /review-mine again."
2. Unless `--no-fix`, refuse to run on the default branch: fixes are committed to the current branch.
3. If `superpowers:test-driven-development` is not an available skill, stop and tell the user to install the superpowers plugin.
4. Run `bash "$SKILL_DIR/scripts/workspace.sh"`; it prints the workspace path (call it `WS` below) and records it in the repo's git dir, so every other script finds it on its own. Never prefix commands with `REVIEW_WS=...`: allow rules match commands that start with `bash`, and a prefix makes every call prompt. Write workspace files with the Write/Edit tools at `WS/...`.
5. Write `state.md`:
```
branch: <current branch>
base: <base sha>
head_start: <HEAD sha>
depth: lite | standard
round: 0
rounds_max: 2 | 4
budget_max: 3 | 10
budget_used: 0
protected_slot: unused
restore_branch: <current branch>
status: running
```
6. Detect gates: `package.json` scripts `test`, `lint`, `typecheck`/`type-check` (run with the repo's package manager); `Makefile` targets `test`, `lint`; `pyproject.toml` with pytest / ruff; `Cargo.toml` → `cargo test`, `cargo clippy`; `go.mod` → `go test ./...`, `go vet ./...`. Record them in `state.md` as `gate.<name>: <command>`. No gates found → record `gates: none` and say so in the report (correctness evidence is weaker).
7. Baseline: `git switch --detach <base>`, run each gate as `bash "$SKILL_DIR/scripts/run-gate.sh" baseline-<name> 900 -- "<command>"`, then `git checkout -- . && git clean -fd` (gates such as `lint --fix` may have written files on the base commit) and `git switch <branch>`. If anything fails in between, do that cleanup and switch back first. Write `baseline.md` with each gate's status, citing `logs/baseline-<name>.status`; failing gates are **known reds**.
8. Run each gate on HEAD as `head-<name>`. A gate that is `could-not-run` or `timeout` on HEAD stops the run with that reason in the report.
9. Write `bar.md`: the acceptance criteria (given or inferred), plus a `Deferred:` list, initially empty.

## 3. Round 1
1. `bash "$SKILL_DIR/scripts/review-package.sh" <base> HEAD "<WS>/review/round-1/package"`. Also write `review/round-1/gates.md`: each gate's HEAD status (from `logs/head-<name>.status`) compared with `baseline.md`.
   If `--scope` was given, run `bash "$SKILL_DIR/scripts/scope-check.sh" <base> <scope>` now: each `forbidden` file becomes a Critical finding ("revert this change") and each `out-of-scope` file a ruling, before any verdict can end the run.
2. Dispatch critics **in one message, in parallel**, as `patrick-workflows:final-reviewer` with these models:
   - lite: one `combined` critic, model **opus**, `VERDICT_REQUIRED: yes`.
   - standard: `impact` (**opus**), `security+regression` (**opus**), `requirements+maintainability` (**sonnet**, `VERDICT_REQUIRED: yes`).
   Dispatch text: `MODE: review`, `CONCERN`, `PACKAGE`, `BAR` (`bar.md`), `GATES` (`gates.md`), `VERDICT_REQUIRED`. Each dispatch adds 1 to `budget_used`.
3. Save each critic's output to `review/round-1/<concern>.md`. Output that does not follow the format gets one re-dispatch (counts against the budget, never against the protected slot); malformed again → stop condition "every path is a guess".
4. **Evidence filter:** drop any finding missing Location, Trigger, Expected or Actual. Count drops.
5. Assign IDs `F1-1, F1-2, ...`. Fingerprint = `<file>:<line rounded down to 10>:<first 8 chars of shasum of the trigger>`; duplicates keep the highest severity. Write `review/round-1/findings.md`.
6. **Severity changes:** you may raise any severity. You may never lower a Critical. Lowering an Important to Minor requires a ruling in `rulings.md` (`R<n> — <title> / Decision / Why / Cost if wrong`), and it is listed under "Severity downgrades" in the report.
7. Correctness verdict = the `requirements+maintainability` (or `combined`) critic's VERDICT.
8. If VERDICT is PASS and no Critical or Important finding is open → go to section 5. If `--no-fix` → go to section 6.

## 4. Fix rounds (round N = 2, 3, ...)
0. At the start of each fix round, increment `round` in `state.md` (round 1 is the first review).
1. Stop if `round >= rounds_max`, or if only the protected slot remains in the budget and you still need a fixer (standard).
2. Record the pre-fix commit (`git rev-parse HEAD`) in `state.md` as `pre_fix`.
3. Open Critical and Important findings go to the fix round; Minors are deferred.
   - standard: dispatch `patrick-workflows:ticket-fixer` (model sonnet, +1 budget) with `FINDINGS` (the open findings file), `GATES` (one `bash "$SKILL_DIR/scripts/run-gate.sh" fix<N>-<name> 900 -- "<command>"` line per gate), `SCOPE` (if given), `REPORT` (`review/round-<N>/fix-report.md`).
   - lite: do the fix round yourself, under `superpowers:test-driven-development`, with the same rules and the same report format.
4. Re-run every gate yourself as `round<N>-<name>` (never trust the fixer's claim). A gate red on HEAD but not in the baseline becomes a new Critical finding with the log as evidence. If `--scope` was given, run `bash "$SKILL_DIR/scripts/scope-check.sh" <base> <scope>`: a `forbidden` file is a Critical finding ("revert this change"); `out-of-scope` files become rulings.
5. `UNREPRODUCED` findings leave the loop: listed in the report (security first), never counted as fixed or dismissed.
6. Fresh re-review: `bash "$SKILL_DIR/scripts/review-package.sh" <pre_fix sha> HEAD "<WS>/review/round-<N>/package"`, then write `<WS>/review/round-<N>/package/RANGE.txt` saying: this diff is only the fix round (`<pre_fix>..HEAD`), not the branch; `-` lines are removals, so a revert of an earlier change appears as that change with the signs flipped; the whole branch's file list is `base-files.txt` (write it with `git diff --name-only <base> HEAD`). Tell the critic to read `RANGE.txt` first. Then dispatch `patrick-workflows:final-reviewer` (model sonnet, +1 budget; use the protected slot if it is the last dispatch) with `MODE: re-review`, `PACKAGE`, `BAR`, `GATES`, `VERDICT_REQUIRED: yes`, and `FINDINGS` = only IDs and titles of what the fix round touched (no earlier reasoning).
7. **Evidence outranks opinion:** a behavioral finding whose red test now passes stays addressed unless the critic gave a NEW-TRIGGER; a NEW-TRIGGER becomes a new finding (round-N ID).
8. New findings go through the evidence filter and get IDs `F<N>-<n>`.
9. **Progress** (standard only): progress = the count of open Critical + Important findings fell by at least 1. Two consecutive rounds without progress → stop the loop (plateau).
10. Exit the loop when VERDICT is PASS and no Critical or Important is open; otherwise next round.

## 5. Exit pair (only if `--prove` was given)
Run after the loop exits with PASS: `bash "$SKILL_DIR/scripts/exit-pair.sh" --label exit-pair-r<round> --prove ... [reset options]`.
The result line is also appended to `<WS>/exit-pair.txt`; cite it in the report.
- `pass` / `pass, flake seen` → bar met (note the flake).
- `fail` → a Critical finding citing the exit-pair logs; if rounds and budget remain, go back to section 4.
- `flaky` → bar unmet with reason `flaky`; name the failing tests; never run a fix round on product code for it.
- `refused` / `could-not-run` → bar not run; report the reason.

## 6. Finish
1. Run every gate one last time as `final-<name>`; compare with `baseline.md`.
2. Outcome:
   - **ready**: no new reds vs baseline, VERDICT PASS, no open Critical, exit pair met (if requested).
   - **blocked**: anything else. Open Importants at the cap are deferred with a ruling and listed as questions.
3. Write `report.md`, in this order:
   1. Outcome line: `READY` or `BLOCKED: <reason>`, depth, rounds used, dispatches used / budget.
   2. Needs your decision: numbered questions, each with a recommendation (deferred Importants, out-of-scope rulings).
   3. Unreproduced findings, security first.
   4. Severity downgrades.
   5. Bars: correctness verdict per round; exit pair result and runs.
   6. Findings per round: raised, dropped for missing evidence, fixed (with red test names), deferred.
   7. Gates: baseline vs final, known reds called out.
   8. Commits made by fix rounds (`git log --oneline <head_start>..HEAD`).
   9. Rulings.
4. Set `status: ready | blocked` in `state.md`. Print the outcome line, the decision questions, and the path to `report.md`. Do not push.
