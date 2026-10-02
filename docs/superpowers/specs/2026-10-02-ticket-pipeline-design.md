# Ticket Pipeline: Architecture (v4)

Date: 2026-10-02
Status: Draft for review (v4: single `/ticket` command with stages; v3 incorporated two independent architecture reviews)
Plugin: `patrick-workflows` (this repo)

## 1. Purpose

A repeatable, mostly autonomous pipeline that takes one ticket from "read it" to "PR ready", with the `superpowers` plugin as the engine. Human input is front-loaded (brainstorm, plan, rules) and concentrated again at the end (one report, one PR decision). In between, the pipeline asks nothing.

**Design stance: a thin layer over superpowers.** Superpowers provides brainstorming, planning, and autonomous task execution (fresh implementer and reviewer per task, a ledger, rulings, stop conditions). This plugin adds what superpowers lacks: ticket intake, a pre-approved autonomy contract, baseline/permission/scope safety, a **gauntlet loop** for the final review, and a human handoff that ends in a PR.

### Success criteria
- After the plan and rules are approved, nothing is asked until the final report, except the four stop conditions (section 7).
- Every claim in the final report is backed by evidence on disk (gate logs, red-to-green output), not a subagent's say-so.
- A crash, `/clear`, or new session resumes mid-ticket from files alone.
- Cost is bounded per ticket by profile and budget (section 10).
- The repo stays public-safe, and no ticket content reaches the project's git history or PR except the code itself.

### Non-goals (Phase 1)
Integration/staging environments; multi-device or multi-model setups; parallel task execution; guardrail hooks; Obsidian or any knowledge base; the adversarial challenger and the `full` profile; batching several tickets per run. All Phase 2 (section 16).

## 2. Constraints
- All Claude, one machine, Claude Code only.
- Requires the `superpowers` plugin; commands fail fast with install instructions if it is missing.
- Ticket tracker unknown and machine-specific: work from an ID, URL, or pasted text.
- No tool attribution in commits or PR bodies (see `templates/CLAUDE.md`).
- Plugin components are markdown/JSON plus a few small bash helpers.

## 3. Approaches considered

| Approach | Verdict |
|---|---|
| A. One mega-orchestrator agent holding all subagent context | Rejected: context bloat; subagents cannot spawn subagents. |
| B. One `/ticket` command routing to stage skills, thin main-session orchestrator, external file workspace, task execution delegated to superpowers (chosen) | Resumable, cheap to build, inherits superpowers' improvements. |
| B0. Our own implementer/reviewer loop (v1 draft) | Rejected: duplicated superpowers' executor, ledger, rulings and stop rules. |
| C. External script driving headless `claude -p` | Deferred: more deterministic, but loses interactivity and subagent tooling. |

## 4. Component overview

### Command surface
One entry point. The workspace records the ticket's phase, so the user never chooses the next command:

```
/ticket <id | url | pasted text>
  PLAN   (interactive)  intake → acceptance criteria → branch/worktree → brainstorm → plan → rulings + autonomy brief
                        ◄ user approves → BUILD starts immediately, no new command
  BUILD  (autonomous)   pre-flight → tasks via superpowers executor → harvest → GAUNTLET LOOP → report
  SHIP   (interactive)  handoff report + §0 questions ◄ user answers → (round 2) → draft PR on authorization

/ticket <id>            run again at any time: resumes the current stage, shows the report, or —
  CLOSE  (autonomous)   once the PR is merged — sets the ticket to Done and cleans up

/review-mine [base]     the gauntlet loop on its own, for any branch
```

| Stage | Mode | Accepts phase | Sets phase |
|---|---|---|---|
| PLAN | interactive | (none), `intake`, `designed`, `planned` | `intake` → `designed` → `planned` → `approved` |
| BUILD | autonomous | `approved`, `round2` | `implementing` → `reviewing` ⇄ `fixing` → `ready`, or `blocked` |
| SHIP | interactive | `ready`, `blocked` | `handoff` → (`round2` → BUILD) → `pr` |
| CLOSE | autonomous | `pr` | `closed` (only if the PR is merged; otherwise reports status and changes nothing) |

### Commands (`commands/`)
| Command | Responsibility |
|---|---|
| `ticket` | Router: resolve the workspace, read the phase, run the matching stage skill. Refuses nothing; always does the next valid thing. |
| `review-mine` | Thin wrapper invoking the `review-mine` skill on the current branch. |

