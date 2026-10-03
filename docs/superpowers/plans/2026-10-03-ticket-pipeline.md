# `/ticket` Pipeline (Phase 1b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `/ticket <id>`: PLAN (interactive intake, brainstorm, plan, autonomy brief) → BUILD (autonomous task driver + the `/review-mine` loop) → SHIP (one report, numbered answers, optional round 2, draft PR), resumable from files at every phase.

**Architecture:** One `/ticket` command routes by the phase stored in the ticket workspace (`~/.patrick-workflows/tickets/<repo>/<id>/state.md`) to one stage skill: `ticket-plan`, `ticket-build`, `ticket-ship`. A reference skill, `ticket-workspace`, holds the formats and the deterministic bash helpers (phase machine, branch naming, workspace paths, secret scan). BUILD drives tasks itself with `task-implementer` / `task-reviewer` agents and then runs `review-mine` in embedded mode on a sub-workspace. Superpowers supplies brainstorming, writing-plans (via `ticket-planner`), and TDD.

**Tech Stack:** Bash (macOS bash 3.2 compatible), git, gh, Claude Code plugin markdown (commands, skills, agents), superpowers skills.

**Spec:** `docs/superpowers/specs/2026-10-02-ticket-pipeline-design.md` (v7): sections 4–9.3, 10–14, 17 items 5–8. Spike results from 1a: `docs/superpowers/spikes/2026-10-03-phase-1a.md`.

## Global Constraints

- Plugin `patrick-workflows`; public-safe; no employer content or secrets in the repo.
- No tool attribution in commits or PR bodies; `scripts/validate.sh` enforces it. Conventional Commit messages. Never push except in SHIP after explicit user authorization.
- Bash scripts: macOS bash 3.2 + BSD tools (no `mapfile`, no associative arrays, no `timeout`, `sed -E`, `sed -i.bak`); quote every expansion; paths with spaces must work; scripts invoked as `bash <path>`.
- Workspace root `${TICKETS_HOME:-$HOME/.patrick-workflows/tickets}`; never under `~/.claude/`. Ticket workspace: `<root>/<repo-slug>/<ticket-id>/`. The repo slug is identical from every worktree of the same repo.
- Commands must start with `bash`, `git`, `gh`, or the project's gate command, never with `VAR=value` prefixes (allow rules would not match).
- Agents are dispatched as `patrick-workflows:<name>`. Read-only agents (`final-reviewer`, `task-reviewer`) have only Read, Grep, Glob.
- Phases and transitions exactly as in spec section 6; only `state.sh phase` changes the phase.
- BUILD and the review loop ask the user nothing; PLAN and SHIP are the only interactive stages.
- Stage skills reference shared scripts as `$SKILL_DIR/../ticket-workspace/scripts/<name>.sh`, and review scripts as `$SKILL_DIR/../review-mine/scripts/<name>.sh`.
- The graded (UI) bar and CLOSE are out of scope for this plan (graded bar: next plan; CLOSE: Phase 1c).

## Review Focus

- **Illegal phase jumps** (e.g. `approved` → `pr`) must be refused by `state.sh`, or a resumed run could skip BUILD's checks. Pinned by tests in Task 2.
- **Resume in the wrong place:** a ticket started in a worktree and resumed from the main checkout must find the same workspace (repo slug from the git common dir). Pinned in Task 4.
- **Secrets in the PR:** the scanner must flag credentials in the PR body and diff without echoing them. Test fixtures build secret-shaped strings at runtime so this repo never contains one. Pinned in Task 5.
- **Branch names** from messy ticket titles (unicode, slashes, very long) must be valid git refs. Pinned in Task 3.
- **BUILD trusting the implementer's "green":** the orchestrator re-runs gates itself after every task (skill text, Task 9; exercised by the smoke run in Task 11).

## File Structure

| File | Responsibility |
|---|---|
| `skills/review-mine/scripts/review-package.sh` | (modify) unquoted file names |
| `skills/review-mine/scripts/exit-pair.sh` | (modify) `--label`, `--check` |
| `skills/review-mine/scripts/workspace.sh` | (modify) `--at <dir>` |
| `skills/review-mine/SKILL.md` | (modify) embedded-mode flags, round counter, fallback base |
| `skills/ticket-workspace/SKILL.md` | Reference: layout, state keys, phases, formats, script usage |
| `skills/ticket-workspace/scripts/state.sh` | Read/update `state.md`; validated phase transitions; ledger line per phase change |
| `skills/ticket-workspace/scripts/branch-name.sh` | `<type>/<id>-<slug>` from a ticket title |
| `skills/ticket-workspace/scripts/ticket-ws.sh` | Ticket workspace path / init / list |
| `skills/ticket-workspace/scripts/secret-scan.sh` | Flags secrets and deny-listed strings by rule name and line |
| `skills/ticket-plan/SKILL.md` | PLAN stage |
| `skills/ticket-build/SKILL.md` | BUILD stage |
| `skills/ticket-ship/SKILL.md` | SHIP stage, including round 2 |
| `commands/ticket.md` | `/ticket` router |
| `agents/ticket-planner.md` | Runs writing-plans into the workspace |
| `agents/task-implementer.md` | One task, TDD, gates, commit, report |
| `agents/task-reviewer.md` | Fresh read-only review of one task |
| `scripts/validate.sh` | (modify) read-only list, cross-skill script references |
| `tests/fixture/seed-ticket.sh` | Seeds an `approved` ticket on the fixture repo for headless BUILD/SHIP smoke |
| `tests/SMOKE-ticket.md` | Manual + headless smoke checklist |
| `tests/scripts/*.test.sh` | One test file per script |

---

### Task 0: Spike — Phase 1b assumptions

**Files:**
- Create: `docs/superpowers/spikes/2026-10-03-phase-1b.md`
- Create then delete: `agents/spike-probe.md`

**Interfaces:**
- Produces: facts Tasks 8–10 rely on: whether a subagent can dispatch subagents (S7), whether writing-plans honors save-path / no-commit / no-question overrides inside an agent (S8), and how a session works in a git worktree outside its starting directory (S9).

- [ ] **Step 1: Probe agent**

`agents/spike-probe.md`:
```markdown
---
name: spike-probe
description: Temporary spike agent for phase 1b checks.
tools: Read, Write, Grep, Glob, Skill, Bash
model: sonnet
---

Follow the dispatch instructions exactly and report each result on its own line, prefixed by the check name.
```

- [ ] **Step 2: S7 — nested dispatch**

Run from the repo root:
```bash
claude -p --model sonnet --plugin-dir "$PWD" "Dispatch patrick-workflows:spike-probe with: 'S7: try to dispatch another subagent of any type. Report S7: yes if it worked, S7: no plus the reason if you have no tool for it.' Print its output verbatim." < /dev/null
```
Expected: `S7: no` (no Agent tool inside subagents). Record the reason text.

- [ ] **Step 3: S8 — writing-plans overrides**

```bash
S8=$(mktemp -d) && printf '# Design\nAdd a function `double(n)` in `src/double.js` returning n*2, with a node:test test.\n' > "$S8/design.md"
claude -p --model sonnet --plugin-dir "$PWD" --allowedTools "Skill" "Read" "Edit($S8/**)" -- "Dispatch patrick-workflows:spike-probe with: 'S8: load the superpowers:writing-plans skill and write a plan for the design in $S8/design.md. Overrides from the user, which outrank the skill: save the plan to $S8/plan.md; do not commit anything; do not ask which execution approach to use; end by reporting S8: saved <path> and the number of tasks.' Print its output verbatim." < /dev/null
ls "$S8"; git -C "$PWD" status --short
```
Expected: `$S8/plan.md` exists; no new commit in this repo; output contains `S8: saved $S8/plan.md` and no execution-approach question. Any deviation is recorded; if overrides are ignored, Task 8's fallback (planner runs inline in the main session with the same overrides) becomes the primary path.

- [ ] **Step 4: S9 — worktree mechanics**

```bash
git worktree add -q "../patrick-workflows-s9" -b spike/s9
claude -p --model sonnet --plugin-dir "$PWD" --permission-mode acceptEdits -- "Create the file ../patrick-workflows-s9/S9.txt containing 'ok' using the Write tool, then run 'git -C ../patrick-workflows-s9 status --short' and report S9: <result>, and whether any permission was refused." < /dev/null
git worktree remove --force "../patrick-workflows-s9" && git branch -D spike/s9
```
Expected: record whether writing outside the starting directory was refused. Consequence: if refused, PLAN offers a worktree only together with the advice to start the next session inside the worktree (`cd ../<repo>-<id> && claude`), and defaults to the main checkout.

- [ ] **Step 5: Write the spike doc, remove the probe, commit**
```bash
rm -f agents/spike-probe.md
./scripts/validate.sh
git add docs/superpowers/spikes/2026-10-03-phase-1b.md
git commit -m "docs: record phase 1b spike results"
```
The doc has one section per check: command, trimmed output, conclusion, consequence.

