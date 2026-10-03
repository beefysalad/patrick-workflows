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
Tasks 0–8 are built and reviewed. Commits through `65076a1`; Task 9 is `abd9d6a`; a follow-up fix is `8efdb54`.

Open work, in order:
1. **Review `abd9d6a..8efdb54`** (the fix that deleted `commands/review-mine.md` and `commands/hello.md`). They had the same names as `skills/review-mine` and `skills/hello`, and Claude Code resolved the name to the 3-line command, so the skill's instructions never loaded. `/review-mine` still works as the skill's own slash command (verified). `validate.sh` now fails on "command shadows skill".
2. **Task 9 fix round:** in `README.md`'s UI grading paragraph, (a) state the pass rule: ours ≥ reference − 0.3, ours ≥ 3.5, no criterion below 3, confirmed by a second independent scorer; (b) correct "Playwright (light theme)": Playwright captures light and dark; only the Chrome fallback is light only. Then a scoped re-review.
3. **Graded smoke run:** `bash tests/fixture/ui-setup.sh <dir>`, then in that dir run `/review-mine main --graded graded.md --depth standard` (headless: see `tests/SMOKE-graded.md` for the allow rules). Tick its checklist from the workspace under `~/.patrick-workflows/tickets/<repo>/_reviews/`. Script defects are fixed test-first.
4. **Final whole-branch review** of `ec0da47..HEAD` on the most capable model (superpowers `requesting-code-review/code-reviewer.md`), one fix wave, one scoped re-review.
5. Tag `v0.4.0` and ask the user before pushing tags.

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
- ticket-close: `git branch -d` refuses after squash merges (reported, safe); old workspaces have no `type` key.
- README: rubric shown like an inline key; dev-command allow rule not mentioned.
- Fixture: `SMOKE-graded.md` must run from the repo root and fails if the folder exists.

## After A
Sub-projects B (guardrail hooks), C (full review depth + challenger) and D (parallel tasks) each need a plan from the completion spec, then subagent-driven development with TDD, a final review, and a release. Each starts with the spike listed in the spec.
