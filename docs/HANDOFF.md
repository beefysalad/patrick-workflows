# Handoff: finishing the ticket pipeline

Written 2026-10-04 so another session (for example Claude Code on the web) can continue. Read this first, then the files it points to.

## Rules that always apply
- Use the superpowers skills: brainstorming for new design, writing-plans for plans, subagent-driven-development + test-driven-development to build, a fresh most-capable-model review at the end of each plan.
- No tool attribution in commits or PR text, ever (no co-author trailers, no "generated with" footers). `scripts/validate.sh` enforces it.
- Conventional Commit messages. Ask the user before pushing or tagging a release push.
- Bash must run on macOS bash 3.2 with BSD tools (the user's machines are Macs). On Linux, the scripts should run, but Chrome is not at the macOS path: set `CHROME_BIN` and expect Playwright to need `npx playwright install chromium` or `--channel chrome` with Chrome installed.
- Checks: `./scripts/validate.sh`, `bash tests/run.sh`, `claude plugin validate .`.

## Where things are
- Shipped: `/review-mine` (v0.2.0), `/ticket` PLAN/BUILD/SHIP + round 2 (v0.3.0).
- Design for what remains: `docs/superpowers/specs/2026-10-03-pipeline-completion-design.md` (sub-projects A–D; Obsidian and a separate integration-test step are dropped by the user).
- Current plan: `docs/superpowers/plans/2026-10-03-ui-grading-close.md` (sub-project A: UI grading, CLOSE, minors). Version in `plugin.json` is already 0.4.0; **no v0.4.0 tag yet**.

## Sub-project A status
Built, reviewed and fixed (commits `ec0da47..HEAD`). The graded smoke run passed end to end and found two script defects (fixed in `ebb0517`). The final whole-branch review (Opus) found 6 Important issues, fixed in `fc1117b..6d60418`:
- the fixer handles `Kind: visual` findings and is told not to copy the reference;
- `capture.sh` refuses error pages (non-2xx), and a `route:`/`url:` reference is one page compared with the first route;
- the graded bar runs before the loop exits, and a run-level `could-not-run` does not loop;
- CLOSE closes issues by the stored `issue_url` and uses `git branch -D` only when the local tip equals the PR's merged head.

Open work: rerun `tests/SMOKE-graded.md` after the fixes, then tag `v0.4.0` (ask the user before pushing tags).

## Decisions already made (rulings)
- Work happens on `main` (the user approved every phase there).
- `capture.sh` passes `--channel chrome` to Playwright by default (`CAPTURE_PW_CHANNEL` overrides; empty disables): the bundled Playwright browser build did not match the cache on the user's Mac; installed Chrome works.
- `graded.md` uses the key `min` (not `min_criterion` as the spec says), matching `graded-ab.sh --min`.
- Section 4b of `review-mine` mentions depth `full`, which sub-project C adds.
- The fixture `server.js` path-traversal issue is graded Minor (test-only, localhost).
- CLOSE permission rules (`git worktree`, `git branch`, `git pull`, `gh pr view`, `gh issue close`) were added to README and the PLAN brief.
- Re-graded to Important and fixed: graded-ab malformed scores (could false-pass), capture failure handling, verdict exit 2 handling, CLOSE ledger time format.

## Deferred minors (for the final review to triage)
- dev-server: `alive()` trusts `kill -0` (recycled PID); a signal between launch and PID write can orphan a server; servers that `setsid` escape the group kill; free-port race.
- capture: `CAPTURE_PW` word-splitting undocumented; a stale PNG in a reused folder could pass; route slug collisions (`/a/b` vs `/a-b`).
- graded-ab: option flags without a value exit 1 instead of 2; `rm -rf "$out"` trusts the caller; trailing whitespace/CRLF score lines rejected (fails closed).
- pr-state: unexpected-output and empty-argument paths untested.
- review-mine 4b: capture URL not tied to the `DEV-SERVER: up` line; retry/budget edge cases not spelled out.
- ticket-close: old workspaces have no `type` key.
- README: rubric shown like an inline key; dev-command allow rule not mentioned.
- Fixture: `SMOKE-graded.md` must run from the repo root and fails if the folder exists.

## Sub-project B status (2026-10-04)
Done and tagged `v0.5.0`: guard hook (attribution always; push approval and base-branch commits during a ticket). Final Opus review: 1 Important (false blocks from quoted text/heredocs), fixed test-first. Deferred minors: ticket lookup ignores `cd X`/`git -C X`; missed forms (`git --no-pager push`, `env X=1 git push`, quoted `-C` paths); a message that only mentions the trailer is blocked; `-F` scan also reads `grep -F` args; an extra perl call before the fast exit.

## Sub-project C status (2026-10-04)
Done and tagged `v0.6.0` (local until the user approves the push): `--depth full` (5 critics + `finding-challenger`, budget 16, 4 rounds); SHIP shows refuted findings with a reopen question. No end-to-end run of depth full yet (usage). Deferred minors: budget slack in the 16 math; "reply to overrule" undefined for standalone /review-mine.

## Sub-project D status (2026-10-04)
Done and tagged `v0.7.0` (local until the user approves the push): `waves.sh`, planner `Files:`/`Depends on:`, PLAN `parallel: on|off`, BUILD section 2b (agent worktrees reset to `START`, cherry-pick in plan order, resume). Final Opus review: 6 Important, all fixed. No end-to-end run of a parallel wave yet. Deferred minors: conflict re-run skips the budget check; waves.sh ignores Delete/Rename bullets, dirs and `./` paths; parallel gates on fixed ports may flake; `### Task` inside code fences is counted.

All four sub-projects (A-D) of the completion spec are done.

## After A
Sub-projects B (guardrail hooks), C (full review depth + challenger) and D (parallel tasks) each need a plan from the completion spec, then subagent-driven development with TDD, a final review, and a release. Each starts with the spike listed in the spec.