---

### Task 1: `review-mine` follow-ups and embedded mode

**Files:**
- Modify: `skills/review-mine/scripts/review-package.sh`, `skills/review-mine/scripts/exit-pair.sh`, `skills/review-mine/scripts/workspace.sh`, `skills/review-mine/SKILL.md`
- Modify tests: `tests/scripts/review-package.test.sh`, `tests/scripts/exit-pair.test.sh`, `tests/scripts/workspace.test.sh`

**Interfaces:**
- Produces: `workspace.sh --at <dir>` (creates `<dir>/logs`, writes the pointer, prints `<dir>`); `exit-pair.sh --label <name>` (log names `<name>-<run>-reset|prove`, default `exit-pair`) and `--check` (runs only the reset-safety checks: exit 0 safe, 4 refused, prints `EXIT-PAIR: safe` or the refusal); `review-mine` flags `--workspace <dir>`, `--baseline <file>`, `--budget <n>`, `--rounds-max <n>`. Used by Task 9.

- [ ] **Step 1: Failing tests**

Append to `tests/scripts/review-package.test.sh` before `finish`:
```bash
cd "$tmp" || exit 1
printf 'x\n' > "src/café.js" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m unicode
bash "$RP" HEAD~1 HEAD "$tmp/uni"
assert_contains "$(cat "$tmp/uni/files.txt")" "src/café.js" "non-ASCII file names are not C-quoted"
```

Append to `tests/scripts/exit-pair.test.sh` before `finish`:
```bash
printf '0\n0\n' > "$tmp/seq"
out=$(bash "$EP" --label round3 --prove "bash '$tmp/next.sh' '$tmp/seq'"); assert_eq 0 $? "labelled run passes"
assert_file "$REVIEW_WS/logs/round3-1-prove.log" "label used in log names"
printf 'DATABASE_URL=postgres://prod.example.com/app_test\n' > "$tmp/.env.check"
out=$(bash "$EP" --check --prove "true" --reset "echo x >> '$tmp/check.marker'" --env-file "$tmp/.env.check" --db-pattern '_test$'); assert_eq 4 $? "--check refuses remote"
printf 'DATABASE_URL=file:./t_test.db\n' > "$tmp/.env.check"
out=$(bash "$EP" --check --prove "true" --reset "echo x >> '$tmp/check.marker'" --env-file "$tmp/.env.check" --db-pattern '_test\.db$'); assert_eq 0 $? "--check accepts safe target"
assert_contains "$out" "EXIT-PAIR: safe" "--check reports safe"
[ -f "$tmp/check.marker" ] && _ko "--check ran reset" || _ok
```

Append to `tests/scripts/workspace.test.sh` before the "outside a repo" block (still inside `$repo`):
```bash
at="$tmp/given ws"
out=$(bash "$WS" --at "$at"); assert_eq "$at" "$out" "--at prints the given dir"
[ -d "$at/logs" ] && _ok || _ko "--at creates logs"
assert_eq "$at" "$(cat "$(git rev-parse --git-path patrick-workflows-review-ws)")" "--at updates the pointer"
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/run.sh`
Expected: the new checks fail (C-quoted `"src/caf\303\251.js"`, unknown options `--label` / `--check` / `--at`).

- [ ] **Step 3: Implement**

`review-package.sh`: change `git diff --name-only "$base" "$head" > "$out/files.txt"` to
```bash
git -c core.quotePath=false diff --name-only "$base" "$head" > "$out/files.txt"
```

`exit-pair.sh`: add `label=exit-pair; check=no` to the defaults line, add to the option `case`:
```bash
    --label) label=${2:-}; shift 2 ;;
    --check) check=yes; shift ;;
```
After the reset-safety `if [ -n "$reset" ]; then ... fi` block, add:
```bash
if [ "$check" = yes ]; then echo "EXIT-PAIR: safe"; exit 0; fi
```
In `run_once`, replace both `"exit-pair-$1-reset"` and `"exit-pair-$1-prove"` with `"$label-$1-reset"` and `"$label-$1-prove"`, and in `report()` replace `logs/exit-pair-*` with `logs/$label-*`.

`workspace.sh`: insert after `set -u`:
```bash
if [ "${1:-}" = "--at" ]; then
  dir=${2:?usage: workspace.sh --at <dir>}
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 1; }
  mkdir -p "$dir/logs" || exit 1
  printf '%s\n' "$dir" > "$(git rev-parse --git-path patrick-workflows-review-ws)"
  printf '%s\n' "$dir"
  exit 0
fi
```

`skills/review-mine/SKILL.md`:
- In section 1, replace the `base` bullet's fallback text with: "(fallback: the local `main` branch, then local `master`, when there is no `origin`)".
- Add to section 1:
```markdown
- Embedded mode (used by `/ticket`): `--workspace <dir>` uses that directory (`bash "$SKILL_DIR/scripts/workspace.sh" --at <dir>`) instead of creating one; `--baseline <file>` copies that file to `<WS>/baseline.md` and skips setup step 7; `--budget <n>` and `--rounds-max <n>` override the depth defaults. In embedded mode the caller has already checked the tree and branch, so setup steps 0–2 are skipped.
```
- In section 4, insert as step 0: "At the start of each fix round, increment `round` in `state.md` (round 1 is the first review)."
- In section 5, pass `--label exit-pair-r<round>` to `exit-pair.sh`.

- [ ] **Step 4: Run to verify they pass**

Run: `bash tests/run.sh && ./scripts/validate.sh`
Expected: every test file `0 failed`; `OK: repo is valid`.

- [ ] **Step 5: Commit**
```bash
git add skills/review-mine tests/scripts
git commit -m "feat: add embedded mode to review-mine and close 1a follow-ups"
```

---

### Task 2: `state.sh` — state and phase machine

**Files:**
- Create: `tests/scripts/state.test.sh`, `skills/ticket-workspace/scripts/state.sh`

**Interfaces:**
- Produces: `bash state.sh <state-file> get <key>` (prints value; exit 1 if absent), `set <key> <value>` (creates file/key as needed), `incr <key> [n]` (numeric; prints new value), `phase <new>` (validates transition, writes `phase`, appends `<UTC> phase <old> -> <new>` to `ledger.md` beside the state file; exit 2 on an illegal transition). Keys match `^[a-z0-9_.-]+$`. Used by Tasks 8–10.

- [ ] **Step 1: Failing test**

`tests/scripts/state.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
ST="$ROOT/skills/ticket-workspace/scripts/state.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
f="$tmp/ticket ws/state.md"; mkdir -p "$tmp/ticket ws"

bash "$ST" "$f" set ticket ABC-123; assert_eq "ABC-123" "$(bash "$ST" "$f" get ticket)" "set then get"
bash "$ST" "$f" set branch "feat/abc-123-x y"; assert_eq "feat/abc-123-x y" "$(bash "$ST" "$f" get branch)" "value with spaces and slash"
bash "$ST" "$f" set ticket ABC-124; assert_eq "ABC-124" "$(bash "$ST" "$f" get ticket)" "overwrite keeps one line"
assert_eq 1 "$(grep -c '^ticket: ' "$f")" "no duplicate keys"
bash "$ST" "$f" get missing >/dev/null; assert_eq 1 $? "missing key exits 1"
bash "$ST" "$f" set "bad key" x 2>/dev/null; assert_eq 2 $? "invalid key name rejected"

assert_eq 1 "$(bash "$ST" "$f" incr budget_impl_used)" "incr from absent starts at 1"
assert_eq 4 "$(bash "$ST" "$f" incr budget_impl_used 3)" "incr by n"

bash "$ST" "$f" phase intake; assert_eq 0 $? "none -> intake"
for p in designed planned approved implementing reviewing fixing reviewing ready handoff round2 implementing reviewing blocked handoff pr; do
  bash "$ST" "$f" phase "$p" || _ko "legal transition to $p refused"
done
assert_eq pr "$(bash "$ST" "$f" get phase)" "phase walked to pr"
out=$(bash "$ST" "$f" phase implementing 2>&1); assert_eq 2 $? "pr -> implementing refused"
assert_contains "$out" "illegal transition: pr -> implementing" "refusal names both phases"
assert_eq pr "$(bash "$ST" "$f" get phase)" "refused transition leaves phase unchanged"
bash "$ST" "$f" phase pr; assert_eq 0 $? "same phase is a no-op"
assert_contains "$(cat "$tmp/ticket ws/ledger.md")" "phase handoff -> pr" "ledger records transitions"

g="$tmp/other.md"; bash "$ST" "$g" phase approved 2>/dev/null; assert_eq 2 $? "none -> approved refused"

finish
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh`
Expected: `state.test.sh` failures (script missing).

- [ ] **Step 3: Implement**

