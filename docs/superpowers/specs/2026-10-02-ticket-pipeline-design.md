# Ticket Pipeline: Architecture (v2)

Date: 2026-10-02
Status: Draft for review (v2: revised after an independent architecture review)
Plugin: `patrick-workflows` (this repo)

## 1. Purpose

A repeatable, mostly autonomous pipeline that takes one ticket from "read it" to "PR ready", with the `superpowers` plugin as the engine. Human input is front-loaded (brainstorm, plan, rules) and concentrated again at the end (one report, one PR decision). In between, the pipeline asks nothing.

**Design stance: this plugin is a thin layer over superpowers.** Superpowers already provides brainstorming, planning, autonomous task execution with a ledger, rulings, stop conditions, fresh implementer/reviewer subagents, and a whole-branch review. This plugin adds only what superpowers lacks: ticket intake, a pre-approved autonomy contract, baseline/permission/scope safety, a concern-specialized final review with an evidence rule, and a human handoff that ends in a PR.

### Success criteria
- After the plan and rules are approved, nothing is asked until the final report, except the four stop conditions (section 7).
- Every claim in the final report is backed by evidence on disk (gate logs, red-to-green output), not a subagent's say-so.
- A crash, `/clear`, or new session resumes mid-ticket from files alone.
- Cost is bounded and chosen per ticket (section 10).
- The repo stays public-safe, and no ticket content ever reaches the project's git history or PR except the code itself.

### Non-goals (Phase 1)
- Integration/staging environments, multi-device or multi-model setups.
- Parallel task execution, guardrail hooks, Obsidian or any knowledge base, the adversarial challenger agent, a `full` profile. All Phase 2 (section 16).
- Several tickets batched into one run.

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
| B. Three slash commands, thin main-session orchestrator, file-based workspace, delegating execution to superpowers (chosen) | Resumable, cheap to build, inherits superpowers' improvements. |
| C. External script driving headless `claude -p` | Deferred: more deterministic, but loses interactivity and subagent tooling. |
| B0. Build our own implementer/reviewer loop (the v1 draft) | Rejected after review: duplicated superpowers' executor, ledger, rulings and stop rules, and created a second workspace that would drift. |

## 4. Component overview

```
 /start-ticket (interactive)              /ship-ticket (autonomous)             /wrap-ticket (human gate)
 ├ intake + acceptance-criteria check     ├ pre-flight: baseline, perms           ├ handoff report
 ├ branch (+ worktree?)                   ├ lite     → superpowers:executing-plans├ you answer §0 questions
 ├ superpowers:brainstorming  [main]      │ standard → superpowers:subagent-      ├ round 2 if needed
 ├ ticket-planner [agent: writing-plans]  │             driven-development       ├ base-drift check
 └ rulings + autonomy brief ◄ approve     ├ review-mine (final, concern-split)    ├ draft PR on approval
                                          └ evidence filter → fix pass            └ cleanup
          ▲                                       ▲                                     ▲
          └──────── external workspace ~/.claude/tickets/<repo>/<id>/ (state, rulings, ledger, reports) ──┘
```

### Commands (`commands/`)
| Command | Mode | Accepts phase | Sets phase |
|---|---|---|---|
| `start-ticket` | interactive | (none), `intake`, `designed`, `planned` | `intake` → `designed` → `planned` → `approved` |
| `ship-ticket` | autonomous | `approved`, `round2` | `implementing` → `reviewing` → `fixing` → `ready`, or `blocked` |
| `wrap-ticket` | human gate | `ready`, `blocked` | `handoff` → (`round2` → back to ship) → `pr` → `wrapped` |

Each command checks the phase first and, if wrong, refuses and names the correct command.

### Agents (`agents/`)
| Agent | Role | Model | Tools |
|---|---|---|---|
| `ticket-planner` | Runs `superpowers:writing-plans` on the approved design, saves into the workspace, never commits, never asks the execution-approach question; returns the plan path and a short summary. | Opus | Read, Write, Grep, Glob, Skill |
| `final-reviewer` | One agent definition, parameterized by a concern (`impact`, `security`, `regression`, `requirements`, `maintainability`). Read-only, evidence-required findings. | Sonnet | Read, Grep, Glob (no Bash) |

Implementers and per-task reviewers are **not** defined here: `subagent-driven-development` supplies them.

