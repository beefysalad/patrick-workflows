---
name: ticket-plan
description: PLAN stage of /ticket - read the ticket, settle acceptance criteria, create the branch, brainstorm the design, write the plan, and agree the autonomy brief with the user. The only interactive stage before BUILD; ends by starting BUILD.
---

# PLAN

Read `patrick-workflows:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`. Ask the user whatever you need in this stage; after the final approval nothing more is asked until SHIP.

## 1. Identify the ticket
- An ID (`ABC-123`, `#42`) or URL: that is the ID. Pasted text with no ID: ask the user for a short ID (suggest `T-<yyyymmdd>-<two words>`).
- `WS=$(bash "$SKILL_DIR/../ticket-workspace/scripts/ticket-ws.sh" path <id>)`. If it exists, resume at the first missing step below according to `phase`. Otherwise `bash ".../ticket-ws.sh" init <id>`, then `S set ticket <id>` and `S phase intake`.

## 2. Intake
Read the ticket with whatever the machine offers: `gh issue view <n> --json title,body,comments` for GitHub; a tracker MCP tool if one is available; otherwise ask the user to paste it. Save it verbatim to `WS/ticket.md`; `S set title "<title>"`.

## 3. Acceptance criteria
Extract them into `WS/bar.md` as `AC1`, `AC2`, ... followed by a `Deferred:` line. None in the ticket → write them with the user now. The run does not start without them.

## 4. Branch and checkout
1. Type: `fix` for bugs, else `feat` (ask if unclear). `BR=$(bash "$SKILL_DIR/../ticket-workspace/scripts/branch-name.sh" <type> <id> <title>)`; show it; the user may rename it.
2. Base: the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`, minus `origin/`; else local `main`). If a remote exists, `git fetch origin <base> -q`.
3. Ask: **main checkout** (recommended) or **a worktree**.
   - Main checkout: requires a clean tree; `git switch -c <BR> origin/<base>` (or `<base>` with no remote). `S set checkout main`.
   - Worktree (only because the user asked for one): call the `EnterWorktree` tool with `name` = the ticket ID. It creates the worktree under `.claude/worktrees/` and moves this session into it. Then `git branch -m <BR>` and, if it was not created from the base, `git reset --hard <base ref>` before any change. `S set checkout <worktree path>`. Do not use `git worktree add` outside the repo: the session cannot write there.
4. `S set branch <BR>`, `S set base $(git rev-parse HEAD)`, `S set base_branch <base>`, `S set pr_target <base>`.

## 5. Design
Invoke `superpowers:brainstorming` with these overrides from the user, which outrank the skill: save the design to `WS/design.md` (not `docs/`); do not commit it; when the user approves the design, do not invoke writing-plans, return here. Then `S phase designed`.

## 6. Plan
Dispatch `patrick-workflows:ticket-planner` (model opus) with `TICKET=WS/ticket.md`, `DESIGN=WS/design.md`, `BAR=WS/bar.md`, `RULINGS=WS/rulings.md` (create it empty if absent) and `OUT=WS/plan.md`. If the planner could not save the plan (permission refused), run `superpowers:writing-plans` here instead with the same overrides. Show the user the task list and risks; revise until they approve. `S set tasks_total <n>`, `S set tasks_done 0`, `S set round2 no`, `S phase planned`.

## 7. Autonomy brief
Settle each item, then show the whole brief once for approval.
1. **Gates:** detect as `review-mine` does (package.json scripts `test`/`lint`/`typecheck`; Makefile `test`/`lint`; pyproject pytest/ruff; Cargo; go.mod). `S set gate.<name> <command>`; `S set gate_timeout 900`.
2. **Scope:** start from the planner's `SCOPE-SUGGESTION`; ask for `forbid:` paths; write `WS/scope.txt`.
3. **Depth:** `lite` if the plan has at most 2 tasks and no path matches auth, security, crypto, payment, billing, session, token, password or permission; else `standard`. Show it as "review depth"; the user may raise it. `S set depth <depth>`.
4. **Budget:** `S set budget_impl_max` = 2 × tasks (lite) or 4 × tasks (standard); `S set budget_review_max` 3 (lite) or 10 (standard); `S set budget_impl_used 0`.
5. **Exit pair (optional):** if the user wants whole-feature proof, collect `--prove`, `--reset`, `--env-file`, `--db-pattern`; run `bash "$SKILL_DIR/../review-mine/scripts/exit-pair.sh" --check <flags>`. Refused → explain why, then drop it or let the user fix the env file. `S set exit_pair "<flags>"` or `S set exit_pair none`.
6. **Permissions:** print the allow rules this run needs, for the user to add to the project's `.claude/settings.local.json` (never edit settings yourself). Paths under the home directory are written with `~/`; any other absolute path needs a leading `//`.
   - `Read(~/.patrick-workflows/**)`, `Edit(~/.patrick-workflows/**)`
   - `Bash(bash *skills/*/scripts/*)`
   - each gate command, e.g. `Bash(npm test*)`
   - `Bash(git add*)`, `Bash(git commit*)`, `Bash(git diff*)`, `Bash(git log*)`, `Bash(git status*)`, `Bash(git switch*)`, `Bash(git rev-parse*)`
7. **Rulings:** record every decision made in this stage in `WS/rulings.md` with `source: user`.

Ask for one approval of the brief. On approval:
1. `bash "$SKILL_DIR/../review-mine/scripts/workspace.sh" --at "<WS>/review-mine"`, then run every gate once as `bash "$SKILL_DIR/../review-mine/scripts/run-gate.sh" preflight-<name> <timeout> -- "<command>"`. If a permission prompt appeared, ask the user to add the rule now and rerun the gate.
2. `S phase approved`, then invoke `patrick-workflows:ticket-build` immediately. Do not wait for another command.