`skills/ticket-workspace/scripts/state.sh`:
```bash
#!/usr/bin/env bash
# Read and update a ticket's state.md ("key: value" lines) and enforce the phase machine.
# Usage: state.sh <state-file> get <key>
#        state.sh <state-file> set <key> <value>
#        state.sh <state-file> incr <key> [n]
#        state.sh <state-file> phase <new-phase>
# Exit: 0 ok, 1 key absent (get), 2 bad input or illegal phase transition.
set -u
f=${1:-}; cmd=${2:-}; key=${3:-}
[ -n "$f" ] && [ -n "$cmd" ] || { echo "usage: state.sh <file> get|set|incr|phase ..." >&2; exit 2; }

# Legal phase transitions (spec section 6). "none" is a ticket with no phase yet.
ALLOWED=" none>intake intake>designed designed>planned planned>approved approved>implementing
 implementing>reviewing implementing>blocked reviewing>fixing fixing>reviewing reviewing>ready
 reviewing>blocked fixing>blocked ready>handoff blocked>handoff handoff>round2 round2>implementing
 handoff>pr pr>closed "

valid_key() { printf '%s' "$1" | grep -Eq '^[a-z0-9_.-]+$'; }
get() { [ -f "$f" ] || return 1; v=$(sed -n "s/^$1: //p" "$f" | head -n 1); grep -q "^$1: " "$f" || return 1; printf '%s\n' "$v"; }
put() {
  mkdir -p "$(dirname "$f")" || exit 2
  if [ -f "$f" ] && grep -q "^$1: " "$f"; then
    tmpf="$f.tmp.$$"
    awk -v k="$1: " -v v="$2" 'index($0, k) == 1 { print k v; next } { print }' "$f" > "$tmpf" && mv "$tmpf" "$f"
  else
    printf '%s: %s\n' "$1" "$2" >> "$f"
  fi
}

case $cmd in
  get)
    valid_key "$key" || { echo "invalid key: $key" >&2; exit 2; }
    get "$key" || exit 1 ;;
  set)
    valid_key "$key" || { echo "invalid key: $key" >&2; exit 2; }
    put "$key" "${4-}" ;;
  incr)
    valid_key "$key" || { echo "invalid key: $key" >&2; exit 2; }
    n=${4:-1}; cur=$(get "$key" 2>/dev/null || echo 0)
    case "$cur$n" in *[!0-9]*) echo "not a number: $key=$cur" >&2; exit 2 ;; esac
    new=$((cur + n)); put "$key" "$new"; echo "$new" ;;
  phase)
    [ -n "$key" ] || { echo "usage: state.sh <file> phase <new>" >&2; exit 2; }
    cur=$(get phase 2>/dev/null || echo none); [ -n "$cur" ] || cur=none
    [ "$cur" = "$key" ] && exit 0
    allowed=$(printf '%s' "$ALLOWED" | tr '\n' ' ')
    case "$allowed" in
      *" $cur>$key "*) ;;
      *) echo "illegal transition: $cur -> $key" >&2; exit 2 ;;
    esac
    put phase "$key"
    printf '%s phase %s -> %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cur" "$key" >> "$(dirname "$f")/ledger.md" ;;
  *)
    echo "unknown command: $cmd" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run.sh`
Expected: `state.test.sh` `0 failed`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/state.test.sh skills/ticket-workspace/scripts/state.sh
git commit -m "feat: add ticket state script with validated phase transitions"
```

---

### Task 3: `branch-name.sh`

**Files:**
- Create: `tests/scripts/branch-name.test.sh`, `skills/ticket-workspace/scripts/branch-name.sh`

**Interfaces:**
- Produces: `bash branch-name.sh <type> <ticket-id> <title words...>` → prints `<type>/<id>-<slug>` (lowercase, `[a-z0-9-]`, at most 60 chars, no trailing `-`, valid per `git check-ref-format --branch`); type ∈ feat fix chore docs refactor test perf (exit 2 otherwise). Used by Task 8.

- [ ] **Step 1: Failing test**

`tests/scripts/branch-name.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
BN="$ROOT/skills/ticket-workspace/scripts/branch-name.sh"

assert_eq "feat/abc-123-add-csv-export" "$(bash "$BN" feat ABC-123 "Add CSV export")" "basic"
assert_eq "fix/abc-9-orders-page-crashes-on-empty-list" "$(bash "$BN" fix abc-9 "Orders page: crashes on empty list!!")" "punctuation collapsed"
assert_eq "feat/42-caf-menu-a-b" "$(bash "$BN" feat "#42" "Café menu / a\\b")" "unicode, slash and backslash removed"
assert_eq "chore/x-1" "$(bash "$BN" chore X-1)" "no title"
long=$(bash "$BN" feat ABC-1 "a very long title that keeps going and going well past the sixty character limit for names")
[ ${#long} -le 60 ] && _ok || _ko "length capped: ${#long}"
case "$long" in *-) _ko "trailing dash: $long" ;; *) _ok ;; esac
git check-ref-format --branch "$long" >/dev/null && _ok || _ko "valid ref: $long"
bash "$BN" wip ABC-1 "x" >/dev/null 2>&1; assert_eq 2 $? "unknown type rejected"
finish
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh` — Expected: failures in `branch-name.test.sh`.

- [ ] **Step 3: Implement**

`skills/ticket-workspace/scripts/branch-name.sh`:
```bash
#!/usr/bin/env bash
# Derive a branch name "<type>/<ticket-id>-<slug>" from a ticket.
# Usage: branch-name.sh <type> <ticket-id> [title words...]
set -u
type=${1:-}; id=${2:-}
[ -n "$type" ] && [ -n "$id" ] || { echo "usage: branch-name.sh <type> <ticket-id> [title...]" >&2; exit 2; }
shift 2
case $type in feat|fix|chore|docs|refactor|test|perf) ;; *) echo "unknown type: $type" >&2; exit 2 ;; esac
slug() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
name="$type/$(slug "$id")"
t=$(slug "$*")
[ -n "$t" ] && name="$name-$t"
name=$(printf '%s' "$name" | cut -c1-60 | sed -E 's/-+$//')
git check-ref-format --branch "$name" >/dev/null 2>&1 || { echo "cannot form a valid branch name from: $id $*" >&2; exit 2; }
printf '%s\n' "$name"
```

- [ ] **Step 4: Run to verify it passes** — `bash tests/run.sh`, expected `0 failed`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/branch-name.test.sh skills/ticket-workspace/scripts/branch-name.sh
git commit -m "feat: add branch-name script"
```

---

### Task 4: `ticket-ws.sh`

**Files:**
- Create: `tests/scripts/ticket-ws.test.sh`, `skills/ticket-workspace/scripts/ticket-ws.sh`

**Interfaces:**
- Produces: `bash ticket-ws.sh path <id>` (prints the workspace path, creates nothing), `init <id>` (creates `logs/ briefs/ reports/` and prints the path; exit 3 if it already exists), `list` (one `<id>\t<phase>` line per ticket of this repo, `_reviews` excluded). Repo slug: remote `origin` name, else the main checkout's folder name taken from the git common dir, so every worktree agrees. Used by Tasks 7–10.

- [ ] **Step 1: Failing test**

`tests/scripts/ticket-ws.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
TW="$ROOT/skills/ticket-workspace/scripts/ticket-ws.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets home"
repo="$tmp/Shop App"; mkdir -p "$repo"; cd "$repo" || exit 1
git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

p=$(bash "$TW" path ABC-123); assert_eq "$TICKETS_HOME/Shop-App/ABC-123" "$p" "path from folder name"
[ -e "$p" ] && _ko "path must not create" || _ok
p2=$(bash "$TW" init ABC-123); assert_eq "$p" "$p2" "init prints the same path"
[ -d "$p/logs" ] && [ -d "$p/briefs" ] && [ -d "$p/reports" ] && _ok || _ko "init creates subdirs"
bash "$TW" init ABC-123 >/dev/null 2>&1; assert_eq 3 $? "second init exits 3"

git worktree add -q "$tmp/wt dir" -b feat/x
p3=$(cd "$tmp/wt dir" && bash "$TW" path ABC-123); assert_eq "$p" "$p3" "same path from a worktree"

bash "$ROOT/skills/ticket-workspace/scripts/state.sh" "$p/state.md" phase intake
mkdir -p "$TICKETS_HOME/Shop-App/_reviews"
out=$(bash "$TW" list); assert_eq "$(printf 'ABC-123\tintake')" "$out" "list shows id and phase, skips _reviews"

git remote add origin "git@github.com:me/shop.git"
assert_eq "$TICKETS_HOME/shop/X-1" "$(bash "$TW" path X-1)" "slug from remote"
assert_eq "$TICKETS_HOME/shop/a-b-c" "$(bash "$TW" path 'a/b c')" "unsafe id characters replaced"
cd "$tmp" && bash "$TW" path X >/dev/null 2>&1; assert_eq 1 $? "outside a repo exits 1"
finish
```