### Skills (`skills/`)
| Skill | Purpose |
|---|---|
| `ticket-workspace` | Reference: workspace layout, state schema, phase table, ruling format. Every command reads it. |
| `review-mine` | The final-review procedure: pick concerns by profile, dispatch `final-reviewer` per concern, apply the evidence filter, consolidate, drive one fix pass. Also runnable standalone on any branch. |

### Helper scripts (`scripts/`)
| Script | Purpose |
|---|---|
| `run-gate.sh <name> <timeout> -- <cmd>` | Runs a gate with a hard timeout, writes the full log to the workspace, prints only status plus the last ~30 lines. Keeps test logs out of the orchestrator's context and prevents hung or watch-mode runs. |
| `scope-check.sh` | Compares `git diff --name-only <base>..HEAD` against the allowed paths in `state.md`; non-zero on any file outside scope. Registered as a gate. |

## 5. Workspace (external to the repo)

Location: `~/.claude/tickets/<repo-slug>/<ticket-id>/`. It is **outside the repository**, so it cannot be committed by `git add -A`, needs no ignore rules, survives worktree removal, and lets a new session in any checkout find the ticket. `<repo-slug>` comes from the remote URL (fallback: top-level folder name).

```
state.md        # machine-readable header: phase, branch, base SHA, profile, budget, gates, scope, checkout, sdd_workspace
ticket.md       # ticket verbatim; deleted at wrap on request
design.md       # approved design
plan.md         # approved plan
rulings.md      # numbered binding rulings
ledger.md       # phase-level ledger (one line per phase step)
baseline.md     # gate results on the base commit, before any change
logs/           # full gate logs (from run-gate.sh)
review/<concern>.md   # one per final reviewer
review/findings.md    # consolidated, evidenced, ranked
handoff.md
```

**Two ledgers, one rule:** `ledger.md` records *phase-level* progress (intake, approved, implementing, reviewing...). Task-level progress lives in superpowers' own ledger (`.superpowers/sdd/<plan>/progress.md`, git-ignored by its tooling). `state.md` stores the pointer (`sdd_workspace`) so neither is duplicated.

**Hand-off overrides.** Superpowers' brainstorming saves a spec to `docs/superpowers/specs/` and commits it, and writing-plans saves to `docs/superpowers/plans/` and ends by asking the user to choose an execution method. `start-ticket` explicitly overrides this (user instructions outrank skills): save to the workspace paths above, **do not commit**, and stop before the execution-method question, because the pipeline's own `ship-ticket` is the execution method. A spike confirms the overrides hold (section 17).

State header example:
```
ticket: ABC-123
phase: implementing
branch: feat/abc-123-add-export
base: 4f2c1ab
profile: standard
budget: {dispatches_max: 30, dispatches_used: 7, fix_passes_max: 2, fix_passes_used: 0}
checkout: worktree ../repo-abc-123
gates: {test: "npm test", lint: "npm run lint", types: "npm run typecheck", scope: "scripts/scope-check.sh"}
scope: {allow: ["src/export/**", "tests/export/**"]}
sdd_workspace: .superpowers/sdd/<plan>/
```

## 6. Phase machine

```
intake → designed → planned → approved → implementing → reviewing → fixing ⟲ → ready
   ↑ any stop condition / budget cap with red gates ─────────────→ blocked ─┤
                                                                            ▼
                                     handoff → (round2 → implementing) → pr → wrapped
```
- Phase changes are written to `state.md` together with a ledger line.
- `approved` is set only by `start-ticket` after the user approves plan + autonomy brief.
- `blocked` carries a reason; `wrap-ticket` accepts it and reports honestly instead of pretending success.
- Resume: a command re-run mid-ticket reads state, both ledgers, and `git log`; those outrank conversation memory.
- Concurrency: one workspace per ticket ID; two tickets in the same repo are separate workspaces and must use separate checkouts.

## 7. Interaction contract

The user is consulted at exactly these points:
1. `start-ticket`: clarifying questions, approach choice, design approval, plan approval, autonomy brief approval.
2. `wrap-ticket`: one batched handoff, then PR authorization.

During `ship-ticket` it stops only for: (1) an irreversible or destructive operation; (2) a security-sensitive action; (3) an out-of-repo side effect normally asked about first (push, publish, send); (4) a plan so broken every path is a guess. Everything else is decided, recorded as a ruling (what, why, cost if wrong), and shown in the handoff.

**Permissions are part of the contract.** Unallowlisted Bash calls from subagents would prompt and break autonomy. The autonomy brief therefore proposes a project allowlist (gate commands, `git add/commit/diff/log/status`, the helper scripts, workspace paths). The user approves it, the user (not the pipeline) adds it to their settings, and pre-flight verifies it by running every gate once; any prompt or failure there blocks `approved`.

