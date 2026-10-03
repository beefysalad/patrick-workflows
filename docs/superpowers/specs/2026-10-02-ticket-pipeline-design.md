# Ticket Pipeline: Architecture (v6)

Date: 2026-10-03
Status: Draft for review (v6: bars and grading — explicit PASS, graded rubric vs reference, exit pair; v5: own task driver, `/review-mine` first)
Plugin: `patrick-workflows` (this repo)

## 1. Purpose

A repeatable, mostly autonomous pipeline that takes one ticket from "read it" to "merged and closed". Human input is front-loaded (brainstorm, plan, rules) and concentrated again at the end (one report, one PR decision). In between, the pipeline asks nothing.

**Design stance.** Superpowers skills do the thinking work: brainstorming, planning (writing-plans), test-driven development, debugging, verification. This plugin owns the orchestration: ticket intake, the autonomy contract, its own task driver and ledger, baseline/permission/scope safety, a builder/critic review loop, and the human handoff. It does not steer superpowers' own executors, because depending on another plugin's ledger format and end-of-plan behavior would break silently on its updates.

**Naming.** The review loop is a builder/critic loop built on gauntlet principles: the builder never grades its own work, critics are fresh, the bar is concrete, and the loop runs until clean or out of budget. It does not stop until every **bar** the ticket declares is met (section 9.5) or the cap is reached. Graded bars use a blind A/B comparison against a reference, as in the original pattern.

### Success criteria
- After plan and rules are approved, nothing is asked until the report, except the four stop conditions (section 7).
- Every claim in the report is backed by evidence on disk (gate logs, red-to-green output).
- A crash, `/clear`, or new session resumes from files alone.
- Cost is bounded per ticket by review depth and budget (section 10).
- No ticket content reaches the project's git history or PR except the code itself. The repo stays public-safe.

### Non-goals (Phase 1)
Integration/staging environments; multi-device or multi-model setups; parallel tasks; guardrail hooks; Obsidian; a `full` depth with challenger; several tickets per run. See section 16.

## 2. Constraints
- All Claude, one machine, Claude Code only.
- Requires the `superpowers` plugin; fail fast with install instructions if missing.
- Ticket tracker unknown and machine-specific: work from an ID, URL, or pasted text.
- No tool attribution in commits or PR bodies.
- Plugin components are markdown/JSON plus small bash helpers.

## 3. Approaches considered

| Approach | Verdict |
|---|---|
| A. One mega-orchestrator agent holding all subagent context | Rejected: context bloat; subagents cannot spawn subagents. |
| B1. Delegate task execution to superpowers' executors and override their ending | Rejected (v5): requires parsing and steering another plugin's ledger and end-of-plan steps; fragile across its updates; needs a harvest step and two ledgers. |
| **B2. `/ticket` router + stage skills + own thin task driver + external workspace (chosen)** | One ledger we own; superpowers used for skills, not for control flow. |
| C. External script driving headless `claude -p` | Deferred. |

## 4. Components

### Command surface
```
/ticket <id | url | pasted text>
  PLAN   (interactive)  intake → acceptance criteria → branch/worktree → brainstorm → plan → autonomy brief
                        ◄ user approves → BUILD starts immediately
  BUILD  (autonomous)   pre-flight → task driver → review loop (review-mine) → ready | blocked
  SHIP   (interactive)  report + numbered questions ◄ user answers → (round 2) → draft PR on authorization
/ticket <id>            run again any time: resumes, shows the report, or —
  CLOSE  (autonomous)   once the PR is merged — sets the ticket to Done and cleans up
/review-mine [base]     the review loop on its own, on any branch
```

| Stage | Mode | Accepts phase | Sets phase |
|---|---|---|---|
| PLAN | interactive | (none), `intake`, `designed`, `planned` | `intake` → `designed` → `planned` → `approved` |
| BUILD | autonomous | `approved`, `round2` | `implementing` → `reviewing` ⇄ `fixing` → `ready` or `blocked` |
| SHIP | interactive | `ready`, `blocked` | `handoff` → (`round2` → BUILD) → `pr` |
| CLOSE | autonomous | `pr` | `closed` only if merged; otherwise reports PR state, changes nothing |