### Agents (`agents/`)
| Agent | Role | Model | Tools |
|---|---|---|---|
| `ticket-planner` | Runs `superpowers:writing-plans` on the approved design; saves into the workspace; never commits; never asks the execution-method question; returns plan path and summary. | Opus | Read, Write, Grep, Glob, Skill |
| `final-reviewer` | Gauntlet critic, parameterized by concern (`impact`, `security`, `regression`, `requirements`, `maintainability`, or `combined`) or by mode `re-review`. Read-only. | Sonnet (round 1); Opus (re-review, which is small) | Read, Grep, Glob (no Bash) |
| `ticket-fixer` | Gauntlet fix round in `standard`: takes the findings list, writes a RED test per behavioral finding, fixes, runs gates, commits. | Sonnet | Read, Write, Edit, Bash, Grep, Glob |

Implementers and per-task reviewers during task execution come from superpowers, not from this plugin.

### Skills (`skills/`)
| Skill | Purpose |
|---|---|
| `ticket-workspace` | Reference: workspace layout, state schema, phase table, ruling and finding formats. Every stage reads it. |
| `ticket-plan` | PLAN stage. |
| `ticket-build` | BUILD stage (sections 9–10). |
| `ticket-ship` | SHIP stage (section 12). |
| `ticket-close` | CLOSE stage (section 12a). |
| `review-mine` | The gauntlet loop (section 9.4): builds review packages, dispatches critics, applies the evidence rule, drives fix rounds and blind re-reviews, decides exit. Runnable standalone on any branch. |

### Helper scripts (`scripts/`)
| Script | Purpose |
|---|---|
| `run-gate.sh <name> <timeout> -- <cmd>` | Runs a gate with a hard timeout; writes the full log to the workspace; prints status plus the last ~30 lines. |
| `scope-check.sh` | Compares `git diff --name-only <base>..HEAD` with the allowed paths in `state.md`; non-zero on any file outside scope. Registered as a gate. |
| `review-package.sh <base> <head> <out>` | Writes a review package: diff, changed symbols, and the grep-derived callers/importers of those symbols. Used by the gauntlet for round 1 and re-reviews. |

## 5. Workspace (external to the repo)

Location: `~/.claude/tickets/<repo-slug>/<ticket-id>/`. Outside the repository, so it cannot be committed, needs no ignore rules, survives worktree removal, and is findable from any checkout. `<repo-slug>` comes from the remote URL (fallback: top-level folder name).

```
state.md          # machine-readable header (below)
ticket.md         # ticket verbatim; deleted at wrap on request
design.md, plan.md
rulings.md        # binding rulings, including those harvested from the executor ledger
ledger.md         # phase-level ledger
baseline.md       # gate results on the base commit
tasks.md          # per-task commit ranges + red-to-green evidence, harvested from the executor ledger
logs/             # full gate logs
review/round-N/   # package/, <concern>.md, findings.md, fix-report.md, re-review.md
handoff.md
```

State header:
```
ticket: ABC-123
phase: reviewing
round: 1                      # gauntlet round, 1-based
branch: feat/abc-123-add-export
base: 4f2c1ab
profile: standard
budget:
  impl_dispatches_max: 40     # 4 × task count (section 10)
  impl_dispatches_used: 17
  gauntlet_dispatches_max: 7  # reserved up front by profile
  gauntlet_dispatches_used: 3
  fix_rounds_max: 2           # set by profile
checkout: worktree ../repo-abc-123
gates: {test: "npm test", lint: "npm run lint", types: "npm run typecheck", scope: "scripts/scope-check.sh"}
scope: {allow: ["src/export/**", "tests/export/**"]}
executor_workspace: .superpowers/sdd/<plan>/
```

**Hand-off overrides (user instructions outrank skills):**
- *Brainstorming / writing-plans:* save design and plan to the workspace, do not commit, do not ask the execution-method question.
- *Executor (executing-plans or subagent-driven-development):* run the task loop only and **stop when no tasks remain**. Do not run the executor's own final review, fix pass, workspace deletion, or `finishing-a-development-branch`. BUILD owns everything after the last task.
- Immediately after the executor stops, BUILD **harvests** its ledger: task completion lines into `tasks.md`, `Ruling:` lines into `rulings.md`, `minor (deferred)` lines into the deferred list. Only then may the executor workspace be removed (at wrap).

## 6. Phase machine