## 8. Rulings and the autonomy brief

`rulings.md` is binding on all agents; every brief links it. Format:
```
R3 — <title> (source: user | decision)
Decision: ... / Why: ... / Cost if wrong: ... / Applies to: all | task N
```
Design-changing findings become new rulings and propagate to affected tasks.

`start-ticket` must obtain, before approval:
- **Acceptance criteria.** A ticket with none is turned into criteria with the user, or the run does not start.
- Worktree or main checkout; branch name `<type>/<ticket-id>-<slug>` (override allowed).
- Gate commands with timeouts, and the **baseline** (gates run on the base commit; a red baseline blocks the start and is reported).
- **Scope boundary** (paths allowed and forbidden), enforced by `scope-check.sh` after every task and fix, not by instruction alone.
- Definition of done as checks a reviewer can verify.
- Profile and budget.
- The permission allowlist proposal.
- PR target branch and body conventions.

## 9. `ship-ticket`

1. **Pre-flight:** phase `approved`; workspace readable; superpowers present; baseline recorded; allowlist verified by a dry run of every gate; base SHA frozen.
2. **Execute the plan** by profile, with the autonomy contract as the user's explicit instruction not to pause:
   - `lite` → `superpowers:executing-plans` (inline, no per-task reviewers).
   - `standard` → `superpowers:subagent-driven-development` (fresh implementer and reviewer per task).
   In both, all gates run through `run-gate.sh`, `scope-check.sh` is one of the gates, and TDD (red then green) is mandatory.