### Commands
| Command | Responsibility |
|---|---|
| `ticket` | Resolve the workspace, read the phase, run the matching stage skill. |
| `review-mine` | Run the `review-mine` skill on the current branch against a base (default: merge-base with the default branch). |

### Agents
| Agent | Role | Model | Tools |
|---|---|---|---|
| `ticket-planner` | Runs `superpowers:writing-plans` on the approved design; saves to the workspace; never commits; never asks the execution-method question. | Opus | Read, Write, Grep, Glob, Skill |
| `task-implementer` | One task from its brief: loads `superpowers:test-driven-development`; red test first, then green; runs gates via `run-gate.sh`; commits locally; writes its report. | Sonnet | Read, Write, Edit, Bash, Grep, Glob, Skill |
| `task-reviewer` | Fresh review of one task against its brief and the rulings (standard depth only). | Sonnet | Read, Grep, Glob |
| `final-reviewer` | Review-loop critic, parameterized by concern or `re-review` mode. | Per concern (section 10) | Read, Grep, Glob |
| `ticket-fixer` | Review-loop fix round: red test per behavioral finding, fix, gates, commit. | Sonnet | Read, Write, Edit, Bash, Grep, Glob, Skill |

### Skills
| Skill | Purpose |
|---|---|
| `ticket-workspace` | Reference: workspace layout, state schema, phase table, ruling/finding formats, ledger format. |
| `ticket-plan`, `ticket-build`, `ticket-ship`, `ticket-close` | One per stage. |
| `review-mine` | The review loop (section 9.3). Standalone or called by BUILD. |

### Scripts
| Script | Purpose |
|---|---|
| `run-gate.sh <name> <timeout> -- <cmd>` | Gate with hard timeout; full log to the workspace; prints status and the last ~30 lines; distinguishes `pass`, `fail`, `could-not-run`, `timeout`. |
| `scope-check.sh` | Classifies changed files (`git diff --name-only <base>..HEAD`) as in-scope, incidental, out-of-scope, or forbidden (section 8). Fails only on forbidden. |
| `review-package.sh <base> <head> <out>` | Diff, changed symbols, and grep-derived callers/importers: a starting point for critics. |
| `capture.sh <url> <out>` | Screenshots at desktop and phone widths for graded bars (headless browser). |
| `exit-pair.sh` | Runs `reset` then `prove`, twice; passes only if both runs pass. |

## 5. Workspace (local, outside the repo)

`~/.claude/tickets/<repo-slug>/<ticket-id>/` for tickets; `~/.claude/tickets/<repo-slug>/_reviews/<branch>-<timestamp>/` for standalone `/review-mine`. Outside the repo, so never committed, survives worktree removal, findable from any checkout.

```
state.md       # header below
ticket.md, design.md, plan.md
rulings.md     # binding rulings
ledger.md      # the only ledger: one line per completed step (task, gate run, review round)
baseline.md    # gate results on the base commit, including known reds
briefs/task-N.md, reports/task-N.md   # brief in; red-to-green evidence and gate summary out
logs/          # full gate logs
review/round-N/  # package/, <concern>.md, findings.md, fix-report.md, re-review.md
handoff.md
```

State header:
```
ticket: ABC-123
phase: reviewing
round: 1
branch: feat/abc-123-add-export
base: 4f2c1ab
depth: standard
budget: {impl_max: 20, impl_used: 17, review_max: 15, review_used: 3, rounds_max: 4}
checkout: worktree ../repo-abc-123
gates: {test: "npm test", lint: "npm run lint", types: "npm run typecheck"}
scope: {allow: ["src/export/**", "tests/export/**"], forbid: ["src/billing/**"]}
bars:
  correctness: true
  graded: {reference: reference/home.png, rubric: rubric.md, target: 4.0, min_criterion: 3}
  exit_pair: {prove: "npm run e2e", reset: "npm run db:reset"}
```

**Hand-off overrides for superpowers skills** (user instructions outrank skills): brainstorming and writing-plans save to the workspace, do not commit, and do not ask the execution-method question.