```
intake → designed → planned → approved → implementing → reviewing ⇄ fixing → ready
            any stop condition, exhausted budget, or open Critical/Important at cap → blocked
ready | blocked → handoff → (round2 → implementing) → pr → closed (after merge)
```
- `reviewing` covers round-1 review and every re-review; `fixing` covers fix rounds. `round` in state says which.
- Phase changes are written with a ledger line.
- `ready` requires both: gates green against the baseline **and** no open Critical/Important findings. Anything else at the end is `blocked`, with a reason.
- **Round 2** (from handoff answers): the user's answers become rulings and new plan tasks; implementation resumes with a new impl allotment (4 × new tasks), and the gauntlet runs again with a fresh gauntlet reserve, scoped to the round-2 diff.
- Resume: re-running `/ticket <id>` reads state, both ledgers, and `git log`; those outrank conversation memory.
- Concurrency: one workspace per ticket ID; two tickets in one repo need separate checkouts.

## 7. Interaction contract

The user is consulted only at:
1. PLAN: clarifying questions, approach, design approval, plan approval, autonomy brief approval.
2. SHIP: one batched handoff, then PR authorization.

CLOSE asks nothing: running it is the request, and it only acts on a merged PR.

During BUILD it stops only for: (1) an irreversible or destructive operation; (2) a security-sensitive action; (3) an out-of-repo side effect normally asked about first (push, publish, send); (4) a plan so broken every path is a guess. Everything else is decided by the orchestrator (the main session), recorded as a ruling (what, why, cost if wrong), and reported in the handoff.

**Permissions are part of the contract.** The autonomy brief proposes a project allowlist: gate commands, `git add/commit/diff/log/status`, the helper scripts, and read/write access to the workspace path. The user approves it and adds it to their own settings; the pipeline never edits settings. Pre-flight runs every gate once and has a reviewer-equivalent read of the workspace; any prompt or failure blocks `approved`.

## 8. Rulings, findings, and the autonomy brief

**Ruling format** (`rulings.md`, binding on all agents):
```
R3 — <title> (source: user | orchestrator | executor)
Decision: ... / Why: ... / Cost if wrong: ... / Applies to: all | task N
```

**Finding format** (`review/round-N/findings.md`):
```
F1-2 — <title>                     # F<round>-<n>; carries forward unchanged across rounds
Severity: Critical | Important | Minor
Kind: behavioral | structural      # structural = no observable behavior (naming, duplication...)
Location: path/file.ts:42
Trigger: <input or condition>  Expected: ...  Actual: ...
Fingerprint: <file>:<symbol>:<trigger-hash>   # identity for dedupe and stall detection
```

**Autonomy brief** (PLAN must obtain, before approval):
- **Acceptance criteria.** None in the ticket → written with the user, or the run does not start. They become the **bar**: checks the critics grade against.
- Worktree or main checkout; branch `<type>/<ticket-id>-<slug>` (overridable).
- Gate commands with timeouts; **baseline** run on the base commit (red baseline blocks the start).
- **Scope**: allowed and forbidden paths, enforced by `scope-check.sh` after every task and fix round.
- Profile and budget; the permission allowlist; PR target branch and body conventions.

## 9. BUILD stage

1. **Pre-flight:** phase `approved` (or `round2`); workspace readable; superpowers present; baseline recorded; allowlist verified by a dry run of every gate; base SHA frozen.
2. **Tasks:** run the executor by profile (`lite` → `executing-plans`, `standard` → `subagent-driven-development`) under the hand-off override (section 5): TDD mandatory, gates via `run-gate.sh`, scope-check as a gate, stop when no tasks remain. The orchestrator tracks `impl_dispatches_used` from the executor ledger; at the cap it lets the current task's step finish, then stops the executor and goes to step 4 with phase `blocked` pending.
3. **Harvest** the executor ledger into `tasks.md`, `rulings.md`, and the deferred list.
4. **Gauntlet loop** (`review-mine`). Principles: the builder never grades its own work; critics are fresh and see none of the previous critics' reasoning; the bar is concrete; the loop ends when a blind re-review of the fixes finds nothing Critical/Important and gates are green, or when the budget ends.
   1. **Round-1 package:** `review-package.sh base..HEAD` plus rulings, plan, bar, and gate logs vs baseline.
   2. **Round-1 critics:** `final-reviewer` per concern (`lite`: 1 `combined`; `standard`: `impact`, `security+regression`, `requirements+maintainability`), Sonnet.
   3. **Evidence rule (reviewer side):** each finding states location, trigger, expected vs actual (finding format). Findings missing these are dropped. The orchestrator dedupes by fingerprint and ranks.
   4. **Severity re-grade:** the orchestrator may re-grade by effect on the person using the software; every re-grade is a ruling.
   5. **Fix round** (Critical and Important only; Minors deferred). Fixer: `ticket-fixer` (one dispatch with the full list) in `standard`; the orchestrator inline in `lite`.
      - *Behavioral findings:* the fixer writes a RED test first; **that test is the proof.** If no failing test can be produced, the finding is marked `unreproduced`, is not fixed, and goes to the handoff.
      - *Structural findings:* fixed directly; verified by the re-review only.
      - After fixes: all gates plus scope-check via `run-gate.sh`.
   6. **Blind re-review** (Opus, one dispatch): receives the fix diff, `review-package.sh` callers/importers of every symbol the fix touched, gate logs vs baseline, the bar, and the list of finding IDs and titles (not the earlier reasoning). It marks each ID `ADDRESSED` or `NOT ADDRESSED` and reports new findings, which go through the evidence rule with new IDs.
   7. **Exit / continue:**
      - All Critical/Important `ADDRESSED`, no new ones, gates green → exit clean.
      - Otherwise, if `round < fix_rounds_max` and gauntlet budget remains → next round (5–6) on the open IDs and new ones.
      - **Stall:** an ID marked `NOT ADDRESSED` in two consecutive re-reviews is not retried. The orchestrator decides: Critical → `blocked`; Important → a ruling deferring it plus a §0 question in the handoff.
      - Cap or budget reached with Critical/Important open → `blocked`.
      - Termination is guaranteed by `fix_rounds_max`; oscillation is bounded by it.
