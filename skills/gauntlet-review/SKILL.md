---
name: gauntlet-review
description: Use when reviewing a branch before a PR, or when /gauntlet-review runs. Runs a builder/critic loop - fresh critics by concern, evidence rule, fix rounds proven by red tests, fresh re-review, explicit PASS verdict, optional exit pair - without asking questions once started.
---

# Gauntlet Review

A builder/critic review loop on gauntlet principles: the builder never grades its own work, every critic is a fresh agent, critics grade against a written bar, and the loop runs until the bar is met, progress stalls, or the budget ends.

`SKILL_DIR` below means the base directory shown when this skill loaded. Run every script as `bash "$SKILL_DIR/scripts/<name>.sh"`. Agents are dispatched as `patrick-workflows:final-reviewer`, `patrick-workflows:ticket-fixer`, `patrick-workflows:finding-challenger` (depth full) and `patrick-workflows:ui-scorer` (`--graded`).

## Rules for the whole run
- After setup succeeds, ask the user nothing. Stop only for: an irreversible or destructive action, a security-sensitive action, an outside side effect (push, publish, send), or a situation where every path is a guess. Everything else is your decision, recorded as a ruling.
- Never push. Never edit settings. Never downgrade a Critical. Commit messages carry no trailers.
- Every claim in the report must point to a file in the workspace (a log, a finding, a fixer report).
- Append one line to `ledger.md` for every completed step: `<UTC time> <step> <result>`.
- Ledger lines use `date -u +%Y-%m-%dT%H:%M:%SZ` for the time; never type a time by hand.

## 1. Parse arguments
- `base`: first positional argument; default `git merge-base HEAD origin/<default>` where `<default>` comes from `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback: the local `main` branch, then local `master`, when there is no `origin`).
- `--depth`: `lite`, `standard` or `full`. `full` is used only when asked for (or set by `/start`'s brief). Default: `lite` if the diff has at most 3 files and 150 changed lines and no path contains auth, security, crypto, payment, billing, session, token, password or permission; otherwise `standard`.
- `--criteria <file>`: acceptance criteria. Without it, build the bar from the PR description (`gh pr view --json title,body` if it works) and the branch's commit messages, and mark it `inferred` in `bar.md`.
- `--scope <file>`: scope file for `scope-check.sh`. Optional.
- `--no-fix`: run round 1 only and report.
- `--prove/--reset/--env-file/--db-pattern/--allow-remote`: passed straight to `exit-pair.sh`.
- `--graded <graded.md>`: adds the graded (UI) bar (section 4b). Adds 5 to the review budget (3 for lite).

```
graded.md (one "key: value" per line):
dev: <dev command; the server gets PORT in its environment>
routes: <path to a routes file, one path per line>
reference: image-dir:<path> | route:<path on the same site> | url:<http(s) url>
rubric: <path to rubric.md; criterion names contain no ":">
margin: 0.3
floor: 3.5
min: 3
```
- Embedded mode (used by `/start`): `--workspace <dir>` uses that directory (`bash "$SKILL_DIR/scripts/workspace.sh" --at <dir>`) instead of creating one; `--baseline <file>` copies that file to `<WS>/baseline.md` and skips setup step 7; `--budget <n>` and `--rounds-max <n>` override the depth defaults; `--gates <file>` (lines `<name>: <command>`) and `--gate-timeout <seconds>` replace gate detection, so setup step 6 is skipped and the review loop runs exactly the gates the caller agreed, under the same names as its baseline. In embedded mode the caller has already checked the tree and branch, so setup steps 0–2 are skipped. If `<WS>/state.md` already exists with `status: running`, this is a rerun after a crash: keep its `budget_used`, `round` and findings and continue from them.

## 2. Setup (the only point where you may stop with a message to the user)
0. **Recover from an interrupted run first.** If `$(git rev-parse --git-path patrick-workflows-review-ws)` exists, read the workspace path in it. If that workspace's `state.md` says `status: running` and HEAD is detached, run `git checkout -- . && git clean -fd` (this only discards what a baseline gate wrote on the detached base commit) and then `git switch <restore_branch>`. Note the recovery in the new run's report.
1. Must be on a branch (`git symbolic-ref -q HEAD` succeeds); refuse a detached HEAD: "Check out the branch you want reviewed, then run /gauntlet-review again." Must be inside a git repository with a clean working tree (`git status --porcelain` empty). Otherwise stop: "Commit or stash your changes, then run /gauntlet-review again."
2. Unless `--no-fix`, refuse to run on the default branch: fixes are committed to the current branch.
3. If `superpowers:test-driven-development` is not an available skill, stop and tell the user to install the superpowers plugin.
4. Run `bash "$SKILL_DIR/scripts/workspace.sh"`; it prints the workspace path (call it `WS` below) and records it in the repo's git dir, so every other script finds it on its own. Never prefix commands with `REVIEW_WS=...`: allow rules match commands that start with `bash`, and a prefix makes every call prompt. Write workspace files with the Write/Edit tools at `WS/...`.
5. Write `state.md`:
```
branch: <current branch>
base: <base sha>
head_start: <HEAD sha>
depth: lite | standard | full
round: 0
rounds_max: 2 | 4 | 4
budget_max: 3 | 10 | 16
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
   - full: `impact` (**opus**), `security` (**opus**), `regression` (**sonnet**), `requirements` (**sonnet**, `VERDICT_REQUIRED: yes`), `maintainability` (**sonnet**).
   Dispatch text: `MODE: review`, `CONCERN`, `PACKAGE`, `BAR` (`bar.md`), `GATES` (`gates.md`), `VERDICT_REQUIRED`. Each dispatch adds 1 to `budget_used`.