- [ ] **Step 2: Run to verify it fails** — `bash tests/run.sh`.

- [ ] **Step 3: Implement**

`skills/ticket-workspace/scripts/ticket-ws.sh`:
```bash
#!/usr/bin/env bash
# Ticket workspace paths: ${TICKETS_HOME:-~/.patrick-workflows/tickets}/<repo-slug>/<ticket-id>
# Usage: ticket-ws.sh path <id> | init <id> | list
# Exit: 0 ok, 1 not a git repo, 2 bad input, 3 init on an existing workspace.
set -u
root=${TICKETS_HOME:-$HOME/.patrick-workflows/tickets}
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git repository" >&2; exit 1; }
url=$(git config --get remote.origin.url 2>/dev/null || true)
if [ -n "$url" ]; then slug=$(basename "$url" .git)
else
  case $common in */.git) slug=$(basename "$(dirname "$common")") ;; *) slug=$(basename "$common" .git) ;; esac
fi
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
base="$root/$(safe "$slug")"
cmd=${1:-}; id=${2:-}
case $cmd in
  path|init)
    [ -n "$id" ] || { echo "usage: ticket-ws.sh $cmd <id>" >&2; exit 2; }
    dir="$base/$(safe "$id")"
    if [ "$cmd" = init ]; then
      [ ! -e "$dir" ] || { echo "workspace exists: $dir" >&2; exit 3; }
      mkdir -p "$dir/logs" "$dir/briefs" "$dir/reports" || exit 2
    fi
    printf '%s\n' "$dir" ;;
  list)
    [ -d "$base" ] || exit 0
    for d in "$base"/*/; do
      [ -d "$d" ] || continue
      t=$(basename "$d"); [ "$t" = _reviews ] && continue
      ph=$(sed -n 's/^phase: //p' "$d/state.md" 2>/dev/null | head -n 1)
      printf '%s\t%s\n' "$t" "${ph:-none}"
    done ;;
  *) echo "usage: ticket-ws.sh path <id> | init <id> | list" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run to verify it passes** — `bash tests/run.sh`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/ticket-ws.test.sh skills/ticket-workspace/scripts/ticket-ws.sh
git commit -m "feat: add ticket workspace script"
```

---

### Task 5: `secret-scan.sh`

**Files:**
- Create: `tests/scripts/secret-scan.test.sh`, `skills/ticket-workspace/scripts/secret-scan.sh`

**Interfaces:**
- Produces: `bash secret-scan.sh [--deny-file <file>] <file|->...` → one `<file>:<line>: <rule>` line per hit, never the matched text; exit 0 clean, 1 hits, 2 bad input. Rules: `aws-access-key`, `private-key`, `github-token`, `slack-token`, `stripe-key`, `jwt`, `password-assignment`, `url-credentials`, `deny-list` (case-insensitive fixed strings from the deny file). `-` reads stdin (reported as `stdin`). Used by Task 10.

- [ ] **Step 1: Failing test** (secret-shaped strings are assembled at runtime so this repo never contains one)

`tests/scripts/secret-scan.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SS="$ROOT/skills/ticket-workspace/scripts/secret-scan.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
aws="AKIA""QWERTYUIOPASDFGH"
gh="ghp""_""abcdefghijklmnopqrstuvwxyz0123456789AB"
pw="hunter2""hunter2"
{
  echo "clean line"
  echo "key = $aws"
  echo "-----BEGIN RSA ""PRIVATE KEY-----"
  echo "token: $gh"
  echo "password = \"$pw\""
  echo "db: postgres://admin:$pw@db.internal/app"
} > "$tmp/pr body.md"
out=$(bash "$SS" "$tmp/pr body.md"); code=$?
assert_eq 1 "$code" "hits exit 1"
assert_contains "$out" "pr body.md:2: aws-access-key" "aws key with line number"
assert_contains "$out" ":3: private-key" "private key"
assert_contains "$out" ":4: github-token" "github token"
assert_contains "$out" ":5: password-assignment" "password assignment"
assert_contains "$out" ":6: url-credentials" "credentials in url"
assert_not_contains "$out" "$pw" "secret value never printed"
assert_not_contains "$out" "$aws" "key never printed"

echo "nothing to see" > "$tmp/clean.md"
out=$(bash "$SS" "$tmp/clean.md"); assert_eq 0 $? "clean exits 0"; assert_eq "" "$out" "clean prints nothing"

printf '# company strings\nAcme Internal\n' > "$tmp/deny.txt"
echo "Deploy to the acme internal cluster" > "$tmp/c.md"
out=$(bash "$SS" --deny-file "$tmp/deny.txt" "$tmp/c.md"); assert_eq 1 $? "deny list hit"
assert_contains "$out" "c.md:1: deny-list" "deny list is case-insensitive"

out=$(printf 'x\nkey %s\n' "$aws" | bash "$SS" -); assert_contains "$out" "stdin:2: aws-access-key" "stdin"
bash "$SS" "$tmp/none.md" >/dev/null 2>&1; assert_eq 2 $? "missing file exits 2"
finish
```

- [ ] **Step 2: Run to verify it fails** — `bash tests/run.sh`.

- [ ] **Step 3: Implement**

`skills/ticket-workspace/scripts/secret-scan.sh`:
```bash
#!/usr/bin/env bash
# Flag secrets and deny-listed strings in files without printing them.
# Usage: secret-scan.sh [--deny-file <file>] <file|->...
# Prints "<file>:<line>: <rule>" per hit. Exit: 0 clean, 1 hits, 2 bad input.
set -u
deny=""
if [ "${1:-}" = "--deny-file" ]; then
  deny=${2:-}; shift 2
  [ -f "$deny" ] || { echo "deny file not found: $deny" >&2; exit 2; }
fi
[ $# -gt 0 ] || { echo "usage: secret-scan.sh [--deny-file <file>] <file|->..." >&2; exit 2; }
RULES='aws-access-key|AKIA[0-9A-Z]{16}
private-key|-----BEGIN [A-Z ]*PRIVATE KEY-----
github-token|gh[pousr]_[A-Za-z0-9]{36,}
slack-token|xox[baprs]-[A-Za-z0-9-]{10,}
stripe-key|[sr]k_(live|test)_[A-Za-z0-9]{16,}
jwt|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
password-assignment|(password|passwd|secret|api_?key|access_?token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}["'"'"']
url-credentials|[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]+@'
tmpd=$(mktemp -d); trap 'rm -rf "$tmpd"' EXIT
hits=0
scan() {   # $1 path to read, $2 name to report
  while IFS= read -r rule; do
    name=${rule%%|*}; re=${rule#*|}
    for n in $(grep -niE -e "$re" "$1" 2>/dev/null | cut -d: -f1); do
      printf '%s:%s: %s\n' "$2" "$n" "$name"; hits=1
    done
  done <<EOF
$RULES
EOF
  if [ -n "$deny" ]; then
    while IFS= read -r s || [ -n "$s" ]; do
      case $s in ''|'#'*) continue ;; esac
      for n in $(grep -niF -e "$s" "$1" 2>/dev/null | cut -d: -f1); do
        printf '%s:%s: deny-list\n' "$2" "$n"; hits=1
      done
    done < "$deny"
  fi
}
for f in "$@"; do
  if [ "$f" = "-" ]; then cat > "$tmpd/stdin"; scan "$tmpd/stdin" stdin
  elif [ -f "$f" ]; then scan "$f" "$f"
  else echo "not a file: $f" >&2; exit 2
  fi
done
exit "$hits"
```

Note: `scan` runs in the current shell (a `while ... done <<EOF` loop, no pipeline), so `hits=1` survives.

- [ ] **Step 4: Run to verify it passes** — `bash tests/run.sh`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/secret-scan.test.sh skills/ticket-workspace/scripts/secret-scan.sh
git commit -m "feat: add secret-scan script for PR bodies and diffs"
```

---

### Task 6: Ticket agents and `validate.sh` updates

**Files:**
- Create: `agents/ticket-planner.md`, `agents/task-implementer.md`, `agents/task-reviewer.md`
- Modify: `scripts/validate.sh`, `tests/scripts/validate.test.sh`

**Interfaces:**
- Produces: agents `patrick-workflows:ticket-planner`, `patrick-workflows:task-implementer`, `patrick-workflows:task-reviewer` and their output formats (contracts for Tasks 8 and 9). `validate.sh` treats both `final-reviewer` and `task-reviewer` as read-only, and resolves `../<skill>/scripts/<name>.sh` references.

- [ ] **Step 1: Failing validate tests**

Append to `tests/scripts/validate.test.sh` before `finish`:
```bash
fresh; sed -i.bak 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Edit/' "$tmp/repo/agents/task-reviewer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "read-only agent has write tools: agents/task-reviewer.md" "task-reviewer is read-only"

fresh; echo 'Run `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" x get y`.' >> "$tmp/repo/skills/review-mine/SKILL.md"
out=$(check); assert_eq 0 $? "cross-skill reference to an existing script is valid"