5. **Finish:** final gates against the baseline; phase `ready` only if section 6's two conditions hold, else `blocked`. No questions.

## 10. Profiles and cost control (Phase 1)

| | `lite` | `standard` (default) |
|---|---|---|
| Executor | `executing-plans` (inline) | `subagent-driven-development` |
| Impl budget | 2 × tasks | 4 × tasks |
| Gauntlet round 1 | 1 `combined` critic | 3 critics |
| Fixer | orchestrator inline | `ticket-fixer` |
| `fix_rounds_max` | 1 | 2 |
| Gauntlet reserve (dispatches) | 2 (1 critic + 1 re-review) | 7 (3 critics + 2 × (fixer + re-review)) |

- Selected automatically from plan and diff size and shown in the PLAN summary as "review depth"; the user only speaks up to make it heavier. Security-sensitive scope forces `standard`.
- **Model ruling:** round-1 critics run on Sonnet for cost; the re-review runs on Opus because it is small and decides exit. Planner on Opus. No Haiku in Phase 1 (cheap models often cost more turns).
- **Budget:** hard caps on dispatches, tracked in state; a malformed-output re-dispatch counts against the same cap. The gauntlet reserve is set aside before implementation starts, so implementation can never consume the review budget. It does not claim to measure tokens.
- **Context hygiene:** gate output goes to log files; critics receive packages, not the repo; subagents return short structured summaries.

## 11. Failure triage

| Class | Action |
|---|---|
| Product bug | Fix round (executor during tasks, gauntlet fixer after) |
| Test defect | Fix the test, not the product; ruling if semantics changed |
| Setup/environment | Fix environment or record as blocker; never touch product code |
| Pre-existing (red in `baseline.md`) | Do not fix; list in handoff |
| Hung/timeout | Recorded; one retry with a longer timeout only if a ruling allows |
| Unknown | One `superpowers:systematic-debugging` pass; if unresolved, stop condition 4 |

## 12. SHIP stage and the handoff

`handoff.md`, in order: what changed (files, commits, diff stat); gate evidence vs baseline; red-to-green proof per task (`tasks.md`); gauntlet summary per round (findings raised, dropped for missing evidence, fixed, `unreproduced`, stalled, deferred); rulings made autonomously with cost if wrong; **§0 questions**, each with a recommendation and terse answer format ("1 keep 2 change 3 yes"); base drift; draft PR title and body.

After answers: required changes become rulings and round 2 runs (section 6). On explicit authorization, in order: scan PR body and diff for secrets and company-specific strings and show the body; fetch base and, with approval, rebase; push; `gh pr create --draft`; No tool attribution anywhere. Cleanup is deferred to CLOSE.

## 12a. CLOSE stage

Run by `/ticket <id>` once phase is `pr`.
1. Check the PR state (`gh pr view`). Not merged → report its state (open, changes requested, closed unmerged) and change nothing.
2. Merged → update the ticket status to Done with whatever tracker tool the machine provides; if none, say so and give the one-line manual step.
3. Clean up: remove the worktree, delete the local branch if it is merged, remove the executor workspace.
4. Mark the workspace `closed`. It stays local in `~/.claude/tickets/` (Phase 2: notes are copied into the local knowledge vault here).

## 13. Ticket intake and tracker independence