## 6. Phase machine
```
intake → designed → planned → approved → implementing → reviewing ⇄ fixing → ready
      budget exhausted, a stop condition, an open Critical, or an unmet bar at the cap/plateau → blocked
ready | blocked → handoff → (round2 → implementing) → pr → closed (after merge)
```
- **Green** means no gate result is worse than the baseline: no new failures, and every gate ran.
- **`ready`** requires green, no open Critical finding, **and every declared bar met** (section 9.5). Open Important findings at the cap do not block; they become SHIP questions.
- Round 2: answers become rulings and new plan tasks; new implementation allotment; the review loop runs again with a fresh review budget, scoped to the round-2 diff.
- Resume: re-running `/ticket <id>` reads state, ledger, `review/round-N/`, and `git log`.
- Concurrency: one workspace per ticket; two tickets in one repo need separate checkouts.

## 7. Interaction contract
User consulted only at PLAN (questions, approach, design, plan, autonomy brief) and SHIP (one batched report, then PR authorization). CLOSE asks nothing.

BUILD stops only for: (1) an irreversible or destructive operation; (2) a security-sensitive action; (3) an out-of-repo side effect normally asked about first (push, publish, send); (4) a plan so broken every path is a guess. Everything else is decided by the orchestrator, recorded as a ruling (what, why, cost if wrong), and reported.

**Permissions are part of the contract.** The brief proposes an allowlist (gate commands, `git add/commit/diff/log/status`, the scripts, workspace read/write). The user approves and adds it to their own settings; the pipeline never edits settings. Pre-flight dry-runs every gate; any permission prompt blocks `approved`.

## 8. Rulings, findings, autonomy brief, scope

**Ruling** (`rulings.md`): `R3 — <title> (source: user | orchestrator)` / Decision / Why / Cost if wrong / Applies to.

**Finding** (`review/round-N/findings.md`):
```
F1-2 — <title>
Severity: Critical | Important | Minor
Kind: behavioral | structural
Location: path/file.ts:42
Trigger: ...  Expected: ...  Actual: ...
Fingerprint: <file>:<symbol>:<trigger-hash>
```

**Autonomy brief**, obtained in PLAN:
- Acceptance criteria (written with the user if missing).
- **Bars** (section 9.5): correctness always; a graded bar with reference, rubric and target when the ticket has a visual or quality reference; an exit pair when the ticket needs whole-feature or end-to-end proof (with its `prove` and `reset` commands).
- Worktree or main checkout; branch `<type>/<ticket-id>-<slug>`.
- Gate commands with timeouts; baseline run on the base commit. Known reds are recorded; the start is blocked only if a gate **could not run** (missing command, timeout, environment error).
- Scope: `allow` and `forbid` paths, plus the built-in **incidental** list.
- Review depth and budget; the permission allowlist; PR target and body conventions.

**Scope classes** (`scope-check.sh`):
| Class | Examples | Effect |
|---|---|---|
| In scope | matches `allow` | none |
| Incidental (built-in) | lockfiles, package manifests, `index.*` barrel exports, generated types/clients, snapshot files, migrations folder when the plan mentions a migration | none; listed in report |
| Out of scope | anything else not forbidden | ruling recorded and shown in the report; build continues |
| Forbidden | matches `forbid` | gate failure → fix round must undo it; still present at cap → `blocked` |

## 9. BUILD stage

### 9.1 Pre-flight
Phase `approved` or `round2`; superpowers present; every gate run once on the base commit via `run-gate.sh` (baseline); allowlist confirmed by that run; base SHA frozen.