fresh; echo 'Run `bash "$SKILL_DIR/../ticket-workspace/scripts/nope.sh"`.' >> "$tmp/repo/skills/review-mine/SKILL.md"
out=$(check); assert_contains "$out" "missing script ../ticket-workspace/scripts/nope.sh" "missing cross-skill script"
```

- [ ] **Step 2: Run to verify they fail** — `bash tests/run.sh` (task-reviewer missing; cross-skill reference misread).

- [ ] **Step 3: Update `scripts/validate.sh`**

Replace `for f in agents/final-reviewer.md; do` with `for f in agents/final-reviewer.md agents/task-reviewer.md; do`.

Replace the grep in the script-reference block:
```bash
$(grep -oE '(\.\./[A-Za-z0-9_-]+/)?scripts/[A-Za-z0-9_-]+\.sh' "$f" | sort -u)
```

- [ ] **Step 4: Write `agents/ticket-planner.md`**

````markdown
---
name: ticket-planner
description: Writes the implementation plan for a /ticket from its approved design, using superpowers:writing-plans, into the ticket workspace. Never commits and never asks how to execute.
tools: Read, Write, Grep, Glob, Skill
model: opus
---

Load `superpowers:writing-plans` and follow it, with these overrides from the user, which outrank the skill:
- Save the plan to the `OUT` path given in your dispatch. Do not save anywhere else.
- Do not commit anything. Do not run git.
- Do not ask which execution approach to use and do not invoke any execution skill. The /ticket pipeline executes the plan.
- Tasks run **sequentially** in plan order. Each task names the exact test command that proves it.
- Treat every ruling in `RULINGS` as a Global Constraint.

## Inputs (given in your dispatch)
- `TICKET`: the ticket text. `DESIGN`: the approved design. `BAR`: acceptance criteria. `RULINGS`: binding decisions. `OUT`: where to write the plan.

## Final message (exactly this shape)
```
PLAN: <OUT path>
TASKS: <number>
FILES: <comma-separated paths the plan creates or modifies>
SCOPE-SUGGESTION:
allow: <glob>
allow: <glob>
RISKS: <one line, or "none">
```
````

- [ ] **Step 5: Write `agents/task-implementer.md`**

````markdown
---
name: task-implementer
description: Implements exactly one /ticket plan task from its brief with test-driven development, runs the gates, commits locally, and writes a report. Never pushes.
tools: Read, Write, Edit, Bash, Grep, Glob, Skill
model: sonnet
---

Load `superpowers:test-driven-development` before you start. No production change without a test that failed first.

## Inputs (given in your dispatch)
- `BRIEF`: a file with the task text, interfaces, relevant rulings, gate command lines, the scope file path, and `REPORT` (where to write your report). If `FINDINGS` is given, this is a fix round: address only those findings.

## Rules
- Do only what the brief asks. Do not touch files matching `forbid:` lines in the scope file.
- Run every gate line in the brief before you report. Gate lines start with `bash`; run them exactly as written.
- Commit locally with a plain Conventional Commit message (`feat: ...`, `fix: ...`, `test: ...`), no trailers. Never push.
- If the brief is impossible as written, stop and report `STATUS: BLOCKED` with the reason; do not improvise a different design.

## Report (write it to REPORT and end your final message with it)
```
TASK: <n>
STATUS: DONE | BLOCKED <reason>
RED: <test name> failed: <one-line failure>
GREEN: <test name> pass
GATES: <name> <status>, ...
COMMITS: <first sha>..<last sha>
FILES: <paths>
CONCERNS: <one line, or "none">
```
````

- [ ] **Step 6: Write `agents/task-reviewer.md`**

````markdown
---
name: task-reviewer
description: Fresh, read-only review of one /ticket task against its brief and the rulings. Returns APPROVE or CHANGES with evidenced findings. Never edits files.
tools: Read, Grep, Glob
model: sonnet
---

You review one task you did not write. You cannot run commands.

## Inputs (given in your dispatch)
- `BRIEF`: what the task was supposed to do. `REPORT`: the implementer's report. `PACKAGE`: a review package for this task's commits (`diff.patch`, `files.txt`, `symbols.txt`, `callers.txt`, `README.txt`; the package is a starting point, not the boundary). `RULINGS`: binding decisions.

## Check
1. Does the diff do what the brief asks, completely, and nothing outside it?
2. Is there a test that would have failed without the change, matching the report's RED line?
3. Does it break callers or conventions around it?
Severity: Critical (wrong result on a main path, data loss, security hole, brief not met), Important (edge-case bug, missing validation, likely regression), Minor (everything else).

## Output (exactly this shape)
```
VERDICT: APPROVE | CHANGES
FINDINGS:
N1 — <title>
Severity: Critical | Important | Minor
Kind: behavioral | structural
Location: <path>:<line>
Trigger: <input or condition>
Expected: <what should happen>
Actual: <what the code does>
(or "none")
```
`CHANGES` only if there is at least one Critical or Important finding. Report a finding only if every field is filled.
````

- [ ] **Step 7: Run to verify** — `./scripts/validate.sh && bash tests/run.sh`; expected `OK: repo is valid` and every file `0 failed`.

- [ ] **Step 8: Commit**
```bash
git add agents scripts/validate.sh tests/scripts/validate.test.sh
git commit -m "feat: add ticket planner, implementer and reviewer agents"
```

---

### Task 7: `ticket-workspace` reference skill and `/ticket` router

**Files:**
- Create: `skills/ticket-workspace/SKILL.md`, `commands/ticket.md`

**Interfaces:**
- Consumes: scripts from Tasks 2–5.
- Produces: the stage routing every later task assumes; the formats all stage skills share.

- [ ] **Step 1: Write `skills/ticket-workspace/SKILL.md`**

````markdown
---
name: ticket-workspace
description: Reference for the /ticket pipeline - workspace layout, state keys, phase machine, ruling and finding formats, and the shared scripts. Read by every ticket stage skill; use when any /ticket stage starts.
---

# Ticket workspace

`TW` = `bash "$SKILL_DIR/scripts/<name>.sh"` where `SKILL_DIR` is this skill's base directory. Stage skills call these as `bash "$SKILL_DIR/../ticket-workspace/scripts/<name>.sh"`.

## Location
`bash ticket-ws.sh path <id>` → `~/.patrick-workflows/tickets/<repo>/<id>/` (`TICKETS_HOME` overrides the root). The same path from every worktree. Never inside the project, never under `~/.claude/`.

## Layout
```
state.md        machine-readable "key: value" lines (below); change only via state.sh
ticket.md       ticket text verbatim
bar.md          acceptance criteria AC1..ACn, plus "Deferred:" list
design.md       approved design
plan.md         approved plan (round 2 appends tasks under "## Round 2")
rulings.md      binding rulings
scope.txt       allow:/forbid: lines for scope-check.sh
ledger.md       one line per completed step; state.sh appends phase changes
baseline.md     gate results on the base commit
briefs/task-N.md, reports/task-N.md
logs/           gate logs and .status files
review-mine/    the review loop's own workspace (state, rounds, report.md)
handoff.md      the SHIP report; pr-body.md the draft PR body
```

## State keys
`ticket`, `title`, `phase`, `branch`, `base` (sha), `base_branch`, `checkout` (`main` or a worktree path), `depth` (`lite`|`standard`), `tasks_total`, `tasks_done`, `round2` (`no`|`yes`), `budget_impl_max`, `budget_impl_used`, `budget_review_max`, `gate.<name>` (command), `gate_timeout`, `exit_pair` (`none` or the exit-pair flags), `pr_target`, `pr_url`, `preflight` (`done`).

## Phases
`state.sh <state.md> phase <new>` is the only way to change phase; it refuses illegal jumps and logs every change.
```
intake → designed → planned → approved → implementing → reviewing ⇄ fixing → ready
implementing | reviewing | fixing → blocked
ready | blocked → handoff → round2 → implementing ...   handoff → pr → closed
```
Stage per phase: none/intake/designed/planned → `ticket-plan`; approved/round2/implementing/reviewing/fixing → `ticket-build`; ready/blocked/handoff → `ticket-ship`; pr → CLOSE (Phase 1c; not yet available); closed → nothing left to do.

## Formats
Ruling (`rulings.md`):
```
R3 — <title> (source: user | orchestrator)
Decision: ... / Why: ... / Cost if wrong: ... / Applies to: all | task N
```
Finding: the format in `patrick-workflows:final-reviewer` (ID, Severity, Kind, Location, Trigger, Expected, Actual).
Ledger line: `<UTC time> <step> <result>`.

## Scripts
| Script | Use |
|---|---|
| `state.sh <state.md> get/set/incr/phase ...` | state and phases |
| `ticket-ws.sh path/init/list` | workspace location |
| `branch-name.sh <type> <id> <title...>` | branch name |
| `secret-scan.sh [--deny-file f] <file\|->...` | secrets before a PR |
````

- [ ] **Step 2: Write `commands/ticket.md`**

```markdown
---
description: Take a ticket from intake to a draft PR - plan with you, build and review on its own, then ship on your say-so
argument-hint: "[ticket id | url | pasted text]"
---