3. Save each critic's output to `review/round-1/<concern>.md`. Output that does not follow the format gets one re-dispatch (counts against the budget, never against the protected slot); malformed again → stop condition "every path is a guess".
4. **Evidence filter:** drop any finding missing Location, Trigger, Expected or Actual. Count drops.
5. Assign IDs `F1-1, F1-2, ...`. Fingerprint = `<file>:<line rounded down to 10>:<first 8 chars of shasum of the trigger>`; duplicates keep the highest severity. Write `review/round-1/findings.md`.
5b. **Challenger** (full only, round 1 only): write `review/round-1/challenge-in.md` with every open Critical and Important finding raised by a critic (ID, severity, location, trigger, expected, actual) and dispatch `patrick-workflows:finding-challenger` (model **opus**, +1 budget) with `FINDINGS` (that file), `PACKAGE`, `BAR`. Save its output to `review/round-1/challenge.md`. Output that does not have exactly one `<ID>: STANDS` or `<ID>: REFUTED <path:line> — <reason>` line per finding gets one re-dispatch; malformed again → every finding stands, noted in the report. A REFUTED finding is closed: move it to `review/round-1/refuted.md` with the challenger's reason. It never reaches the fixer, and a later round that raises the same fingerprint again closes it as refuted too. A finding the challenger leaves STANDS keeps its severity. Scope-check findings (`forbidden` files) are never challenged: the user set that scope. With no critic finding at Critical or Important, skip the challenger (no dispatch).
6. **Severity changes:** you may raise any severity. You may never lower a Critical. Lowering an Important to Minor requires a ruling in `rulings.md` (`R<n> — <title> / Decision / Why / Cost if wrong`), and it is listed under "Severity downgrades" in the report.
7. Correctness verdict = the `requirements+maintainability` (`requirements` at full, `combined` at lite) critic's VERDICT. At full, step 5 writes each finding's critic and N-ID next to its F-ID in `findings.md` (e.g. `F1-4 (requirements N2)`). The requirements critic's FAIL counts as PASS, with a ruling in `rulings.md`, only when every Critical and Important finding that critic raised was refuted and its VERDICT-REASON names only those findings or the criteria they were about. Otherwise FAIL stands; if it stands while no Critical or Important finding is open, add a Critical finding `Verdict FAIL: <VERDICT-REASON>` (Location: the criterion in `bar.md`) so the fix round has something to act on.
7b. With `--graded`: run section 4b now, before step 8. Its gaps join the open findings.
8. If VERDICT is PASS, no Critical or Important finding is open, and the graded bar does not keep the loop going (see 4b, "Graded status") → go to section 5. If `--no-fix` → go to section 6.