3. **Gauntlet loop (final review, performed by `review-mine` instead of a single reviewer; an override verified in the spike).** Principles borrowed from the gauntlet-loop pattern: the builder never grades its own work; critics are fresh and blind; the bar is concrete; the loop runs until a fresh critic finds nothing or the budget ends.
   1. **Bar:** the acceptance-criteria checks and rulings from the autonomy brief. Critics grade against the bar, not against taste.
   2. **Round 1 review:** `final-reviewer` per concern (`lite`: 1 combined; `standard`: 3 merged concern groups), each reading one review package (diff + rulings + plan + bar), not the repo.
   3. **Evidence filter:** every finding needs proof (failing test, command output, file:line plus a concrete trigger). Evidence-free findings are dropped; the rest are deduped and ranked into `review/findings.md`.
   4. **Fix round:** Critical and Important findings are each reproduced by a failing test first, then fixed, then all gates plus scope-check. Minors are listed as deferred.
   5. **Blind re-review:** a **new** `final-reviewer` dispatch, never the one that wrote the earlier findings, receives only the changed files, the bar, and the *list* of fixed findings (not the earlier reviewers' reasoning). It checks that each fix holds and that the fix introduced nothing new.
   6. **Exit when** a re-review finds no Critical or Important findings, **or** the fix-round cap is reached, **or** the stall rule fires: the same finding returning twice becomes a ruling or stop condition, never a third attempt. Hitting the cap with open Critical/Important findings sets `blocked`.
4. **Finish:** final gates compared against the baseline (only new failures count); phase `ready` if green and the loop exited clean, `blocked` otherwise. No questions.

## 10. Profiles and cost control (Phase 1)

| Profile | Executor | Gauntlet round 1 | Max fix rounds (each followed by a scoped blind re-review) |
|---|---|---|---|
| `lite` | `executing-plans` (inline) | 1 combined reviewer | 1 |
| `standard` (default) | `subagent-driven-development` | 3 reviewers | 2 |

- Auto-selected from plan and diff size; confirmed or overridden in the autonomy brief. Security-sensitive scope forces `standard`.
- Models: Opus for the planner; Sonnet for implementers and reviewers. Haiku is not used in Phase 1 (cheap models often cost more turns).
- **Budget** is hard caps on subagent dispatches and fix passes, plus any usage subagents report. It deliberately does not claim to measure tokens. At the cap the pipeline stops and reports.
- **Context hygiene:** gate output goes to log files via `run-gate.sh`; reviewers receive one review package, not the repo; subagents return short structured summaries.

## 11. Failure triage

Every gate failure is classified before anything changes:

| Class | Action |
|---|---|
| Product bug | Implementer fix round |
| Test defect | Fix the test, not the product; ruling if semantics changed |
| Setup/environment | Fix environment or record as blocker; never touch product code |
| Pre-existing (red in `baseline.md`) | Do not fix; list in handoff |
| Hung/timeout | Recorded; one retry with a longer timeout only if the ruling allows |
| Unknown | One `superpowers:systematic-debugging` pass; if unresolved, stop condition 4 |

## 12. `wrap-ticket` and the handoff

`handoff.md`, in order: what changed (files, commits, diff stat); gate evidence vs baseline; red-to-green proof per task; findings fixed, deferred, and dropped for lack of evidence; rulings made autonomously with cost if wrong; **§0 questions** each with a recommendation and terse answer format; **base drift** (has the base branch moved since `base`?); draft PR title and body.

After answers: required changes become rulings and a bounded round 2 runs. On explicit authorization, in this order: scan the PR body and diff for secrets and company-specific strings (and show the body); fetch base and, with approval, rebase; push the branch; `gh pr create --draft`; then cleanup (remove worktree). Ticket data (`ticket.md`) is deleted from the workspace on request. No tool attribution anywhere.

## 13. Ticket intake and tracker independence

`start-ticket` takes an ID, URL, or pasted text; it reads the ticket with whatever tool the machine offers (tracker MCP, `gh issue view`, a CLI) or asks the user to paste. The text is saved verbatim in `ticket.md`; nothing downstream calls the tracker. Tracker connections and company conventions live in the work project's own `.claude/`, never in this repo.

## 14. Failure modes and recovery

| Event | Behavior |
|---|---|
| Crash, `/clear`, new session | Re-run the command; resumes from state, ledgers, `git log`. |
| `superpowers` missing | Stop at step 0 with install instructions. |
| Red baseline | Stop before any change; report which gates fail on the base commit. |
| Permission prompt in pre-flight | Block `approved`; show the missing allowlist entries. |
| Scope-check hit | Ruling or stop condition; the change is not accepted silently. |
| Budget cap | Stop, set `blocked` (or `ready` if gates green), write handoff. |
| Subagent output malformed or evidence-free | Counts as not done; one re-dispatch, then stop condition 4. |
| Tracker unreachable | Ask the user to paste. |
| Base branch moved | Reported in handoff; rebase only with approval, never mid-run. |

## 15. Verification of the pipeline itself
- Extend `scripts/validate.sh`: every referenced command/agent/skill/script exists; agent `tools:` and `model:` present; final-reviewer has no Bash; no file contains attribution strings.
- `tests/fixture/`: a tiny repo with a canned ticket and a seeded defect, plus `tests/SMOKE.md`, a manual end-to-end checklist run before each release.
- Evaluate `claude plugin eval` suites for `final-reviewer` once the CLI's behavior is confirmed.

## 16. Phasing
- **Phase 1 (this spec):** workspace + phase machine, three commands, `ticket-planner`, `final-reviewer`, `review-mine`, `run-gate.sh`, `scope-check.sh`, `lite`/`standard` profiles, handoff, fixture smoke test.
- **Phase 2:** guardrail hooks (block push/PR before handoff approval, no-attribution guard, block commits on the base branch), `full` profile adding a `finding-challenger` (blind refutation of each finding) and 5 concerns, parallel independent tasks, local knowledge notes (Obsidian), a pluggable `prove` command for projects with an integration environment.

## 17. Assumptions to verify first (Spike 0)
1. A plugin agent with `Skill` in its tools can invoke `superpowers:writing-plans` and write to `~/.claude/tickets/...` (medium confidence).
2. Agent frontmatter `model:` pins the model (high).
3. Subagents cannot dispatch subagents, so the main session must orchestrate (high).
4. The brainstorming/writing-plans overrides (alternate save paths, no commit, no execution-method question) are honored (unverified).
5. `executing-plans`/`subagent-driven-development` accept `review-mine` replacing their final review (unverified).
6. Plugin agents ignore `hooks`, `permissionMode`, and `mcpServers` frontmatter, so no design element relies on them (medium-high).
7. After `/clear`, re-running a command resumes correctly from files.

If 1 fails, the planner runs in the main thread. If 4 or 5 fail, `start-ticket`/`ship-ticket` perform those steps inline with explicit instructions; the architecture holds.

## 18. Open questions for the user
1. `wrap-ticket` = handoff, answers, PR, cleanup. Confirm.
2. Default profile `standard`. Confirm.
3. Branch naming `<type>/<ticket-id>-<slug>`: confirm or give the convention.
4. Workspace outside the repo (`~/.claude/tickets/`): acceptable on the work laptop, or must everything stay under the repo?