PLAN takes an ID, URL, or pasted text; reads it with whatever tool the machine offers (tracker MCP, `gh issue view`, a CLI) or asks the user to paste. Saved verbatim in `ticket.md`; nothing downstream calls the tracker. Tracker connections and company conventions live in the work project's own `.claude/`, never in this repo.

## 14. Failure modes and recovery

| Event | Behavior |
|---|---|
| Crash, `/clear`, new session | Re-run `/ticket <id>`; resumes from state, ledgers, `review/round-N/`, `git log`. |
| `superpowers` missing | Stop at step 0 with install instructions. |
| Red baseline | Stop before any change; report failing gates on the base commit. |
| Permission prompt in pre-flight | Block `approved`; show missing allowlist entries. |
| Scope-check hit | Ruling or stop condition; never accepted silently. |
| Impl budget reached | Stop executor after the current step; run the gauntlet on what exists (reserve is intact); end `blocked` unless section 6's `ready` conditions hold. |
| Gauntlet budget reached | End per 9.4.7. |
| Subagent output malformed or evidence-free | One re-dispatch (counts against budget), then stop condition 4. |
| Executor ignores the stop-after-tasks override | Detected by its ledger showing final-review/finish steps; spike-blocking issue (section 17). |
| Tracker unreachable | Ask the user to paste. |
| Base branch moved | Reported in handoff; rebase only with approval, never mid-run. |

## 15. Verification of the pipeline itself
- Extend `scripts/validate.sh`: every referenced command/agent/skill/script exists; agents have `tools:` and `model:`; `final-reviewer` has no Bash; no file contains attribution strings.
- `tests/fixture/`: a tiny repo with a canned ticket and seeded defects (one behavioral, one structural, one pre-existing red), plus `tests/SMOKE.md`, a manual end-to-end checklist run before each release. Expected: behavioral defect fixed with a RED test, structural one fixed and `ADDRESSED`, pre-existing one reported and untouched.
- Evaluate `claude plugin eval` suites for `final-reviewer` once the CLI's behavior is confirmed.

## 16. Phasing
- **Phase 1 (this spec):** workspace + phase machine, `/ticket` router with PLAN/BUILD/SHIP/CLOSE stage skills, `/review-mine`, `ticket-planner`, `final-reviewer`, `ticket-fixer`, `review-mine` gauntlet, three helper scripts, `lite`/`standard`, handoff, fixture smoke test.
- **Phase 2:** guardrail hooks (block push/PR before handoff approval, no-attribution guard, block commits on the base branch); `full` profile with 5 concerns and a `finding-challenger`; parallel independent tasks; local knowledge notes (Obsidian), written at PLAN (design/plan) and updated at CLOSE (Done); a pluggable `prove` command for projects with an integration environment.

## 17. Assumptions to verify first (Spike 0)
1. A plugin agent with `Skill` in its tools can invoke `superpowers:writing-plans` and write to `~/.claude/tickets/...` (medium confidence).
2. Agent frontmatter `model:` pins the model (high).
3. Subagents cannot dispatch subagents, so the main session orchestrates (high).
4. Brainstorming/writing-plans honor the save-path, no-commit, and no-execution-question overrides (unverified).
5. **Both executors honor "stop when no tasks remain"**: no final review, no fix pass, no workspace deletion, no `finishing-a-development-branch` menu (unverified; spike-blocking).
6. Read-only agents can read `~/.claude/tickets/...` without a permission prompt once allowlisted (medium).
7. Plugin agents ignore `hooks`, `permissionMode`, and `mcpServers` frontmatter, so nothing relies on them (medium-high).
8. After `/clear`, re-running a command resumes correctly from files.

Fallbacks: if 1 fails, the planner runs in the main thread. If 4 fails, PLAN performs design/plan writing inline with explicit instructions. If 5 fails, BUILD drives tasks itself using the executor's per-task procedure, without invoking the skill's end-of-plan sections. If 6 fails, the package is copied into the repo's git-ignored `.superpowers/` area for the review.

## 18. Decisions recorded
1. Command surface: one `/ticket` command with PLAN/BUILD/SHIP/CLOSE stages, plus `/review-mine` (decided by Claude; user asked for a new design, not the old command set).
2. CLOSE = the old wrap step: Done status only when the PR is merged, plus cleanup. Knowledge-vault updates are Phase 2.
3. Review depth (profile) is chosen automatically; default `standard`.
4. Branch naming `<type>/<ticket-id>-<slug>` (user confirmed).
5. Workspace in `~/.claude/tickets/`, local only, never inside the project.