## 4. Fix rounds (round N = 2, 3, ...)
0. At the start of each fix round, increment `round` in `state.md` (round 1 is the first review).
1. Stop if `round >= rounds_max`, or if only the protected slot remains in the budget and you still need a fixer (standard and full).
2. Record the pre-fix commit (`git rev-parse HEAD`) in `state.md` as `pre_fix`.
3. Open Critical and Important findings go to the fix round; Minors are deferred.
   - standard and full: dispatch `patrick-workflows:ticket-fixer` (model sonnet, +1 budget) with `FINDINGS` (the open findings file), `GATES` (one `bash "$SKILL_DIR/scripts/run-gate.sh" fix<N>-<name> 900 -- "<command>"` line per gate), `SCOPE` (if given), `REPORT` (`review/round-<N>/fix-report.md`).
   - Visual findings (Kind: visual, from 4b) go in the same `FINDINGS` file. When any is open, also pass `RECAPTURE` and `REFERENCE_IMAGES` (`<WS>/graded/reference`). `RECAPTURE` is these three lines with `<dev>` and `<routes>` from `graded.md` filled in and `<N>` set:
     ```
     bash "$SKILL_DIR/scripts/dev-server.sh" start "<dev>" 120
     bash "$SKILL_DIR/scripts/capture.sh" <url printed by the DEV-SERVER: up line> "<routes>" "<WS>/review/round-<N>/captures"
     bash "$SKILL_DIR/scripts/dev-server.sh" stop
     ```
   - lite: do the fix round yourself, under `superpowers:test-driven-development`, with the same rules and the same report format; fix visual findings exactly as `ticket-fixer`'s "Visual" section says, using the same `RECAPTURE` lines.