Route this ticket with the `patrick-workflows:ticket-workspace` skill's phase table:

1. Arguments: $ARGUMENTS
2. If no argument was given, run `bash "<ticket-workspace skill dir>/scripts/ticket-ws.sh" list` and ask which ticket to continue, or to paste a new one.
3. If the argument is an ID or URL with an existing workspace (`ticket-ws.sh path <id>` exists), read its `phase` with `state.sh` and invoke the stage skill the phase table names: `patrick-workflows:ticket-plan`, `patrick-workflows:ticket-build`, or `patrick-workflows:ticket-ship`. For `pr`, say that CLOSE (marking the ticket done after merge) is not available yet and show `pr_url`. For `closed`, say the ticket is finished.
4. Otherwise it is a new ticket: invoke `patrick-workflows:ticket-plan` with the argument.
```

- [ ] **Step 3: Validate** — `./scripts/validate.sh && claude plugin validate .` → `OK` and `✔ Validation passed`.

- [ ] **Step 4: Commit**
```bash
git add skills/ticket-workspace/SKILL.md commands/ticket.md
git commit -m "feat: add ticket workspace reference and /ticket router"
```

---

### Task 8: `ticket-plan` skill (PLAN stage)

**Files:**
- Create: `skills/ticket-plan/SKILL.md`

**Interfaces:**
- Consumes: `ticket-ws.sh`, `state.sh`, `branch-name.sh` (Tasks 2–4); `ticket-planner` (Task 6); `exit-pair.sh --check` and `run-gate.sh` (Task 1, 1a); spike S8/S9 results (Task 0).
- Produces: a workspace in phase `approved` with `ticket.md`, `bar.md`, `design.md`, `plan.md`, `rulings.md`, `scope.txt`, `state.md`; then invokes `ticket-build`.

- [ ] **Step 1: Write the skill**

`skills/ticket-plan/SKILL.md`:
````markdown
---
name: ticket-plan
description: PLAN stage of /ticket - read the ticket, settle acceptance criteria, create the branch, brainstorm the design, write the plan, and agree the autonomy brief with the user. The only interactive stage before BUILD; ends by starting BUILD.
---

# PLAN

Read `patrick-workflows:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`. Ask the user whatever you need in this stage; after the final approval, nothing more is asked until SHIP.

## 1. Identify the ticket
- An ID (`ABC-123`, `#42`) or URL: that is the ID. Pasted text with no ID: ask the user for a short ID (suggest `T-<yyyymmdd>-<two words>`).
- `WS=$(bash "$SKILL_DIR/../ticket-workspace/scripts/ticket-ws.sh" path <id>)`. If it exists, resume at the first missing step below according to `phase`. Otherwise `ticket-ws.sh init <id>`, then `S set ticket <id>` and `S phase intake`.

## 2. Intake
Read the ticket with whatever the machine offers: `gh issue view <n> --json title,body,comments` for GitHub; a tracker MCP tool if one is available; otherwise ask the user to paste it. Save it verbatim to `WS/ticket.md`; `S set title "<title>"`.

## 3. Acceptance criteria
Extract them into `WS/bar.md` as `AC1`, `AC2`, ... with a final `Deferred:` line. None in the ticket → write them with the user now. The run does not start without them.