### 9.2 Task driver (own; replaces superpowers' executors)
For each plan task, sequentially:
1. Write `briefs/task-N.md`: task text, interfaces, relevant rulings, gates, scope.
2. **Standard:** dispatch `task-implementer`. **Lite:** the orchestrator implements inline under `superpowers:test-driven-development`.
3. The orchestrator re-runs gates and scope-check itself (never trusts a report's claim of green).
4. **Standard:** dispatch a fresh `task-reviewer`. Critical/Important → fix round by a new `task-implementer` dispatch, then a new `task-reviewer`. Max 2 fix rounds per task; then the open items carry into the review loop as findings.
5. Ledger line: task, commit range, gate results vs baseline, review result.
Gate failures are triaged first (section 11). Implementation budget exhausted → stop after the current step; run the review loop on what exists (its budget is reserved separately).

### 9.3 Review loop (`review-mine`)
1. **Package:** `review-package.sh base..HEAD`, plus rulings, plan, the bar, gate logs vs baseline. Critics are told the package is a **starting point, not the boundary**: grep-derived callers miss dependency injection, dynamic dispatch, string-keyed routes, and framework conventions (route files, ORM schemas, config-driven wiring); critics use Grep/Glob to look beyond it.
2. **Round-1 critics** by depth (section 10). Read-only; every finding is a hypothesis until reproduced.
3. **Evidence rule:** a finding must state location, trigger, expected vs actual; otherwise dropped. Dedupe by fingerprint; rank.
4. **Severity changes:** the orchestrator may raise any severity. It may **never downgrade a Critical**. Downgrading an Important to Minor is allowed only as a ruling, and every downgrade is listed in its own report section.
5. **Fix round** (Critical and Important; Minors deferred), by `ticket-fixer` (standard) or inline (lite):
   - Behavioral: red test first; **the red test is the proof.** Cannot be reproduced → `unreproduced`, not fixed, listed in its own report section (security first).
   - Structural: fixed directly; verified by re-review.
   - Then all gates and scope-check.
6. **Fresh re-review:** a new `final-reviewer` dispatch in `re-review` mode gets the fix diff, the callers package for touched symbols, gate logs vs baseline, the bar, and the finding IDs and titles (titles carry the earlier framing; the critic is fresh, not blind). It marks each ID `ADDRESSED` / `NOT ADDRESSED` and may report new findings, which go through the evidence rule.
7. **Evidence outranks opinion:** for a behavioral finding whose red test now passes, `NOT ADDRESSED` counts only if the critic supplies a **new trigger**; that becomes a new finding. Without a new trigger, the finding stays addressed.
8. **Exit:** every declared bar met (section 9.5) → clean. Otherwise, if `round < rounds_max`, review budget remains, and no plateau (9.5) → next round on open findings and unmet bars. At the cap or plateau: open **Critical** or an unmet bar → `blocked` with the best result reached; open **Important** only → ruling deferring it plus a SHIP question. Termination is guaranteed by the cap.

### 9.5 Bars and grading
A ticket declares one or more bars at PLAN. The loop runs until all are met, a plateau is detected, or the cap is hit.

| Bar | Applies to | Met when |
|---|---|---|
| **Correctness** (always) | every ticket | A fresh critic returns an explicit `PASS` verdict: every acceptance check is proven by evidence, no open Critical/Important finding, gates green vs baseline. Absence of findings alone is not a pass. |
| **Graded** | UI, landing pages, docs, anything with a reference | A fresh critic scores the work **≥ target overall (default 4.0/5) with no criterion below 3**. Target set at PLAN (e.g. 3.5). |
| **Exit pair** | whole-feature / end-to-end proof | The `prove` command passes **twice consecutively**, with `reset` run before each. One green run may be chance. |

**Graded bar mechanics**
- **Rubric** written at PLAN from the ticket: 3–6 criteria (e.g. layout fidelity, hierarchy, responsiveness, copy, accessibility), each with written anchors for scores 1, 3 and 5 so a score means the same thing every round.
- **Reference**: an image, URL capture, existing page, or design export, stored in the workspace.
- **Blind A/B**: the critic receives the reference and the current version labeled A and B in random order and scores both on the same rubric. It is not told which is ours. The report shows both scores.
- **Evidence for UI** (`capture.sh`): start the dev server from the brief's command and wait for its port; screenshot each route at desktop (1440×900) and phone (390×844), light and dark, via Playwright's CLI (`npx playwright screenshot --viewport-size=… --full-page --color-scheme=…`), which needs no Playwright setup in the project. A URL reference is captured the same way; an image or design export is used as-is. Optional **scripted states** per route (e.g. "open the mobile menu") run as a short Playwright script and are captured too. Critics read the PNGs (Claude reads images), not just code. Fallback: Chrome's own headless screenshot mode. If neither is available, the graded bar is reported as `could-not-run`, never silently skipped. Static screenshots judge appearance; whether interactions work is covered by the exit pair.
- **Fresh critic every round**, never shown earlier scores, so scores cannot creep upward by anchoring.
- Each criterion below 4 must come with a concrete, actionable gap; that list drives the next fix round.

**Plateau rule:** if the overall score (graded) or the open-finding count (correctness) does not improve for 2 consecutive rounds, stop early and report the best result; spending more rounds is unlikely to help.

**Report:** per bar, the result and history, e.g. "Graded: 3.4 → 3.9 → 4.2 / target 4.0 (reference 4.4). Exit pair: pass, pass."


### 9.4 Finish
Final gates vs baseline; `ready` if section 6's conditions hold, else `blocked`. No questions.

## 10. Review depth and cost

Chosen automatically from plan and diff size, shown in the PLAN summary; the user only speaks up to make it heavier. Security-sensitive scope forces standard.

| | `lite` | `standard` (default) |
|---|---|---|
| Task execution | orchestrator inline, TDD | `task-implementer` per task + fresh `task-reviewer` |
| Implementation budget | 2 × tasks | 4 × tasks |
| Round-1 critics | 1 `combined` on **Opus** | `impact` (**Opus**), `security+regression` (**Opus**), `requirements+maintainability` (Sonnet) |
| Fixer | inline | `ticket-fixer` (Sonnet) |
| Re-review | Sonnet | Sonnet |
| `rounds_max` | 2 | 4 |
| Review budget (reserved up front) | 4 | 12 (+3 per graded bar) |

- **Model ruling:** discovery is where missed bugs cost most, so the discovery critics for impact and security use Opus; checking a known fix is the easier job, so re-review uses Sonnet. Planner on Opus. No Haiku in Phase 1.
- Budgets are dispatch caps tracked in state; a re-dispatch for malformed output counts. Not a token meter.
- Context hygiene: gate output to files; critics get packages; subagents return short summaries.

## 11. Failure triage
| Class | Action |
|---|---|
| Product bug | Fix round |
| Test defect | Fix the test, not the product; ruling if semantics changed |
| Setup/environment | Fix environment or record as blocker; never touch product code |
| Known red (in `baseline.md`) | Not fixed; listed in report; does not count against green |
| Could not run / timeout | One retry with a longer timeout if a ruling allows; otherwise `blocked` |
| Unknown | One `superpowers:systematic-debugging` pass; unresolved → stop condition 4 |

## 12. SHIP stage and the report

`handoff.md`, in order:
1. **Needs your decision:** numbered questions with recommendations; answer tersely ("1 keep 2 change 3 yes").
2. **Unreproduced findings** (security first): not dismissed; each needs a decision.
3. **Severity downgrades** made by the orchestrator.
4. What changed: files, commits, diff stat, scope classes (incidental and out-of-scope files listed).
5. Evidence: gates vs baseline (known reds called out), red-to-green proof per task.
6. Bars: result and history per bar (scores per round, exit-pair runs).
7. Review loop summary per round: raised, dropped for missing evidence, fixed, deferred.
8. All other rulings with cost if wrong.
9. Base drift; draft PR title and body.

After answers: required changes → rulings → round 2. On explicit authorization: scan PR body and diff for secrets and company-specific strings and show the body; fetch base and, with approval, rebase; push; `gh pr create --draft`. No tool attribution. Cleanup waits for CLOSE.

## 12a. CLOSE stage
1. `gh pr view`: not merged → report state, change nothing.
2. Merged → set the ticket to Done with the machine's tracker tool; if none, give the one manual step.
3. Remove the worktree and the merged local branch.
4. Mark the workspace `closed`; it stays local (Phase 2: knowledge notes updated here).

## 13. Ticket intake
ID, URL, or pasted text, read with whatever tool the machine offers, or pasted. Saved verbatim; nothing downstream calls the tracker. Tracker connections and company conventions live in the work project's `.claude/`, never in this repo.

## 14. Failure modes and recovery
| Event | Behavior |
|---|---|
| Crash, `/clear`, new session | Re-run `/ticket <id>`; resumes from files and `git log`. |
| `superpowers` missing | Stop at step 0 with install instructions. |
| A gate cannot run on the base commit | Block the start; report which gate and why. |
| Known reds on the base commit | Recorded; build proceeds; reported. |
| Permission prompt in pre-flight | Block `approved`; show missing allowlist entries. |
| Forbidden path touched | Gate failure → fix round; at cap → `blocked`. |
| Out-of-scope path touched | Ruling; reported. |
| Implementation budget reached | Stop after current step; review loop runs on what exists. |
| Review budget reached | Exit per 9.3.8. |
| Malformed or evidence-free subagent output | One re-dispatch (counts), then stop condition 4. |
| Tracker unreachable | Ask the user to paste. |
| Base branch moved | Reported; rebase only with approval. |

## 15. Verification of the pipeline itself
- Extend `scripts/validate.sh`: referenced commands/agents/skills/scripts exist; agents declare `tools:` and `model:`; read-only agents have no Write/Edit/Bash; no attribution strings.
- `tests/fixture/`: a small repo with seeded cases and `tests/SMOKE.md`. Expected outcomes: a behavioral bug fixed with a red test; a structural issue fixed and `ADDRESSED`; a known baseline red reported and untouched while the run proceeds; a security-shaped finding with no reproducible test reported as `unreproduced`; a lockfile change classed incidental; a forbidden-path edit forced back out.
- Track per run: dispatches used, findings raised/kept/fixed, to judge whether the review loop earns its cost.

## 16. Phasing (build order)
- **Phase 1a — `/review-mine` standalone.** `final-reviewer`, `ticket-fixer`, `review-mine` skill, `run-gate.sh`, `scope-check.sh` (optional in standalone), `review-package.sh`, `exit-pair.sh`, standalone workspace, lite/standard depth flag, correctness bar with explicit PASS, exit pair (`--prove`/`--reset` flags), plateau rule, report. Useful on any branch immediately; exercises the hardest logic; measures cost vs value before anything else is built.
- **Phase 1b — `/ticket` PLAN + BUILD + SHIP, plus the graded bar** (rubric and reference capture at PLAN, `capture.sh`, blind A/B scoring). Workspace and phase machine, `ticket-planner`, task driver with `task-implementer`/`task-reviewer`, autonomy brief, BUILD calling `review-mine`, report and draft PR.
- **Phase 1c — CLOSE and round 2.**
- **Phase 2:** guardrail hooks (block push/PR before report approval, no-attribution guard, block commits on the base branch); `full` depth with 5 concerns and a challenger; parallel tasks; local Obsidian notes (written at PLAN, marked Done at CLOSE); a pluggable integration-test step.

## 17. Assumptions to verify (spike before each phase)
Before 1a:
1. Agent frontmatter `model:` pins the model per agent (high).
2. Read-only agents can read `~/.claude/tickets/...` without prompting once allowlisted (medium).
3. Plugin agents ignore `hooks`, `permissionMode`, `mcpServers` frontmatter; nothing depends on them (medium-high).
Before 1b:
- Critics (read-only agents) can view screenshot images via Read; a headless browser is available or installable in the project for `capture.sh` (medium).
4. A plugin agent with `Skill` can invoke `superpowers:writing-plans` / `test-driven-development` (medium).
5. Subagents cannot dispatch subagents, so the main session orchestrates (high).
6. Brainstorming/writing-plans honor the save-path, no-commit, no-execution-question overrides.
7. Re-running `/ticket` after `/clear` resumes correctly.

Fallbacks: 2 fails → packages copied into the repo's git-ignored `.superpowers/` area. 4 fails → planner runs in the main session; implementer follows TDD from its brief text. 6 fails → PLAN writes design and plan inline.

## 18. Decisions recorded
1. One `/ticket` command with PLAN/BUILD/SHIP/CLOSE stages, plus `/review-mine`.
2. CLOSE marks Done only when merged, then cleans up.
3. Review depth chosen automatically; default standard.
4. Branch naming `<type>/<ticket-id>-<slug>` (user confirmed).
5. Workspace in `~/.claude/tickets/`, local only.
6. Own task driver; superpowers for skills, not control flow (v5).
7. `/review-mine` built first (v5).
8. The loop stops only when every declared bar is met, on a plateau, or at the cap: explicit PASS for correctness; graded ≥ 4.0/5 with no criterion below 3 by default; exit pair = two consecutive passing runs (v6).