4. Re-run every gate yourself as `round<N>-<name>` (never trust the fixer's claim). A gate red on HEAD but not in the baseline becomes a new Critical finding with the log as evidence. If `--scope` was given, run `bash "$SKILL_DIR/scripts/scope-check.sh" <base> <scope>`: a `forbidden` file is a Critical finding ("revert this change"); `out-of-scope` files become rulings.
5. `UNREPRODUCED` findings leave the loop: listed in the report (security first), never counted as fixed or dismissed.
6. Fresh re-review: `bash "$SKILL_DIR/scripts/review-package.sh" <pre_fix sha> HEAD "<WS>/review/round-<N>/package"`, then write `<WS>/review/round-<N>/package/RANGE.txt` saying: this diff is only the fix round (`<pre_fix>..HEAD`), not the branch; `-` lines are removals, so a revert of an earlier change appears as that change with the signs flipped; the whole branch's file list is `base-files.txt` (write it with `git diff --name-only <base> HEAD`). Tell the critic to read `RANGE.txt` first. Then dispatch `patrick-workflows:final-reviewer` (model sonnet, +1 budget; use the protected slot if it is the last dispatch) with `MODE: re-review`, `PACKAGE`, `BAR`, `GATES`, `VERDICT_REQUIRED: yes`, and `FINDINGS` = only IDs and titles of what the fix round touched (no earlier reasoning).
7. **Evidence outranks opinion:** a behavioral finding whose red test now passes stays addressed unless the critic gave a NEW-TRIGGER; a NEW-TRIGGER becomes a new finding (round-N ID).
8. New findings go through the evidence filter and get IDs `F<N>-<n>`.
8b. With `--graded`: run section 4b for this round now, before steps 9 and 10. Its gaps join the open findings.
9. **Progress** (standard and full): progress = the count of open Critical + Important findings fell by at least 1, or (with `--graded`) ours overall rose by at least 0.2 (4b step 8); either one counts. Two consecutive rounds without progress → stop the loop (plateau).
10. Exit the loop when VERDICT is PASS, no Critical or Important is open, and the graded bar does not keep the loop going (see 4b, "Graded status"); otherwise next round. A graded bar that is `could-not-run` never keeps the loop going.

## 4b. Graded bar (only with `--graded`)
Runs at step 3.7b (round 1) and step 4.8b (each fix round). Once the graded bar is `could-not-run` for the run, skip this section for the rest of the run.

**Graded status** (record it in `state.md` as `graded_status: met | not-met | could-not-run <reason>`):
- `met`: both scorers pass. Does not keep the loop going.
- `not-met`: verdict exit 1. Keeps the loop going: its gaps become findings (step 7).
- `could-not-run` for the run (dev server, capture or reference failed): reported, never skipped silently, never retried, and never keeps the loop going. The outcome is BLOCKED (section 6).
- `could-not-run` for the round (malformed scorer output, step 6): no gaps. If the loop goes on for another reason (open findings, VERDICT not PASS) and a round remains, 4b runs again in that round. Otherwise it becomes `could-not-run` for the run.

**The reference is one page.** It is compared with the first route of the routes file only (the scorer compares the same file names, so both sides use the `home-*` names). Get it once per run, into `<WS>/graded/reference`:
- `route:<path>`: write `<WS>/graded/reference-routes.txt` holding one line, `/`. With the dev server up (step 2), run `bash "$SKILL_DIR/scripts/capture.sh" "<url><path>" "<WS>/graded/reference-routes.txt" "<WS>/graded/reference"`.
- `url:<u>`: the same, with `<u>` in place of `<url><path>` (no dev server needed for it).
- `image-dir:<dir>`: `bash "$SKILL_DIR/scripts/graded-ab.sh" images "<dir>" "<WS>/graded/reference"`. Exit 2 → `could-not-run` for the run (no images).

Steps:
1. `bash "$SKILL_DIR/scripts/dev-server.sh" start "<dev>" 120`. `could-not-run` → the graded bar is `could-not-run` for the run (reason: the DEV-SERVER line); run step 3, then end this section.
2. `bash "$SKILL_DIR/scripts/capture.sh" <url> <routes> "<WS>/graded/round-<N>/ours"` (`<url>` is exactly the URL printed on the `DEV-SERVER: up <url>` line of step 1), then get the reference as above if `<WS>/graded/reference` does not exist yet. capture.sh checks each URL's HTTP status first: a 404, 500 or any non-2xx page is `CAPTURE: could-not-run (HTTP <code> at <url>)`. Any capture that prints `CAPTURE: could-not-run` (exit 3) → the graded bar is `could-not-run` for the run (reason: that line); run step 3, then end this section (never run steps 4-7 on missing images).
3. Always `bash "$SKILL_DIR/scripts/dev-server.sh" stop` before going on, even after a failure. If either capture printed `(fallback: light only)`, note it on the Bars line and tell the scorer (step 5) to score dark-mode criteria only where both sets have dark images.
4. `bash "$SKILL_DIR/scripts/graded-ab.sh" first-route "<WS>/graded/round-<N>/ours" <routes> "<WS>/graded/round-<N>/ours-first"`, then `bash "$SKILL_DIR/scripts/graded-ab.sh" prepare "<WS>/graded/reference" "<WS>/graded/round-<N>/ours-first" "<WS>/blind/r<N>-<6 random letters>" "<WS>/graded/round-<N>/ab.mapping"` (the scorer's folders sit apart from the mapping and the source images).
5. Dispatch `patrick-workflows:ui-scorer` (model opus, +1 budget) with `DIR_A`, `DIR_B` (`<WS>/blind/r<N>-.../A` and `.../B`) and `RUBRIC`. Scorer dispatches never use the protected slot; if the budget runs out before the second scorer, the bar is `could-not-run` for the round. Save its output to `<WS>/graded/round-<N>/score-1.txt`.
6. `bash "$SKILL_DIR/scripts/graded-ab.sh" verdict "<WS>/graded/round-<N>/ab.mapping" "<WS>/graded/round-<N>/score-1.txt" --margin <m> --floor <f> --min <n>`. If it passes, dispatch a second, fresh `ui-scorer` (+1) into `<WS>/graded/round-<N>/score-2.txt` and run the verdict on both full paths; the bar is met only if both pass. Exit 2 (bad input: malformed scorer output) → re-dispatch that scorer once (counts against the budget); still exit 2 → `could-not-run` for the round. Only exit 1 (fail) produces gaps for the fix round: take the gaps from every scorer whose verdict failed. If any verdict prints `GRADED: tie on every criterion`, add a question to the report's "Needs your decision": "Round <N>: ours ties the reference on every criterion. Check that the fix did not copy the reference's markup, styles, text or images." with the recommendation to compare the diff with the reference.
7. Not met: read the mapping to know which side is ours, and turn each `GAP <ours> <criterion>` line into a finding:
   - Kind: visual. Severity: Important. Location: the first route and the viewport named in the gap.
   - Trigger and Actual: from the gap.
   - Expected: the rubric's quality for that criterion in your own words (e.g. "the call to action reads as the primary action at a glance on phone"). Never "match the reference" or "same as the reference".
   - End every visual finding with this sentence, verbatim: "The reference is a quality target, not content to copy: do not copy its markup, styles, text, images or brand. Keep this page's own content and purpose. Reusing the project's shared components and design tokens is fine."
   The fixer verifies visual fixes by recapturing (`RECAPTURE`, step 4.3), not with a red test.
8. Progress for the plateau rule (standard and full): ours overall (the average of the scorers' overall scores for ours in that round) rising by at least 0.2 counts as progress for step 4.9, alongside fewer open Critical + Important findings; there is no separate graded plateau. Report the best score when the loop stops.
9. The report's Bars section lists ours and reference per round, e.g. `Graded: 3.4 → 3.9 → 4.2 (reference 4.4, margin 0.3)`, or `Graded: could-not-run (<reason>)`.

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
   - **ready**: no new reds vs baseline, VERDICT PASS, no open Critical, exit pair met (if requested), and the graded bar is met (when `--graded` was given).
   - **blocked**: anything else. Open Importants at the cap are deferred with a ruling and listed as questions. A graded bar that is `could-not-run` gives `BLOCKED: graded bar could not run (<reason>)`.
3. Write `report.md`, in this order:
   1. Outcome line: `READY` or `BLOCKED: <reason>`, depth, rounds used, dispatches used / budget.
   2. Needs your decision: numbered questions, each with a recommendation (deferred Importants, out-of-scope rulings).
   3. Unreproduced findings, security first.
   3b. Refuted by the challenger (full only): each refuted finding with its severity, the challenger's `path:line` and reason, Criticals first, and "Reply to overrule" so the user can reopen it (standalone: a reopened finding is fixed by the user or by a new `/gauntlet-review` run whose `--criteria` names it; under `/start`, SHIP asks).
   4. Severity downgrades.
   5. Bars: correctness verdict per round; exit pair result and runs; with `--graded`, the graded line from 4b.9.
   6. Findings per round: raised, dropped for missing evidence, fixed (with red test names), deferred.
   7. Gates: baseline vs final, known reds called out.
   8. Commits made by fix rounds (`git log --oneline <head_start>..HEAD`).
   9. Rulings.
4. Set `status: ready | blocked` in `state.md`. Print the outcome line, the decision questions, and the path to `report.md`. Do not push.