## 4. Branch and checkout
1. Type: `fix` for bugs, else `feat` (ask if unclear). `BR=$(bash ".../branch-name.sh" <type> <id> <title>)`; show it; the user may rename.
2. Base: the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`, else local `main`). `git fetch origin <base> -q` if a remote exists.
3. Ask: main checkout (recommended) or a worktree. Worktree: `git worktree add ../<repo>-<id> -b <BR> <base>`; per the phase 1b spike, tell the user to continue in a session started in that folder if this session cannot write there. Main checkout: requires a clean tree; `git switch -c <BR> <base>`.
4. `S set branch <BR>`, `S set base $(git rev-parse HEAD)`, `S set base_branch <base>`, `S set checkout <main|path>`, `S set pr_target <base>`.

## 5. Design
Invoke `superpowers:brainstorming` with these overrides from the user, which outrank the skill: save the design to `WS/design.md` (not `docs/`); do not commit it; when the user approves the design, do not invoke writing-plans, return here. Then `S phase designed`.

## 6. Plan
Dispatch `patrick-workflows:ticket-planner` (model opus) with `TICKET`, `DESIGN`, `BAR`, `RULINGS` (`WS/rulings.md`, created empty if absent) and `OUT=WS/plan.md`. If the spike showed the overrides are not honored inside the agent, run `superpowers:writing-plans` here instead with the same overrides. Show the user the task list and the risks; revise until they approve. `S set tasks_total <n>`, `S set tasks_done 0`, `S phase planned`.

## 7. Autonomy brief
Settle each item, then show the whole brief once for approval:
1. **Gates:** detect as `review-mine` does (package.json / Makefile / pyproject / Cargo / go.mod); `S set gate.<name> <command>`; `S set gate_timeout 900`.
2. **Scope:** start from the planner's `SCOPE-SUGGESTION`; ask for `forbid:` paths; write `WS/scope.txt`.
3. **Depth:** `lite` if the plan has at most 2 tasks and no path matches auth, security, crypto, payment, billing, session, token, password or permission; else `standard`. The user may raise it. `S set depth`.
4. **Budget:** `budget_impl_max` = 2 × tasks (lite) or 4 × tasks (standard); `budget_review_max` = 3 (lite) or 10 (standard); `budget_impl_used 0`.
5. **Exit pair (optional):** if the user wants whole-feature proof, collect `--prove`, `--reset`, `--env-file`, `--db-pattern`; run `bash "$SKILL_DIR/../review-mine/scripts/exit-pair.sh" --check <flags>`; refused → explain why and drop it or fix the env file. `S set exit_pair "<flags>"` or `none`.
6. **Permissions:** print the allow rules this run needs for the user to add to the project's `.claude/settings.local.json` (you never edit settings): `Read(~/.patrick-workflows/**)`, `Edit(~/.patrick-workflows/**)`, `Bash(bash *patrick-workflows*/skills/*/scripts/*)` or the plugin path in use, each gate command, `Bash(git add*)`, `Bash(git commit*)`, `Bash(git diff*)`, `Bash(git log*)`, `Bash(git status*)`, `Bash(git switch*)`, `Bash(git rev-parse*)`.
7. **Rulings:** record every decision made in this stage in `WS/rulings.md` (`source: user`).

Ask for one approval of the brief. On approval: run every gate once as `bash "$SKILL_DIR/../review-mine/scripts/run-gate.sh" preflight-<name> <timeout> -- "<command>"` with the review workspace pointer set by `bash "$SKILL_DIR/../review-mine/scripts/workspace.sh" --at "<WS>/review-mine"`. If any permission prompt appeared, ask the user to add the rule now and rerun. Then `S phase approved` and invoke `patrick-workflows:ticket-build` immediately.
````

- [ ] **Step 2: Validate** — `./scripts/validate.sh && claude plugin validate .`

- [ ] **Step 3: Commit**
```bash
git add skills/ticket-plan/SKILL.md
git commit -m "feat: add ticket-plan stage skill"
```

---

### Task 9: `ticket-build` skill (BUILD stage)

**Files:**
- Create: `skills/ticket-build/SKILL.md`

**Interfaces:**
- Consumes: `state.sh`; `run-gate.sh`, `scope-check.sh`, `review-package.sh`, `workspace.sh --at`, `exit-pair.sh` (review-mine scripts); `task-implementer`, `task-reviewer`; `review-mine` embedded mode (Task 1).
- Produces: phase `ready` or `blocked`; `reports/task-N.md`; `review-mine/report.md`; then invokes `ticket-ship`.

- [ ] **Step 1: Write the skill**

`skills/ticket-build/SKILL.md`:
````markdown
---
name: ticket-build
description: BUILD stage of /ticket - runs the approved plan task by task with fresh implementers and reviewers, then the review-mine loop, without asking the user anything. Ends at ready or blocked and hands over to SHIP.
---

# BUILD

Read `patrick-workflows:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`; `R` = `$SKILL_DIR/../review-mine/scripts`.

## Rules
- Ask the user nothing. Stop only for: an irreversible or destructive action, a security-sensitive action, an outside side effect (push, publish, send), or a plan so broken that every path is a guess. Every other decision is a ruling in `WS/rulings.md` (`source: orchestrator`, with cost if wrong).
- Never push. Never edit settings. Commit messages carry no trailers.
- Never trust a subagent's claim of green: re-run gates yourself.
- Ledger: one line per completed step in `WS/ledger.md`.
- Resume: after a crash or `/clear`, read `state.md`, `ledger.md` and `git log`; a task with a `task N complete` ledger line is done.

## 1. Pre-flight (skip if `preflight: done`)
1. Phase must be `approved` or `round2`; HEAD must be on `branch`; tree clean.
2. `bash "$R/workspace.sh" --at "<WS>/review-mine"` (sets the pointer every review script uses).
3. Baseline, only in round 1 and only while HEAD equals `base`: run each gate as `bash "$R/run-gate.sh" baseline-<name> <gate_timeout> -- "<command>"`; write `WS/baseline.md` (status per gate, citing `review-mine/logs/baseline-<name>.status`; failing gates are known reds). A gate that `could-not-run` → `S phase implementing` then `S phase blocked`, with the reason in the ledger, and go to section 4.
4. If `exit_pair` is set: `bash "$R/exit-pair.sh" --check <flags>`; refused → drop it with a ruling.
5. `S set preflight done`; `S phase implementing`.

## 2. Task driver
For each `### Task N` in `plan.md` (and `## Round 2` tasks when `round2: yes`) without a `task N complete` ledger line, in order:
1. Record `task_base=$(git rev-parse HEAD)`.
2. Write `WS/briefs/task-N.md`: the task text verbatim; the rulings that apply; one gate line per gate (`bash "$R/run-gate.sh" task<N>-<name> <gate_timeout> -- "<command>"`); the scope file `WS/scope.txt`; `REPORT: WS/reports/task-N.md`.
3. **standard:** dispatch `patrick-workflows:task-implementer` (model sonnet) with `BRIEF`; `S incr budget_impl_used`. **lite:** implement it yourself under `superpowers:test-driven-development`, writing the same report.
4. Report says `BLOCKED` → ruling; if the plan cannot continue without it, stop condition 4 → `S phase blocked`, go to section 4.
5. Re-run every gate as `task<N>-<name>`. A gate red now but green in the baseline: triage (product bug → fix round; test defect → fix the test; environment → record a blocker; hung → one retry if a ruling allows). Run `bash "$R/scope-check.sh" <task_base> WS/scope.txt`: `forbidden` → fix round; `out-of-scope` → ruling.
6. **standard:** `bash "$R/review-package.sh" <task_base> HEAD "<WS>/review-mine/tasks/task-N"`; dispatch `patrick-workflows:task-reviewer` with `BRIEF`, `REPORT`, `PACKAGE`, `RULINGS`; `S incr budget_impl_used`. `CHANGES` → fix round.
7. **Fix round** (max 2 per task): a new `task-implementer` dispatch with `BRIEF` plus `FINDINGS` (the open Critical/Important findings and gate failures), then steps 5–6 again with a new reviewer. Still open after 2 → append them to `WS/bar.md` under `Known open issues to verify:` so the review loop re-checks them.
8. Ledger: `task N complete <task_base>..<HEAD> gates <summary> review <verdict>`; `S incr tasks_done`.
9. Before each dispatch, if `budget_impl_used >= budget_impl_max`: stop the task driver, add a ruling, and go to section 3 (the review budget is reserved separately).

## 3. Review loop
1. `S phase reviewing`.
2. Invoke `patrick-workflows:review-mine` in embedded mode: base = `base`, `--workspace "<WS>/review-mine"`, `--criteria "<WS>/bar.md"`, `--scope "<WS>/scope.txt"`, `--baseline "<WS>/baseline.md"`, `--depth <depth>`, `--budget <budget_review_max>`, plus the `exit_pair` flags if set. Mirror its round changes into this ticket's phase (`S phase fixing` / `S phase reviewing`).
3. Read `review-mine/state.md` `status`: `ready` → `S phase ready`; otherwise `S phase blocked`.

## 4. Hand over
Ledger: `build finished <phase>`. Invoke `patrick-workflows:ticket-ship`.
````

- [ ] **Step 2: Validate** — `./scripts/validate.sh && claude plugin validate .`

- [ ] **Step 3: Commit**
```bash
git add skills/ticket-build/SKILL.md
git commit -m "feat: add ticket-build stage skill"
```

---

### Task 10: `ticket-ship` skill (SHIP stage, round 2)

**Files:**
- Create: `skills/ticket-ship/SKILL.md`

**Interfaces:**
- Consumes: `state.sh`, `secret-scan.sh`; workspace files from BUILD; `review-mine/report.md`.
- Produces: `handoff.md`, `pr-body.md`; phase `round2` (and invokes `ticket-build`) or `pr` with `pr_url`.

- [ ] **Step 1: Write the skill**

`skills/ticket-ship/SKILL.md`:
````markdown
---
name: ticket-ship
description: SHIP stage of /ticket - writes one report with numbered questions, takes the user's answers, runs round 2 if they ask for changes, and opens a draft PR only on their explicit go-ahead after a secrets scan.
---

# SHIP

Read `patrick-workflows:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`.

## 1. Write the report (`WS/handoff.md`), in this order
1. **Outcome:** `READY` or `BLOCKED: <reason>`; depth; tasks done / total; dispatches used / budgets.
2. **Needs your decision:** numbered questions, each with your recommendation, answerable in a few words ("1 keep 2 change: ... 3 yes"). Include deferred Importants, out-of-scope files, unreproduced findings that need a call, and blockers. The last question is always: "Open the draft PR? (yes / no)".
3. **Unreproduced findings** (security first).
4. **Severity downgrades.**
5. **What changed:** `git diff --stat <base>..HEAD`, commits `git log --oneline <base>..HEAD`, scope classes from the last scope check.
6. **Evidence:** gates vs baseline (known reds called out); red→green per task from `reports/task-N.md`; review-loop verdicts per round and exit-pair result from `review-mine/`.
7. **Rulings:** every line of `rulings.md` with cost if wrong.
8. **Base drift:** `git fetch origin <base_branch> -q` then `git rev-list --count <base>..origin/<base_branch>`; non-zero → "base moved by N commits; rebase before PR?" becomes a question.
9. **Draft PR:** title `<type>(<id>): <title>`; body written to `WS/pr-body.md` with Summary, Changes, How it was tested (the evidence), Ticket link. No tool attribution of any kind.

`S phase handoff`. Show the user section 1–2 in chat and the path to `handoff.md`. Wait for the answers.

## 2. Answers
- Record each answer as a ruling (`source: user`).
- Any answer that asks for a code change: append the needed tasks to `plan.md` under `## Round 2` (write them yourself in the plan's task format, with tests), `S set round2 yes`, add their count to `tasks_total`, set `budget_impl_max` to `budget_impl_used` + 4 × new tasks (2 × for lite), reset the review budget (`review-mine` gets a fresh `--budget`), `S phase round2`, and invoke `patrick-workflows:ticket-build`. The review loop's bars run in full on the whole branch.
- A "rebase" answer: `git rebase origin/<base_branch>`; on conflict, `git rebase --abort` and ask the user how to proceed; after a successful rebase re-run the gates once and note it in the PR body.

## 3. Open the PR (only after an explicit yes)
1. Secrets: `git diff <base>..HEAD | bash "$SKILL_DIR/../ticket-workspace/scripts/secret-scan.sh" [--deny-file .claude/patrick-workflows-deny.txt] - "<WS>/pr-body.md"` (use the deny file only if the project has it). Any hit → show the rule and location (never the value) and stop; this is security-sensitive and the user decides.
2. Show the final PR title and body.
3. `git push -u origin <branch>`; `gh pr create --draft --base <pr_target> --title "<title>" --body-file "<WS>/pr-body.md"`.
4. `S set pr_url <url>`, `S phase pr`. Tell the user the PR URL, and that marking the ticket done after merge (CLOSE) arrives in Phase 1c.
````

- [ ] **Step 2: Validate** — `./scripts/validate.sh && claude plugin validate .`

- [ ] **Step 3: Commit**
```bash
git add skills/ticket-ship/SKILL.md
git commit -m "feat: add ticket-ship stage skill with round 2"
```

---

### Task 11: Ticket fixture, smoke checklist, headless BUILD/SHIP smoke

**Files:**
- Create: `tests/fixture/seed-ticket.sh`, `tests/scripts/seed-ticket.test.sh`, `tests/SMOKE-ticket.md`

**Interfaces:**
- Consumes: `tests/fixture/setup.sh` (1a), `state.sh`, `ticket-ws.sh`.
- Produces: `bash tests/fixture/seed-ticket.sh <fixture-repo>` → in that repo, branch `feat/fx-1-percentage-discounts` from `main`, and an `approved` FX-1 workspace (under `TICKETS_HOME` if set) with a two-task plan, bar, rulings, scope, gates, depth standard, budgets.

- [ ] **Step 1: Failing test**

`tests/scripts/seed-ticket.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets"
bash "$ROOT/tests/fixture/setup.sh" "$tmp/shop" >/dev/null
ws=$(bash "$ROOT/tests/fixture/seed-ticket.sh" "$tmp/shop"); code=$?
assert_eq 0 "$code" "seed exits 0"
ST="$ROOT/skills/ticket-workspace/scripts/state.sh"
assert_eq approved "$(bash "$ST" "$ws/state.md" get phase)" "phase approved"
assert_eq "feat/fx-1-percentage-discounts" "$(git -C "$tmp/shop" rev-parse --abbrev-ref HEAD)" "on the ticket branch"
assert_eq "$(git -C "$tmp/shop" rev-parse main)" "$(bash "$ST" "$ws/state.md" get base)" "base is main"
for f in ticket.md bar.md design.md plan.md rulings.md scope.txt; do assert_file "$ws/$f" "$f written"; done
assert_eq 2 "$(grep -c '^### Task ' "$ws/plan.md")" "two tasks"
finish
```

- [ ] **Step 2: Run to verify it fails** — `bash tests/run.sh`.

- [ ] **Step 3: Implement `tests/fixture/seed-ticket.sh`**

````bash
#!/usr/bin/env bash
# Seed an approved FX-1 ticket on a fixture repo (from setup.sh) for headless BUILD/SHIP smoke runs.
# Usage: seed-ticket.sh <fixture-repo>   → prints the ticket workspace path
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$ROOT/skills/ticket-workspace/scripts"
repo=${1:?usage: seed-ticket.sh <fixture-repo>}
cd "$repo"
git switch -q main
git switch -q -c feat/fx-1-percentage-discounts
ws=$(bash "$T/ticket-ws.sh" init FX-1)
S() { bash "$T/state.sh" "$ws/state.md" "$@"; }

cat > "$ws/ticket.md" <<'EOF'
# FX-1: Percentage discounts
Shoppers can apply a percentage discount and a coupon code at checkout.
Acceptance criteria:
- A discount between 0 and 100 percent reduces the total by that percentage, rounded to the nearest cent.
- A discount outside 0-100 or not a number is rejected with an error.
- Coupon SAVE10 gives 10 percent; unknown codes are rejected with an error.
EOF
cat > "$ws/bar.md" <<'EOF'
AC1: applyDiscount(total, percent) returns total minus round(total*percent/100) for 0 <= percent <= 100.
AC2: applyDiscount throws a RangeError for percent < 0, > 100, or not a finite number.
AC3: applyCoupon(total, 'SAVE10') returns applyDiscount(total, 10); an unknown code throws an Error.
Deferred:
EOF
cat > "$ws/design.md" <<'EOF'
# FX-1 design
Add applyDiscount and applyCoupon to src/cart.js. Coupons come from a fixed table in the same file. Errors are thrown, not returned.
EOF
cat > "$ws/plan.md" <<'EOF'
# FX-1 plan
Tests run with: npm test

### Task 1: applyDiscount
Files: src/cart.js, test/discount.test.js
- Write failing tests in test/discount.test.js: applyDiscount(1000, 10) === 900; applyDiscount(999, 50) === 499 (rounded); applyDiscount(1000, 150), applyDiscount(1000, -1) and applyDiscount(1000, NaN) throw RangeError.
- Implement applyDiscount(total, percent) in src/cart.js and export it.
- Run npm test: only the known red formatPrice test may fail.

### Task 2: applyCoupon
Files: src/cart.js, test/coupon.test.js
- Write failing tests in test/coupon.test.js: applyCoupon(1000, 'SAVE10') === 900; applyCoupon(1000, 'BOGUS') throws Error.
- Implement applyCoupon(total, code) in src/cart.js with const COUPONS = { SAVE10: 10 } and export it.
- Run npm test: only the known red formatPrice test may fail.
EOF
printf 'R1 — Coupons from a fixed table (source: user)\nDecision: COUPONS = { SAVE10: 10 } in src/cart.js / Why: no coupon service yet / Cost if wrong: one refactor / Applies to: task 2\n' > "$ws/rulings.md"
printf 'allow: src/**\nallow: test/**\nforbid: src/billing/**\n' > "$ws/scope.txt"

S set ticket FX-1; S set title "Percentage discounts"
S set branch feat/fx-1-percentage-discounts; S set base "$(git rev-parse main)"; S set base_branch main
S set checkout main; S set pr_target main; S set depth standard
S set tasks_total 2; S set tasks_done 0; S set round2 no
S set budget_impl_max 8; S set budget_impl_used 0; S set budget_review_max 10
S set gate.test "npm test"; S set gate_timeout 300; S set exit_pair none
for p in intake designed planned approved; do S phase "$p"; done
printf '%s\n' "$ws"
````

- [ ] **Step 4: Run to verify it passes** — `bash tests/run.sh`.

- [ ] **Step 5: Write `tests/SMOKE-ticket.md`**

````markdown
# /ticket smoke test

## Run A (headless): BUILD and SHIP from a seeded ticket
```bash
bash tests/fixture/setup.sh /tmp/tk-shop
bash tests/fixture/seed-ticket.sh /tmp/tk-shop
cd /tmp/tk-shop
claude -p --plugin-dir "<repo>" --permission-mode acceptEdits \
  --allowedTools "Read(~/.patrick-workflows/**)" "Edit(~/.patrick-workflows/**)" "Bash(bash *)" "Bash(git *)" "Bash(npm *)" "Bash(node *)" "Skill" "Agent" "Read" "Grep" "Glob" "Write" "Edit" \
  -- "/ticket FX-1" < /dev/null
```
Expected:
- [ ] BUILD resumes at `approved`; no questions until the SHIP report.
- [ ] `baseline.md` lists the known red formatPrice test.
- [ ] Two tasks, each with a `reports/task-N.md` naming a red test and a green run; a `task N complete` ledger line each.
- [ ] The orchestrator re-ran gates after each task (`logs/task<N>-test.status` in `review-mine/logs`).
- [ ] The review loop ran in `review-mine/`; phase ends `ready` (or `blocked` with a reason matching the files).
- [ ] `handoff.md` exists with numbered questions ending in "Open the draft PR?"; phase `handoff`; nothing pushed (the fixture has no remote).
- [ ] `ledger.md` shows `approved -> implementing -> reviewing ... -> handoff` with no illegal jump.

## Run B (interactive): full PLAN on the fixture
```bash
bash tests/fixture/setup.sh /tmp/tk-shop-2 && cd /tmp/tk-shop-2 && claude --plugin-dir "<repo>"
```
`/ticket` then paste the FX-1 ticket text from `tests/fixture/seed-ticket.sh`.
- [ ] Asked for an ID; acceptance criteria confirmed; branch name proposed.
- [ ] Design saved to the workspace, not `docs/`; nothing committed during PLAN.
- [ ] Plan written by `ticket-planner` into the workspace; brief shown once; permission rules printed.
- [ ] After approval, BUILD starts without a new command.

## Record
Dispatches used (implementation / review), tasks, rounds, wall time.
````

- [ ] **Step 6: Run Run A headless** and tick the boxes from the workspace files. Any unchecked box is a defect: fix it (test first where it is in a script) and rerun.

- [ ] **Step 7: Commit**
```bash
git add tests/fixture/seed-ticket.sh tests/scripts/seed-ticket.test.sh tests/SMOKE-ticket.md
git commit -m "test: add ticket fixture seed and smoke checklist"
```

---

### Task 12: README, version, verification

**Files:**
- Modify: `README.md`, `.claude-plugin/plugin.json`

- [ ] **Step 1: README section** (insert before `## /review-mine`)

````markdown
## /ticket

```
/ticket ABC-123        start or continue a ticket (ID, URL, or pasted text)
/ticket                list tickets in this repo
```

- **PLAN (with you):** reads the ticket, settles acceptance criteria, creates the branch, brainstorms the design, writes the plan, and agrees an autonomy brief: gates, scope, review depth, budget, optional exit pair, and the permission rules to add.
- **BUILD (on its own):** one fresh implementer and reviewer per task, test first, gates re-run by the orchestrator, then the `/review-mine` loop. Asks nothing.
- **SHIP (with you):** one report with numbered questions. Ask for changes and it runs a second round; say yes and it scans for secrets, then opens a draft PR.

Run `/ticket <id>` again at any time to resume where it stopped. Working files live in `~/.patrick-workflows/tickets/<repo>/<id>/`. Marking the ticket done after merge (CLOSE) and UI grading come in later versions.

Optional: list company names and internal hostnames, one per line, in your work project's `.claude/patrick-workflows-deny.txt`; SHIP refuses to open a PR whose body or diff contains them.
````

- [ ] **Step 2: Version** — `.claude-plugin/plugin.json` `"version": "0.2.0"` → `"0.3.0"`.

- [ ] **Step 3: Verify** — `./scripts/validate.sh && bash tests/run.sh && claude plugin validate .`; expected all green.

- [ ] **Step 4: Commit and tag**
```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: document /ticket and bump version to 0.3.0"
git tag v0.3.0
```
Do not push.
