# `/review-mine` (Phase 1a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `/review-mine`, a standalone command that runs the builder/critic review loop on any branch: fresh critics by concern, evidence rule, fix rounds proven by red tests, fresh re-review, an explicit PASS verdict, and an optional exit pair with reset safety.

**Architecture:** A slash command invokes the `review-mine` skill, which the main session follows as orchestrator. Deterministic work lives in bash scripts inside the skill (`skills/review-mine/scripts/`), tested with plain bash tests. Judgment lives in two agents: a read-only `final-reviewer` critic and a `ticket-fixer`. All working files go to a local workspace under `~/.claude/tickets/`, never into the repo.

**Tech Stack:** Bash (macOS bash 3.2 compatible), git, perl (process groups), Node 22 (fixture only), Claude Code plugin markdown, superpowers skills.

**Spec:** `docs/superpowers/specs/2026-10-02-ticket-pipeline-design.md` (v7; this plan implements Phase 1a, sections 4, 5, 8, 9.3–9.5, 10, 11, 12, 15, 16, 17 items 1–3).

## Global Constraints

- Plugin name `patrick-workflows`; all new components live in this repo and stay public-safe (no employer content, no secrets).
- No tool attribution anywhere: no co-author trailers in commits, no "generated with" footers. `scripts/validate.sh` enforces it.
- Commit messages use Conventional Commits (`feat:`, `test:`, `docs:`, `chore:`). Never push; pushing is the user's call.
- Bash scripts must run on macOS's bash 3.2 and BSD tools: no `mapfile`, no associative arrays, no `timeout` binary, no `sed -i` without a backup argument, `sed -E` for alternation.
- Every path must survive spaces (this repo lives in `claude workflows`). Quote every expansion.
- Scripts in `skills/review-mine/scripts/` are always invoked as `bash <path>`, so they never depend on the executable bit after plugin install.
- Workspace root is `${TICKETS_HOME:-$HOME/.claude/tickets}`; standalone reviews go to `<root>/<repo-slug>/_reviews/<branch>-<UTC timestamp>/`.
- Review depth: `lite` = 1 combined critic on Opus, inline fixes, `rounds_max` 2, review budget 3. `standard` = critics `impact` (Opus), `security+regression` (Opus), `requirements+maintainability` (Sonnet), `ticket-fixer`, `rounds_max` 4, review budget 10. Re-review on Sonnet. One dispatch is protected for the final re-review/PASS.
- Exit pair: `reset` never runs unless the env file's database value matches the declared pattern and the host is local (unless `--allow-remote`).
- The skill never asks questions after it starts, never pushes, never edits settings, and never downgrades a Critical.

## Review Focus

- **bash 3.2 / BSD tools:** a script that works on Linux bash 5 but breaks on macOS (`timeout`, `mapfile`, GNU-only `sed`) would fail on the user's machine first. Tests run under `/bin/bash` explicitly.
- **Paths with spaces** in the repo path, the workspace path, and changed file names must not split. Pinned by tests in Tasks 1, 2, 3.
- **Destructive reset:** a `.env` pointing at a remote or non-test database must be refused *before* any reset runs. Pinned by the refusal tests in Task 5.
- **Baseline checkout leaves the user on a detached HEAD** if the session crashes mid-baseline. The skill records the branch in `state.md` before switching and restores it first on resume (Task 7).
- **Gate commands passed as strings with quotes and pipes** (`npm test -- --grep "a b"`) must run exactly as written. Pinned by a test in Task 1.

## File Structure

| File | Responsibility |
|---|---|
| `tests/lib/assert.sh` | Tiny assertion helpers for bash tests |
| `tests/run.sh` | Runs every `tests/scripts/*.test.sh` under `/bin/bash` |
| `skills/review-mine/scripts/run-gate.sh` | One gate with hard timeout; log to workspace; status line + tail |
| `skills/review-mine/scripts/workspace.sh` | Creates and prints the standalone review workspace path |
| `skills/review-mine/scripts/scope-check.sh` | Classifies changed files: in-scope / incidental / out-of-scope / forbidden |
| `skills/review-mine/scripts/review-package.sh` | Diff, files, symbols, grep-derived callers, README for critics |
| `skills/review-mine/scripts/exit-pair.sh` | Reset-safety check, then reset+prove twice, flake detection |
| `agents/final-reviewer.md` | Read-only critic (concern mode and re-review mode) |
| `agents/ticket-fixer.md` | Fix-round agent: red test first, fix, gates, commit |
| `skills/review-mine/SKILL.md` | The orchestration procedure the main session follows |
| `commands/review-mine.md` | `/review-mine` entry point |
| `scripts/validate.sh` | Extended repo checks (agents, script references, attribution) |
| `tests/fixture/setup.sh` | Builds a throwaway git repo with seeded defects |
| `tests/fixture/scope.txt` | Scope file for the fixture |
| `tests/SMOKE.md` | Manual end-to-end checklist with expected outcomes |
| `docs/superpowers/spikes/2026-10-03-phase-1a.md` | Spike results |

Ruling recorded in this plan: the spec lists scripts under `scripts/`; they live in `skills/review-mine/scripts/` instead, because an installed skill can locate files relative to its own base directory, while the plugin root is not reliably exposed to skills. `scripts/validate.sh` stays at the repo root as repo tooling.

---

### Task 0: Spike — verify Phase 1a assumptions

**Files:**
- Create: `docs/superpowers/spikes/2026-10-03-phase-1a.md`
- Create (temporary, deleted at the end of the task): `agents/spike-probe.md`, `skills/spike-probe/SKILL.md`

**Interfaces:**
- Produces: confirmed agent naming (`patrick-workflows:<agent>`), model override behavior, skill base-directory behavior, and the permission entries the README will recommend. Later tasks use these as facts.

- [ ] **Step 1: Create a probe agent and probe skill**

`agents/spike-probe.md`:
```markdown
---
name: spike-probe
description: Temporary spike agent. Reports which model it runs on and reads a file it is given.
tools: Read, Skill
model: sonnet
---

When dispatched: state the exact model ID you are running as on the first line, as `MODEL: <id>`.
If given a file path, Read it and print its first line as `READ: <line>`, or `READ-ERROR: <message>`.
If asked to load a skill, invoke it with the Skill tool and report `SKILL: loaded <name>` or `SKILL-ERROR: <message>`.
```

`skills/spike-probe/SKILL.md`:
```markdown
---
name: spike-probe
description: Temporary spike skill. Use only when explicitly asked to run the spike probe.
---

Report the base directory shown for this skill as `BASE: <path>`, then run
`bash "<base>/../../scripts/validate.sh"` and report its last line as `VALIDATE: <line>`.
```

- [ ] **Step 2: Check the dev loop (load the plugin from this checkout)**

Run: `claude --help | grep -i plugin`
Expected: a flag for loading a local plugin directory (e.g. `--plugin-dir`). Record the exact flag in the spike doc. If none exists, record that the dev loop is `/plugin marketplace add "<repo path>"` + `/plugin install patrick-workflows@patrick-workflows`, and that edits require `/plugin update` plus a restart.

- [ ] **Step 3: S1 + S6 — agent naming and model override**

Run (substitute the flag found in Step 2):
```bash
mkdir -p "$HOME/.claude/tickets/_spike" && echo "spike-ok" > "$HOME/.claude/tickets/_spike/probe.txt"
claude -p --plugin-dir "$PWD" "Dispatch the agent patrick-workflows:spike-probe twice: once with no model override, once with model opus. Give it the file $HOME/.claude/tickets/_spike/probe.txt. Print both agents' outputs verbatim."
```
Expected: two outputs; first `MODEL:` is a Sonnet ID, second is an Opus ID; both print `READ: spike-ok`. Record: the exact `subagent_type` string that worked, whether the per-dispatch model override is honored, and whether reading under `~/.claude/tickets` prompted or failed (S2).

- [ ] **Step 4: S2 — read/write under `~/.claude/tickets` in an interactive session**

In an interactive `claude` session started with the plugin, ask it to dispatch `patrick-workflows:spike-probe` on the probe file. Note any permission prompt and the exact rule Claude Code offers to save. Expected: either no prompt, or a prompt whose "always allow" rule text you record (e.g. `Read(~/.claude/tickets/**)`). That rule goes into the README in Task 9.

- [ ] **Step 5: S4 — skill base directory and script execution; S5 — agents can load skills**

Run:
```bash
claude -p --plugin-dir "$PWD" "Use the patrick-workflows:spike-probe skill. Then dispatch patrick-workflows:spike-probe and ask it to load the superpowers:test-driven-development skill."
```
Expected: `BASE:` is this repo's `skills/spike-probe` path (or the installed copy), `VALIDATE: OK: repo is valid`, and `SKILL: loaded superpowers:test-driven-development`. If the agent cannot load skills, record it: Task 6's fixer then carries the TDD rules inline in its prompt instead of loading the skill.

- [ ] **Step 6: S3 — plugin-agent frontmatter limits**

Ask the `claude-code-guide` agent (or check https://code.claude.com/docs) whether plugin agents honor `hooks`, `permissionMode`, and `mcpServers` frontmatter. Record the answer. Nothing in this plan depends on them; the record keeps later phases honest.

- [ ] **Step 7: Write the spike doc and remove the probes**

Write `docs/superpowers/spikes/2026-10-03-phase-1a.md` with one section per check (S1–S6): command run, observed output (trimmed), conclusion, and consequence for this plan. Then:
```bash
rm -f agents/spike-probe.md && rm -rf skills/spike-probe "$HOME/.claude/tickets/_spike"
./scripts/validate.sh
```
Expected: `OK: repo is valid`.

**Stop rule:** if S1 shows plugin agents cannot be dispatched by name, or the model override is ignored, stop and report before Task 1; the agent model split in Task 6/7 depends on it.

- [ ] **Step 8: Commit**
```bash
git add docs/superpowers/spikes/2026-10-03-phase-1a.md
git commit -m "docs: record phase 1a spike results"
```

---

### Task 1: Test harness and `run-gate.sh`

**Files:**
- Create: `tests/lib/assert.sh`, `tests/run.sh`, `tests/scripts/run-gate.test.sh`
- Create: `skills/review-mine/scripts/run-gate.sh`

**Interfaces:**
- Produces: `bash run-gate.sh <name> <timeout-seconds> -- "<command string>"`; requires env `REVIEW_WS`; writes `$REVIEW_WS/logs/<name>.log`; prints `GATE <name>: <pass|fail|timeout|could-not-run> (exit N, log: <path>)` then the last 30 log lines; exit 0 pass, 1 fail, 2 timeout, 3 could-not-run. Used by Tasks 5 and 7.
- Produces: `tests/lib/assert.sh` functions `assert_eq expected actual msg`, `assert_contains haystack needle msg`, `assert_not_contains haystack needle msg`, `assert_file path msg`, `finish`.

- [ ] **Step 1: Write the test helpers**

`tests/lib/assert.sh`:
```bash
#!/usr/bin/env bash
# Minimal assertion helpers for bash tests. Source this file, call finish at the end.
TESTS_RUN=0
TESTS_FAILED=0
_ok() { TESTS_RUN=$((TESTS_RUN + 1)); }
_ko() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1"; }
assert_eq() { if [ "$1" = "$2" ]; then _ok; else _ko "$3 (expected [$1], got [$2])"; fi; }
assert_contains() { case "$1" in *"$2"*) _ok ;; *) _ko "$3 (missing [$2])"; echo "--- output was:"; echo "$1"; echo "---" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) _ko "$3 (unexpected [$2])" ;; *) _ok ;; esac; }
assert_file() { if [ -f "$1" ]; then _ok; else _ko "$2 (no file: $1)"; fi; }
finish() { echo "$TESTS_RUN checks, $TESTS_FAILED failed"; [ "$TESTS_FAILED" -eq 0 ]; }
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
# Runs every tests/scripts/*.test.sh with macOS's /bin/bash (3.2) to catch bash-5-only code.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
for t in "$ROOT"/tests/scripts/*.test.sh; do
  [ -e "$t" ] || continue
  echo "== $(basename "$t")"
  /bin/bash "$t" || status=1
done
exit "$status"
```

- [ ] **Step 2: Write the failing test**

`tests/scripts/run-gate.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
GATE="$ROOT/skills/review-mine/scripts/run-gate.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export REVIEW_WS="$tmp/work space"   # deliberately contains a space

out=$(bash "$GATE" ok 5 -- "echo hello"); code=$?
assert_eq 0 "$code" "pass exits 0"
assert_contains "$out" "GATE ok: pass" "pass status line"
assert_contains "$(cat "$REVIEW_WS/logs/ok.log")" "hello" "log captured"

out=$(bash "$GATE" bad 5 -- "echo nope; exit 3"); code=$?
assert_eq 1 "$code" "fail exits 1"
assert_contains "$out" "GATE bad: fail (exit 3" "fail status line"

out=$(bash "$GATE" missing 5 -- "definitely-not-a-command-xyz"); code=$?
assert_eq 3 "$code" "missing command exits 3"
assert_contains "$out" "could-not-run" "missing command status"

start=$(date +%s)
out=$(bash "$GATE" slow 1 -- "sleep 20"); code=$?
elapsed=$(( $(date +%s) - start ))
assert_eq 2 "$code" "timeout exits 2"
assert_contains "$out" "GATE slow: timeout" "timeout status"
[ "$elapsed" -lt 6 ] && _ok || _ko "timeout took ${elapsed}s"

out=$(bash "$GATE" many 5 -- 'for i in $(seq 1 100); do printf "L-%03d\n" "$i"; done')
assert_contains "$out" "L-100" "tail shows last line"
assert_contains "$out" "L-071" "tail shows 30 lines"
assert_not_contains "$out" "L-070" "tail stops at 30 lines"

out=$(bash "$GATE" quoted 5 -- 'printf "%s|" "a b" c | tr "|" "\n" | grep -c .'); code=$?
assert_eq 0 "$code" "quoted command passes"
assert_contains "$(cat "$REVIEW_WS/logs/quoted.log")" "2" "quotes and pipes preserved"

out=$(REVIEW_WS= bash "$GATE" nows 5 -- "true"); code=$?
assert_eq 3 "$code" "missing REVIEW_WS is could-not-run"

finish
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: `FAIL:` lines (script missing, so exit codes are 127) and a non-zero exit.

- [ ] **Step 4: Implement `run-gate.sh`**

`skills/review-mine/scripts/run-gate.sh`:
```bash
#!/usr/bin/env bash
# Run one gate command with a hard timeout.
# Usage: run-gate.sh <name> <timeout-seconds> -- "<command string>"
# Full output goes to $REVIEW_WS/logs/<name>.log; stdout gets one status line plus the last 30 lines.
# Exit codes: 0 pass, 1 fail, 2 timeout, 3 could-not-run.
set -u
if [ $# -lt 4 ] || [ "$3" != "--" ]; then
  echo "usage: run-gate.sh <name> <timeout-seconds> -- \"<command>\"" >&2
  exit 3
fi
name=$1; limit=$2; cmd=$4
ws=${REVIEW_WS:-}
[ -n "$ws" ] || { echo "GATE $name: could-not-run (REVIEW_WS not set)"; exit 3; }
mkdir -p "$ws/logs" || { echo "GATE $name: could-not-run (cannot create $ws/logs)"; exit 3; }
log="$ws/logs/$name.log"

# Own process group, so a timeout kills the whole tree (npm -> node -> workers).
perl -e 'setpgrp(0, 0); exec @ARGV' bash -c "$cmd" >"$log" 2>&1 &
pid=$!
ticks=0; max=$((limit * 5)); status=""
while kill -0 "$pid" 2>/dev/null; do
  if [ "$ticks" -ge "$max" ]; then
    kill -TERM -- "-$pid" 2>/dev/null
    sleep 1
    kill -KILL -- "-$pid" 2>/dev/null
    status=timeout
    break
  fi
  sleep 0.2
  ticks=$((ticks + 1))
done
wait "$pid" 2>/dev/null
code=$?
if [ -z "$status" ]; then
  case $code in
    0) status=pass ;;
    126|127) status=could-not-run ;;
    *) status=fail ;;
  esac
fi
echo "GATE $name: $status (exit $code, log: $log)"
tail -n 30 "$log"
case $status in
  pass) exit 0 ;;
  fail) exit 1 ;;
  timeout) exit 2 ;;
  *) exit 3 ;;
esac
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh`
Expected: `== run-gate.test.sh`, then `16 checks, 0 failed`, exit 0.

- [ ] **Step 6: Commit**
```bash
git add tests/lib/assert.sh tests/run.sh tests/scripts/run-gate.test.sh skills/review-mine/scripts/run-gate.sh
git commit -m "feat: add run-gate script with timeout and log capture"
```

---

### Task 2: `workspace.sh`

**Files:**
- Create: `tests/scripts/workspace.test.sh`, `skills/review-mine/scripts/workspace.sh`

**Interfaces:**
- Produces: `bash workspace.sh` (run inside a git repo) → creates the directory (with `logs/`) and prints its absolute path on stdout; exit 1 outside a git repo. Honors `TICKETS_HOME`. Used by Task 7.

- [ ] **Step 1: Write the failing test**

`tests/scripts/workspace.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
WS="$ROOT/skills/review-mine/scripts/workspace.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets home"

repo="$tmp/My Repo"; mkdir -p "$repo"; cd "$repo" || exit 1
git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git checkout -q -b feat/abc-1

out=$(bash "$WS"); code=$?
assert_eq 0 "$code" "exits 0 in a repo"
case "$out" in "$TICKETS_HOME/My-Repo/_reviews/feat-abc-1-"*) _ok ;; *) _ko "path shape: $out" ;; esac
[ -d "$out/logs" ] && _ok || _ko "logs dir created"

git remote add origin "git@github.com:me/shop-app.git"
out=$(bash "$WS")
case "$out" in "$TICKETS_HOME/shop-app/_reviews/"*) _ok ;; *) _ko "slug from remote: $out" ;; esac

git checkout -q --detach
out=$(bash "$WS")
case "$out" in *"/_reviews/detached-"*) _ok ;; *) _ko "detached head: $out" ;; esac

a=$(bash "$WS"); b=$(bash "$WS")
[ "$a" != "$b" ] && _ok || _ko "two calls in the same second get distinct dirs"

cd "$tmp" || exit 1
bash "$WS" >/dev/null 2>&1; code=$?
assert_eq 1 "$code" "outside a repo exits 1"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: `workspace.test.sh` reports failures.

- [ ] **Step 3: Implement**

`skills/review-mine/scripts/workspace.sh`:
```bash
#!/usr/bin/env bash
# Create a standalone review workspace and print its path.
# Location: ${TICKETS_HOME:-~/.claude/tickets}/<repo-slug>/_reviews/<branch>-<UTC timestamp>
set -u
root=${TICKETS_HOME:-$HOME/.claude/tickets}
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repository" >&2; exit 1; }
url=$(git config --get remote.origin.url 2>/dev/null || true)
if [ -n "$url" ]; then slug=$(basename "$url" .git); else slug=$(basename "$top"); fi
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "HEAD" ] && branch="detached-$(git rev-parse --short HEAD)"
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
dir="$root/$(safe "$slug")/_reviews/$(safe "$branch")-$(date -u +%Y%m%dT%H%M%SZ)"
n=1; candidate=$dir
while [ -e "$candidate" ]; do n=$((n + 1)); candidate="$dir-$n"; done
mkdir -p "$candidate/logs" || exit 1
printf '%s\n' "$candidate"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: both test files report `0 failed`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/workspace.test.sh skills/review-mine/scripts/workspace.sh
git commit -m "feat: add review workspace script"
```

---

### Task 3: `scope-check.sh`

**Files:**
- Create: `tests/scripts/scope-check.test.sh`, `skills/review-mine/scripts/scope-check.sh`

**Interfaces:**
- Produces: `bash scope-check.sh <base> [scope-file]` → one `<class>\t<file>` line per file changed in `<base>..HEAD`; classes `in-scope`, `incidental`, `out-of-scope`, `forbidden`; exit 1 if any forbidden, 2 on bad input, else 0. Scope file lines: `allow: <glob>` / `forbid: <glob>`, `#` comments, `**` behaves like `*`. No allow lines → every non-forbidden file is in-scope. Used by Task 7.

- [ ] **Step 1: Write the failing test**

`tests/scripts/scope-check.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SC="$ROOT/skills/review-mine/scripts/scope-check.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main
mkdir -p src/billing docs
echo a > src/a.js; echo r > src/billing/rates.js; echo d > docs/x.md
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
base=$(git rev-parse HEAD)

printf '# scope\nallow: src/**\nforbid: src/billing/**\n' > "$tmp/scope.txt"

echo b >> src/a.js; echo '{}' > package-lock.json; echo y >> docs/x.md; echo z > "src/my file.js"
mkdir -p src/__snapshots__ && echo s > src/__snapshots__/a.snap
git add -A && git -c user.name=t -c user.email=t@t commit -q -m change
out=$(bash "$SC" "$base" "$tmp/scope.txt"); code=$?
assert_eq 0 "$code" "no forbidden file exits 0"
assert_contains "$out" "$(printf 'in-scope\tsrc/a.js')" "allow match"
assert_contains "$out" "$(printf 'in-scope\tsrc/my file.js')" "file name with space"
assert_contains "$out" "$(printf 'incidental\tpackage-lock.json')" "lockfile incidental"
assert_contains "$out" "$(printf 'incidental\tsrc/__snapshots__/a.snap')" "snapshot incidental"
assert_contains "$out" "$(printf 'out-of-scope\tdocs/x.md')" "outside allow"

echo r2 >> src/billing/rates.js
git add -A && git -c user.name=t -c user.email=t@t commit -q -m billing
out=$(bash "$SC" "$base" "$tmp/scope.txt"); code=$?
assert_eq 1 "$code" "forbidden file exits 1"
assert_contains "$out" "$(printf 'forbidden\tsrc/billing/rates.js')" "forbid beats allow"

out=$(bash "$SC" "$base"); code=$?
assert_eq 0 "$code" "no scope file: nothing forbidden"
assert_contains "$out" "$(printf 'in-scope\tdocs/x.md')" "no allow lines: all in-scope"

bash "$SC" "$base" "$tmp/nope.txt" >/dev/null 2>&1; code=$?
assert_eq 2 "$code" "missing scope file exits 2"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: `scope-check.test.sh` reports failures.

- [ ] **Step 3: Implement**

`skills/review-mine/scripts/scope-check.sh`:
```bash
#!/usr/bin/env bash
# Classify files changed between <base> and HEAD against a scope file.
# Usage: scope-check.sh <base> [scope-file]
# Scope lines: "allow: <glob>" or "forbid: <glob>"; "**" works like "*"; "#" starts a comment.
# Prints "<class>\t<file>"; classes: in-scope, incidental, out-of-scope, forbidden.
# Exit: 0 ok, 1 a forbidden file changed, 2 bad input.
set -u
set -f   # patterns are matched against names, never expanded against the filesystem
base=${1:-}
[ -n "$base" ] || { echo "usage: scope-check.sh <base> [scope-file]" >&2; exit 2; }
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "unknown base: $base" >&2; exit 2; }
scope=${2:-}
allow=""; forbid=""
trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }
if [ -n "$scope" ]; then
  [ -f "$scope" ] || { echo "scope file not found: $scope" >&2; exit 2; }
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    case $line in
      allow:*) allow="$allow
$(trim "${line#allow:}")" ;;
      forbid:*) forbid="$forbid
$(trim "${line#forbid:}")" ;;
    esac
  done < "$scope"
fi

INCIDENTAL_NAMES='package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb Cargo.lock poetry.lock uv.lock Pipfile.lock Gemfile.lock composer.lock go.sum package.json pyproject.toml go.mod Cargo.toml index.ts index.tsx index.js index.mjs *.snap'
INCIDENTAL_PATHS='*__snapshots__/* */generated/* *.generated.* *.gen.*'

matches() {   # $1 file, $2 newline-separated patterns
  local f=$1 p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p=${p//\*\*/*}
    [[ $f == $p ]] && return 0
  done <<EOF
$2
EOF
  return 1
}
incidental() {
  local f=$1 b p
  b=$(basename "$f")
  for p in $INCIDENTAL_NAMES; do [[ $b == $p ]] && return 0; done
  for p in $INCIDENTAL_PATHS; do [[ $f == $p ]] && return 0; done
  return 1
}

status=0
while IFS= read -r -d '' f; do
  if matches "$f" "$forbid"; then class=forbidden; status=1
  elif [ -z "$(trim "$allow")" ] || matches "$f" "$allow"; then class=in-scope
  elif incidental "$f"; then class=incidental
  else class=out-of-scope
  fi
  printf '%s\t%s\n' "$class" "$f"
done < <(git diff --name-only -z "$base" HEAD)
exit "$status"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: all test files report `0 failed`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/scope-check.test.sh skills/review-mine/scripts/scope-check.sh
git commit -m "feat: add scope-check script with incidental file classes"
```

---

### Task 4: `review-package.sh`

**Files:**
- Create: `tests/scripts/review-package.test.sh`, `skills/review-mine/scripts/review-package.sh`

**Interfaces:**
- Produces: `bash review-package.sh <base> <head> <out-dir>` → writes `diff.patch`, `files.txt`, `symbols.txt` (one name per line), `callers.txt` (`## <symbol>` sections of `git grep` hits at `<head>`, max 20 each), `README.txt`; exit 1 on unknown revision. Used by Task 7 for round 1 (`base..HEAD`) and re-reviews (`<pre-fix>..HEAD`).

- [ ] **Step 1: Write the failing test**

`tests/scripts/review-package.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
RP="$ROOT/skills/review-mine/scripts/review-package.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main
mkdir -p src
cat > src/cart.js <<'EOF'
function total(items) {
  return items.length;
}
module.exports = { total };
EOF
cat > src/checkout.js <<'EOF'
const { total } = require('./cart');
function checkout(items) { return total(items); }
EOF
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
base=$(git rev-parse HEAD)
cat > src/cart.js <<'EOF'
function total(items) {
  return items.reduce((s, i) => s + i.price, 0);
}
class Cart {}
const discountRate = 0.1;
module.exports = { total, Cart, discountRate };
EOF
git add -A && git -c user.name=t -c user.email=t@t commit -q -m change

out="$tmp/pkg dir"
bash "$RP" "$base" HEAD "$out"; code=$?
assert_eq 0 "$code" "exits 0"
assert_contains "$(cat "$out/files.txt")" "src/cart.js" "files listed"
syms=$(cat "$out/symbols.txt")
assert_contains "$syms" "total" "modified function from hunk header"
assert_contains "$syms" "Cart" "added class"
assert_contains "$syms" "discountRate" "added const"
assert_contains "$(cat "$out/callers.txt")" "src/checkout.js" "caller in another file found"
assert_contains "$(cat "$out/README.txt")" "starting point" "README warns it is not the boundary"
assert_file "$out/diff.patch" "diff written"

bash "$RP" "$base" "$base" "$tmp/empty"; code=$?
assert_eq 0 "$code" "empty diff ok"
assert_eq "" "$(cat "$tmp/empty/files.txt")" "empty diff lists no files"

bash "$RP" not-a-rev HEAD "$tmp/x" 2>/dev/null; code=$?
assert_eq 1 "$code" "unknown revision exits 1"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: `review-package.test.sh` reports failures.

- [ ] **Step 3: Implement**

`skills/review-mine/scripts/review-package.sh`:
```bash
#!/usr/bin/env bash
# Build a review package for critics.
# Usage: review-package.sh <base> <head> <out-dir>
# Writes diff.patch, files.txt, symbols.txt, callers.txt, README.txt.
set -u
base=${1:-}; head=${2:-}; out=${3:-}
[ -n "$base" ] && [ -n "$head" ] && [ -n "$out" ] || { echo "usage: review-package.sh <base> <head> <out-dir>" >&2; exit 1; }
for r in "$base" "$head"; do
  git rev-parse --verify -q "$r^{commit}" >/dev/null || { echo "unknown revision: $r" >&2; exit 1; }
done
mkdir -p "$out" || exit 1
git diff "$base" "$head" > "$out/diff.patch"
git diff --name-only "$base" "$head" > "$out/files.txt"

KW='(function|class|def|interface|type|enum|struct|trait|fn|func)'
{
  # Names declared on changed lines, and the enclosing function from hunk headers.
  git diff -U0 "$base" "$head" | grep -E '^(@@|[+-])' | grep -vE '^(\+\+\+|---) ' |
    sed -nE "s/.*(^|[^A-Za-z0-9_])$KW[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p"
  git diff -U0 "$base" "$head" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' |
    sed -nE 's/.*(^|[^A-Za-z0-9_])(const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\3/p'
} | awk 'length($0) >= 3' | sort -u > "$out/symbols.txt"

: > "$out/callers.txt"
while IFS= read -r sym; do
  hits=$(git grep -n -w -F -e "$sym" "$head" -- . 2>/dev/null | head -n 21)
  [ -n "$hits" ] || continue
  n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
  {
    echo "## $sym"
    printf '%s\n' "$hits" | head -n 20
    [ "$n" -gt 20 ] && echo "... (truncated at 20 hits)"
    echo
  } >> "$out/callers.txt"
done < "$out/symbols.txt"

cat > "$out/README.txt" <<'EOF'
This package is a starting point, not the boundary of the review.
- diff.patch / files.txt: what changed.
- symbols.txt: names declared or modified in the change (heuristic).
- callers.txt: plain-text references to those names, found with git grep.
Text search misses: dependency injection, dynamic dispatch, string-keyed routes
and event names, framework conventions (route files, ORM schemas, config-driven
wiring), reflection, and generated code. Use Grep and Glob to look beyond this
package wherever the change could have effects it does not show.
EOF
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: all test files report `0 failed`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/review-package.test.sh skills/review-mine/scripts/review-package.sh
git commit -m "feat: add review-package script for critics"
```

---

### Task 5: `exit-pair.sh` with reset safety and flake detection

**Files:**
- Create: `tests/scripts/exit-pair.test.sh`, `skills/review-mine/scripts/exit-pair.sh`

**Interfaces:**
- Consumes: `run-gate.sh` (Task 1), located next to this script.
- Produces: `bash exit-pair.sh --prove "<cmd>" [--reset "<cmd>" --env-file <path> --db-pattern <ERE> [--db-var NAME] [--allow-remote]] [--timeout SECONDS]`; requires `REVIEW_WS`; prints one `EXIT-PAIR: <pass|pass, flake seen|fail|flaky|refused|could-not-run> (...)` line; exit 0 pass, 1 fail, 3 could-not-run, 4 refused, 5 flaky. Logs `$REVIEW_WS/logs/exit-pair-<run>-<reset|prove>.log`. Used by Task 7.

- [ ] **Step 1: Write the failing test**

`tests/scripts/exit-pair.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
EP="$ROOT/skills/review-mine/scripts/exit-pair.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export REVIEW_WS="$tmp/ws"
cd "$tmp" || exit 1

# prove pops the next exit code from $tmp/seq
cat > "$tmp/next.sh" <<'EOF'
seq="$1"; code=$(head -n 1 "$seq"); tail -n +2 "$seq" > "$seq.tmp" && mv "$seq.tmp" "$seq"; exit "${code:-1}"
EOF
run() { printf '%s\n' $1 > "$tmp/seq"; shift; bash "$EP" --prove "bash '$tmp/next.sh' '$tmp/seq'" "$@"; }

out=$(run "0 0"); assert_eq 0 $? "pass pass"; assert_contains "$out" "EXIT-PAIR: pass" "pass line"
out=$(run "1 1"); assert_eq 1 $? "fail fail"; assert_contains "$out" "EXIT-PAIR: fail" "fail line"
out=$(run "0 1 0 0"); assert_eq 0 $? "flake then two passes"; assert_contains "$out" "flake seen" "flake noted"
out=$(run "0 1 0 1"); assert_eq 5 $? "still inconsistent"; assert_contains "$out" "EXIT-PAIR: flaky" "flaky line"

# reset safety: refusals happen before any reset runs
reset_cmd="echo reset >> '$tmp/reset.marker'"
printf 'export DATABASE_URL="postgres://u:secret@prod.example.com:5432/app_test"\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "$reset_cmd" --env-file "$tmp/.env.test" --db-pattern '_test$'); code=$?
assert_eq 4 "$code" "remote host refused"
assert_contains "$out" "is not local" "remote reason"
assert_not_contains "$out" "secret" "password never printed"
[ -f "$tmp/reset.marker" ] && _ko "reset ran despite refusal" || _ok

printf 'DATABASE_URL=postgres://localhost:5432/app_dev\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "$reset_cmd" --env-file "$tmp/.env.test" --db-pattern '_test$'); assert_eq 4 $? "pattern mismatch refused"

out=$(run "0 0" --reset "$reset_cmd" --db-pattern '_test$'); assert_eq 4 $? "reset without env file refused"
out=$(run "0 0" --reset "$reset_cmd" --env-file "$tmp/.env.test"); assert_eq 4 $? "reset without pattern refused"

printf "DATABASE_URL='postgres://localhost:5432/app_test'\n" > "$tmp/.env.test"
out=$(run "0 0" --reset "$reset_cmd" --env-file "$tmp/.env.test" --db-pattern '_test$'); code=$?
assert_eq 0 "$code" "local test db accepted"
assert_eq 2 "$(wc -l < "$tmp/reset.marker" | tr -d ' ')" "reset ran before each of two runs"

printf 'DATABASE_URL=postgres://u:p@db.ci.internal/app_test\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "true" --env-file "$tmp/.env.test" --db-pattern '_test$' --allow-remote); assert_eq 0 $? "allow-remote overrides host check"

printf 'DATABASE_URL=file:./test.db\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "true" --env-file "$tmp/.env.test" --db-pattern 'test\.db$'); assert_eq 0 $? "file database treated as local"

out=$(bash "$EP" --reset "true"); assert_eq 3 $? "missing --prove is could-not-run"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: `exit-pair.test.sh` reports failures.

- [ ] **Step 3: Implement**

`skills/review-mine/scripts/exit-pair.sh`:
```bash
#!/usr/bin/env bash
# Prove a feature twice in a row, resetting state before each run.
# Usage: exit-pair.sh --prove "<cmd>" [--reset "<cmd>" --env-file <path> --db-pattern <ERE>
#                     [--db-var NAME] [--allow-remote]] [--timeout SECONDS]
# Needs REVIEW_WS. Prints one "EXIT-PAIR: <result> (...)" line.
# Exit: 0 pass, 1 fail, 3 could-not-run, 4 refused (reset target not proven disposable), 5 flaky.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prove=""; reset=""; envfile=""; pattern=""; dbvar=DATABASE_URL; remote=no; limit=900
while [ $# -gt 0 ]; do
  case $1 in
    --prove) prove=${2:-}; shift 2 ;;
    --reset) reset=${2:-}; shift 2 ;;
    --env-file) envfile=${2:-}; shift 2 ;;
    --db-pattern) pattern=${2:-}; shift 2 ;;
    --db-var) dbvar=${2:-}; shift 2 ;;
    --allow-remote) remote=yes; shift ;;
    --timeout) limit=${2:-}; shift 2 ;;
    *) echo "EXIT-PAIR: could-not-run (unknown option $1)"; exit 3 ;;
  esac
done
[ -n "$prove" ] || { echo "EXIT-PAIR: could-not-run (--prove is required)"; exit 3; }
[ -n "${REVIEW_WS:-}" ] || { echo "EXIT-PAIR: could-not-run (REVIEW_WS not set)"; exit 3; }
refuse() { echo "EXIT-PAIR: refused ($1)"; exit 4; }

# Value of NAME in an env file, read as text (the file is not executed here).
env_value() {
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$2[[:space:]]*=[[:space:]]*(.*)$/\2/p" "$1" | tail -n 1 |
    sed -E "s/^['\"]//; s/['\"][[:space:]]*$//"
}

if [ -n "$reset" ]; then
  [ -n "$envfile" ] || refuse "--reset needs --env-file"
  [ -f "$envfile" ] || refuse "env file not found: $envfile"
  [ -n "$pattern" ] || refuse "--reset needs --db-pattern"
  url=$(env_value "$envfile" "$dbvar")
  [ -n "$url" ] || refuse "$dbvar is not set in $envfile"
  printf '%s' "$url" | grep -Eq -- "$pattern" || refuse "$dbvar does not match the disposable pattern"
  case $url in
    *://*) host=$(printf '%s' "$url" | sed -E 's#^[A-Za-z0-9+.-]+://([^@/]*@)?(\[[^]]*\]|[^:/?]*).*#\2#') ;;
    *) host=localhost ;;   # file paths and sqlite-style URLs have no network host
  esac
  if [ "$remote" = no ]; then
    case $host in
      localhost|127.0.0.1|"[::1]"|"") ;;
      *) refuse "$dbvar host '$host' is not local; pass --allow-remote to override" ;;
    esac
  fi
fi

with_env() {   # wrap a command so it loads the env file first, when one was given
  if [ -n "$envfile" ]; then
    printf 'set -a; . %s; set +a; %s' "$(printf '%q' "$envfile")" "$1"
  else
    printf '%s' "$1"
  fi
}
run_once() {   # $1 run number; prints pass, fail or could-not-run
  if [ -n "$reset" ]; then
    bash "$here/run-gate.sh" "exit-pair-$1-reset" "$limit" -- "$(with_env "$reset")" >/dev/null
    [ $? -eq 0 ] || { echo could-not-run; return; }
  fi
  bash "$here/run-gate.sh" "exit-pair-$1-prove" "$limit" -- "$(with_env "$prove")" >/dev/null
  case $? in 0) echo pass ;; 3) echo could-not-run ;; *) echo fail ;; esac
}
report() { echo "EXIT-PAIR: $1 (runs: $2; logs: $REVIEW_WS/logs/exit-pair-*)"; }

r1=$(run_once 1); r2=$(run_once 2)
case "$r1 $r2" in *could-not-run*) report could-not-run "$r1 $r2"; exit 3 ;; esac
if [ "$r1" = "$r2" ]; then
  if [ "$r1" = pass ]; then report pass "$r1 $r2"; exit 0; fi
  report fail "$r1 $r2"; exit 1
fi
# Same commit, different results: one more pair before calling it flaky.
r3=$(run_once 3); r4=$(run_once 4)
runs="$r1 $r2 $r3 $r4"
case "$r3 $r4" in *could-not-run*) report could-not-run "$runs"; exit 3 ;; esac
if [ "$r3" = pass ] && [ "$r4" = pass ]; then report "pass, flake seen" "$runs"; exit 0; fi
if [ "$r3" = fail ] && [ "$r4" = fail ]; then report fail "$runs"; exit 1; fi
report flaky "$runs"; exit 5
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: all test files report `0 failed`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/exit-pair.test.sh skills/review-mine/scripts/exit-pair.sh
git commit -m "feat: add exit-pair script with reset safety and flake detection"
```

---

### Task 6: Agents and stronger `validate.sh`

**Files:**
- Create: `agents/final-reviewer.md`, `agents/ticket-fixer.md`, `tests/scripts/validate.test.sh`
- Modify: `scripts/validate.sh` (append checks before the final `OK` line)

**Interfaces:**
- Produces: agents dispatched as `patrick-workflows:final-reviewer` and `patrick-workflows:ticket-fixer` (confirm the exact name in the Task 0 spike doc). Their output formats below are the contract Task 7's skill parses.
- Produces: `validate.sh` fails when an agent lacks `tools:`/`model:`, when `final-reviewer` has write-capable tools, when a skill references a missing `scripts/*.sh` next to it, or when any file carries a tool-attribution string.

- [ ] **Step 1: Write the failing validate test**

`tests/scripts/validate.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fresh() { rm -rf "$tmp/repo"; mkdir -p "$tmp/repo"; (cd "$ROOT" && tar --exclude=.git -cf - .) | (cd "$tmp/repo" && tar -xf -); }
check() { bash "$tmp/repo/scripts/validate.sh" 2>&1; }

fresh; out=$(check); assert_eq 0 $? "clean copy validates"

fresh; sed -i.bak '/^model:/d' "$tmp/repo/agents/ticket-fixer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "no model in frontmatter: agents/ticket-fixer.md" "agent without model"

fresh; sed -i.bak 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Bash/' "$tmp/repo/agents/final-reviewer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "read-only agent has write tools" "critic with Bash"

fresh; echo 'Run `bash "$SKILL_DIR/scripts/nope.sh"`.' >> "$tmp/repo/skills/review-mine/SKILL.md"
out=$(check); assert_contains "$out" "missing script scripts/nope.sh" "missing referenced script"

fresh; printf 'x\n\nCo-%s: Claude Test <t@example.com>\n' "Authored-By" > "$tmp/repo/notes.txt"
out=$(check); assert_contains "$out" "attribution string in ./notes.txt" "attribution trailer caught"

finish
```

Note: Task 7 creates `skills/review-mine/SKILL.md`. Until then this test's third case cannot run; run the full test after Task 7 (Step 5 of Task 7 re-runs it).

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: `validate.test.sh` reports failures (agents missing, checks missing).

- [ ] **Step 3: Write `agents/final-reviewer.md`**

````markdown
---
name: final-reviewer
description: Fresh, read-only critic for the review-mine loop. Reviews a review package for one concern (impact, security+regression, requirements+maintainability, combined) or re-reviews a fix round. Returns evidenced findings and, when asked, a PASS/FAIL verdict. Never edits files.
tools: Read, Grep, Glob
model: sonnet
---

You are a critic in a builder/critic review loop. You did not write this code and you will not fix it. You cannot run commands; every finding you report is a hypothesis that someone else will try to reproduce with a failing test.

## Inputs (given in your dispatch)
- `MODE`: `review` or `re-review`
- `CONCERN` (review mode): `impact`, `security+regression`, `requirements+maintainability`, or `combined` (all of them)
- `PACKAGE`: a directory with `diff.patch`, `files.txt`, `symbols.txt`, `callers.txt`, `README.txt`
- `BAR`: a file with the acceptance criteria the change must meet
- `GATES`: a file summarizing gate results against the baseline (known reds are listed and are not your concern)
- `VERDICT_REQUIRED`: `yes` or `no`
- Re-review only: `FINDINGS`: a file listing finding IDs and titles that a fix round addressed

## How to review
1. Read `README.txt` first. The package is a starting point, not the boundary. Use Grep and Glob to follow the change wherever it can have effects: callers, dependency injection, string-keyed routes and events, framework conventions, config.
2. Read the diff in full, then the code around it.
3. Concerns:
   - `impact`: what else depends on the changed code, and does it still work?
   - `security+regression`: injection, authentication and authorization, secrets, unsafe input handling, unsafe deserialization; existing behavior that changed, tests that were weakened or removed.
   - `requirements+maintainability`: does the change meet every item in `BAR`, proven by tests or other evidence in the package? Duplication, dead code, naming that misleads, conventions of the surrounding code.
4. Severity:
   - **Critical**: data loss or corruption, a security hole, a crash or wrong result on a main path, an acceptance criterion not met.
   - **Important**: wrong behavior on an edge or secondary path, missing validation, a likely regression.
   - **Minor**: everything else worth mentioning.

## Evidence rule
Report a finding only if you can fill every field. A finding without a concrete trigger and expected-versus-actual is dropped by the orchestrator, so do not send it.

## Output format (your final message, exactly this shape)
```
VERDICT: PASS | FAIL | n/a
VERDICT-REASON: <one line; for FAIL name the unmet criterion or open finding>
FINDINGS:
N1 — <short title>
Severity: Critical | Important | Minor
Kind: behavioral | structural
Location: <path>:<line>
Trigger: <input or condition>
Expected: <what should happen>
Actual: <what the code does>
(repeat for N2, N3 ... or write "none")
```
`VERDICT` is `n/a` unless `VERDICT_REQUIRED: yes`. PASS means: every item in `BAR` is proven by evidence in the package or the code, no open Critical finding, and no open Important finding except those listed as deferred in `BAR`. Absence of findings alone is not a PASS.

## Re-review mode
For each ID in `FINDINGS`, add one line before `FINDINGS:` in your output:
```
F1-2: ADDRESSED | NOT ADDRESSED [NEW-TRIGGER: <a different input that still fails>]
```
A behavioral finding whose new test now passes counts as addressed unless you give a NEW-TRIGGER. Also review the fix diff for anything the fix itself broke, including callers outside the changed files, and report those as new findings.
````

- [ ] **Step 4: Write `agents/ticket-fixer.md`**

````markdown
---
name: ticket-fixer
description: Fix-round agent for review-mine. Takes evidenced findings, writes a failing test for each behavioral finding before fixing it, runs the gates, and commits locally. Marks findings it cannot reproduce as unreproduced instead of guessing.
tools: Read, Write, Edit, Bash, Grep, Glob, Skill
model: sonnet
---

You fix findings from a review. Load the `superpowers:test-driven-development` skill before you start. (If the skill tool is unavailable, follow its core rule anyway: no production change without a test that failed first.)

## Inputs (given in your dispatch)
- `FINDINGS`: a file of findings (ID, severity, kind, location, trigger, expected, actual)
- `GATES`: the exact gate command lines to run, each as `bash <run-gate.sh> <name> <timeout> -- "<command>"`
- `SCOPE` (optional): a scope file; never change files matching its `forbid:` lines except to revert a forbidden change a finding asks you to undo
- `REPORT`: the file path to write your report to

## For each finding, in order of severity
- **Behavioral:** write a test that reproduces the trigger and fails for the stated reason. Run it and confirm it fails. Then fix the code and confirm it passes. If you cannot make a test fail for the stated reason after a genuine attempt, do not change the code: mark it `UNREPRODUCED` and say what you tried.
- **Structural:** make the change directly; no test is required.
- Keep changes minimal and inside the finding's scope.

## Afterwards
1. Run every gate line in `GATES`.
2. Commit locally: `git add <files>` then `git commit -m "fix: address <IDs>"`. Plain message, no trailers. Never push.
3. Write `REPORT` and end your final message with the same content:
```
F1-2: FIXED red: <test name> (failed: <one-line failure>) green: pass
F1-3: FIXED-STRUCTURAL
F1-4: UNREPRODUCED tried: <what you tried>
GATES: <name> <status>, <name> <status>
COMMIT: <sha or "none">
```
````

- [ ] **Step 5: Extend `scripts/validate.sh`**

Insert before the line `[ "$fail" -eq 0 ] && echo "OK: repo is valid"`:
```bash
# Agents declare their tools and model.
fm() { sed -n '2,/^---$/p' "$1"; }
for f in agents/*.md; do
  [ -e "$f" ] || continue
  fm "$f" | grep -q '^tools:' || bad "no tools in frontmatter: $f"
  fm "$f" | grep -q '^model:' || bad "no model in frontmatter: $f"
done

# Read-only agents must not be able to change anything.
for f in agents/final-reviewer.md; do
  [ -f "$f" ] || continue
  fm "$f" | grep '^tools:' | grep -Eq '(Write|Edit|Bash|NotebookEdit)' && bad "read-only agent has write tools: $f"
done

# Scripts a skill references must exist next to it.
for f in skills/*/SKILL.md; do
  [ -e "$f" ] || continue
  d=$(dirname "$f")
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ -f "$d/$s" ] || bad "missing script $s referenced by $f"
  done <<EOF
$(grep -oE 'scripts/[A-Za-z0-9_-]+\.sh' "$f" | sort -u)
EOF
done

# No tool attribution anywhere (patterns are split so this file does not match itself).
attr1='Co-''Authored-By: Claude'
attr2='Generated with \[Claude'' Code\]'
while IFS= read -r f; do
  [ -n "$f" ] && bad "attribution string in $f"
done <<EOF
$(grep -rIlE --exclude-dir=.git -e "$attr1" -e "$attr2" . 2>/dev/null)
EOF
```

- [ ] **Step 6: Run validate and the tests**

Run: `./scripts/validate.sh && bash tests/run.sh`
Expected: `OK: repo is valid`. `validate.test.sh` passes every case except "missing referenced script", which fails until Task 7 adds the skill; every other test file reports `0 failed`.

- [ ] **Step 7: Commit**
```bash
git add agents/final-reviewer.md agents/ticket-fixer.md scripts/validate.sh tests/scripts/validate.test.sh
git commit -m "feat: add final-reviewer and ticket-fixer agents with validation checks"
```

---

### Task 7: The `review-mine` skill and `/review-mine` command

**Files:**
- Create: `skills/review-mine/SKILL.md`, `commands/review-mine.md`

**Interfaces:**
- Consumes: all scripts (Tasks 1–5) via `bash "$SKILL_DIR/scripts/<name>.sh"`; agents (Task 6) by the names confirmed in the spike.
- Produces: `/review-mine [base] [--depth lite|standard] [--criteria <file>] [--scope <file>] [--no-fix] [--prove "<cmd>" [--reset "<cmd>" --env-file <f> --db-pattern <ERE> [--allow-remote]]]`; a workspace with `state.md`, `ledger.md`, `bar.md`, `baseline.md`, `logs/`, `review/round-N/`, `report.md`; a summary printed to the user.

- [ ] **Step 1: Write `commands/review-mine.md`**

```markdown
---
description: Review the current branch with fresh critics, evidence-checked findings, test-proven fix rounds and an explicit PASS verdict
argument-hint: "[base] [--depth lite|standard] [--criteria <file>] [--scope <file>] [--no-fix] [--prove \"<cmd>\" [--reset \"<cmd>\" --env-file <file> --db-pattern <regex>]]"
---

Use the `patrick-workflows:review-mine` skill to review the current branch.

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Write `skills/review-mine/SKILL.md`**

````markdown
---
name: review-mine
description: Use when reviewing a branch before a PR, or when /review-mine runs. Runs a builder/critic loop - fresh critics by concern, evidence rule, fix rounds proven by red tests, fresh re-review, explicit PASS verdict, optional exit pair - without asking questions once started.
---

# Review Mine

A builder/critic review loop on gauntlet principles: the builder never grades its own work, every critic is a fresh agent, critics grade against a written bar, and the loop runs until the bar is met, progress stalls, or the budget ends.

`SKILL_DIR` below means the base directory shown when this skill loaded. Run every script as `bash "$SKILL_DIR/scripts/<name>.sh"`.

## Rules for the whole run
- After setup succeeds, ask the user nothing. Stop only for: an irreversible or destructive action, a security-sensitive action, an outside side effect (push, publish, send), or a situation where every path is a guess. Everything else is your decision, recorded as a ruling.
- Never push. Never edit settings. Never downgrade a Critical. Commit messages carry no trailers.
- Every claim in the report must point to a file in the workspace (a log, a finding, a fixer report).
- Append one line to `ledger.md` for every completed step: `<UTC time> <step> <result>`.

## 1. Parse arguments
- `base`: first positional argument; default `git merge-base HEAD origin/<default>` where `<default>` comes from `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback `main`, then `master`).
- `--depth`: `lite` or `standard`. Default: `lite` if the diff has at most 3 files and 150 changed lines and no path contains auth, security, crypto, payment, billing, session, token, password or permission; otherwise `standard`.
- `--criteria <file>`: acceptance criteria. Without it, build the bar from the PR description (`gh pr view --json title,body` if it works) and the branch's commit messages, and mark it `inferred` in `bar.md`.
- `--scope <file>`: scope file for `scope-check.sh`. Optional.
- `--no-fix`: run round 1 only and report.
- `--prove/--reset/--env-file/--db-pattern/--allow-remote`: passed straight to `exit-pair.sh`.

## 2. Setup (the only point where you may stop with a message to the user)
1. Must be inside a git repository with a clean working tree (`git status --porcelain` empty). Otherwise stop: "Commit or stash your changes, then run /review-mine again."
2. Unless `--no-fix`, refuse to run on the default branch: fixes are committed to the current branch.
3. If `superpowers:test-driven-development` is not an available skill, stop and tell the user to install the superpowers plugin.
4. `REVIEW_WS=$(bash "$SKILL_DIR/scripts/workspace.sh")`; use it as the env var for every script call.
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
7. Baseline: `git switch --detach <base>`, run each gate as `bash "$SKILL_DIR/scripts/run-gate.sh" baseline-<name> 900 -- "<command>"`, then `git switch <branch>`. If anything fails in between, switch back first. Write `baseline.md` with each gate's status; failing gates are **known reds**. On resume, if HEAD is detached and `state.md` has `restore_branch`, switch back to it before anything else.
8. Run each gate on HEAD as `head-<name>`. A gate that is `could-not-run` or `timeout` on HEAD stops the run with that reason in the report.
9. Write `bar.md`: the acceptance criteria (given or inferred), plus a `Deferred:` list, initially empty.

## 3. Round 1
1. `bash "$SKILL_DIR/scripts/review-package.sh" <base> HEAD "$REVIEW_WS/review/round-1/package"`. Also write `review/round-1/gates.md`: each gate's HEAD status compared with `baseline.md`.
2. Dispatch critics **in one message, in parallel**, as `final-reviewer` with these models:
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
1. Stop if `round >= rounds_max`, or if only the protected slot remains in the budget and you still need a fixer (standard).
2. Record `pre_fix=$(git rev-parse HEAD)`.
3. Open Critical and Important findings go to the fix round; Minors are deferred.
   - standard: dispatch `ticket-fixer` (model sonnet, +1 budget) with `FINDINGS` (the open findings file), `GATES` (one `bash "$SKILL_DIR/scripts/run-gate.sh" fix<N>-<name> 900 -- "<command>"` line per gate), `SCOPE` (if given), `REPORT` (`review/round-<N>/fix-report.md`).
   - lite: do the fix round yourself, under `superpowers:test-driven-development`, with the same rules and the same report format.
4. Re-run every gate yourself as `round<N>-<name>` (never trust the fixer's claim). A gate red on HEAD but not in the baseline becomes a new Critical finding with the log as evidence. If `--scope` was given, run `bash "$SKILL_DIR/scripts/scope-check.sh" <base> <scope>`: a `forbidden` file is a Critical finding ("revert this change"); `out-of-scope` files become rulings.
5. `UNREPRODUCED` findings leave the loop: listed in the report (security first), never counted as fixed or dismissed.
6. Fresh re-review: `bash "$SKILL_DIR/scripts/review-package.sh" "$pre_fix" HEAD "$REVIEW_WS/review/round-<N>/package"`, then dispatch `final-reviewer` (model sonnet, +1 budget; use the protected slot if it is the last dispatch) with `MODE: re-review`, `PACKAGE`, `BAR`, `GATES`, `VERDICT_REQUIRED: yes`, and `FINDINGS` = only IDs and titles of what the fix round touched (no earlier reasoning).
7. **Evidence outranks opinion:** a behavioral finding whose red test now passes stays addressed unless the critic gave a NEW-TRIGGER; a NEW-TRIGGER becomes a new finding (round-N ID).
8. New findings go through the evidence filter and get IDs `F<N>-<n>`.
9. **Progress** (standard only): progress = the count of open Critical + Important findings fell by at least 1. Two consecutive rounds without progress → stop the loop (plateau).
10. Exit the loop when VERDICT is PASS and no Critical or Important is open; otherwise next round.

## 5. Exit pair (only if `--prove` was given)
Run after the loop exits with PASS: `bash "$SKILL_DIR/scripts/exit-pair.sh" --prove ... [reset options]`.
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
````

- [ ] **Step 3: Validate**

Run: `./scripts/validate.sh`
Expected: `OK: repo is valid` (the skill references only scripts that exist).

- [ ] **Step 4: Plugin validator**

Run: `claude plugin validate .`
Expected: `✔ Validation passed`.

- [ ] **Step 5: Run the whole test suite**

Run: `bash tests/run.sh`
Expected: every test file reports `0 failed`, including all five `validate.test.sh` cases.

- [ ] **Step 6: Commit**
```bash
git add skills/review-mine/SKILL.md commands/review-mine.md
git commit -m "feat: add review-mine skill and command"
```

---

### Task 8: Fixture repo and smoke checklist

**Files:**
- Create: `tests/fixture/setup.sh`, `tests/fixture/scope.txt`, `tests/scripts/fixture.test.sh`, `tests/SMOKE.md`

**Interfaces:**
- Produces: `bash tests/fixture/setup.sh <dest>` → a git repo at `<dest>` with `main` (base, one known red test) and `feat/discounts` (seeded defects). Used by `tests/SMOKE.md`.

- [ ] **Step 1: Write the failing test**

`tests/scripts/fixture.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
dest="$tmp/fixture shop"
bash "$ROOT/tests/fixture/setup.sh" "$dest" >/dev/null; code=$?
assert_eq 0 "$code" "setup exits 0"
assert_contains "$(git -C "$dest" branch --list)" "feat/discounts" "feature branch exists"
assert_eq "feat/discounts" "$(git -C "$dest" rev-parse --abbrev-ref HEAD)" "left on the feature branch"
git -C "$dest" switch -q main
out=$(cd "$dest" && node --test test/ 2>&1)
assert_contains "$out" "known red" "base has the known red test"
assert_contains "$out" "# fail 1" "exactly one failing test on base"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: `fixture.test.sh` reports failures.

- [ ] **Step 3: Write `tests/fixture/scope.txt`**
```
# Scope for the fixture's feat/discounts branch
allow: src/**
allow: test/**
allow: e2e/**
forbid: src/billing/**
```

- [ ] **Step 4: Write `tests/fixture/setup.sh`**

```bash
#!/usr/bin/env bash
# Build the review-mine fixture: main (with one known red test) and feat/discounts (seeded defects).
# Usage: setup.sh <dest>
set -eu
dest=${1:?usage: setup.sh <dest>}
[ ! -e "$dest" ] || { echo "already exists: $dest" >&2; exit 1; }
mkdir -p "$dest" && cd "$dest"
git init -q -b main
git config user.name "Fixture"
git config user.email "fixture@example.com"
mkdir -p src/billing test e2e scripts

cat > package.json <<'EOF'
{
  "name": "fixture-shop",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "test": "node --test test/",
    "e2e": "node --test e2e/",
    "db:reset": "node scripts/reset-db.js"
  }
}
EOF
cat > .gitignore <<'EOF'
test.db
node_modules
EOF
cat > .env.test <<'EOF'
DATABASE_URL=file:./test.db
EOF
cat > src/cart.js <<'EOF'
function subtotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}

function formatPrice(cents) {
  return '$' + (cents / 100).toFixed(2);
}

module.exports = { subtotal, formatPrice };
EOF
cat > src/billing/rates.js <<'EOF'
module.exports = { taxRate: 0.08 };
EOF
cat > scripts/reset-db.js <<'EOF'
const fs = require('fs');
const file = process.env.DATABASE_URL.replace('file:', '');
fs.writeFileSync(file, '[]');
EOF
cat > test/cart.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { subtotal, formatPrice } = require('../src/cart');

test('subtotal adds price times quantity', () => {
  assert.strictEqual(subtotal([{ price: 250, qty: 2 }, { price: 100, qty: 1 }]), 600);
});

test('known red: formatPrice uses thousands separators', () => {
  assert.strictEqual(formatPrice(123456), '$1,234.56');
});
EOF
cat > e2e/checkout.e2e.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const { subtotal } = require('../src/cart');

test('checkout starts from an empty order store', () => {
  const file = process.env.DATABASE_URL.replace('file:', '');
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(file, 'utf8')), []);
  assert.strictEqual(subtotal([{ price: 500, qty: 1 }]), 500);
});
EOF
git add -A && git commit -q -m "base: cart and checkout"

git switch -q -c feat/discounts
cat > src/cart.js <<'EOF'
function subtotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}

function formatPrice(cents) {
  return '$' + (cents / 100).toFixed(2);
}

// Seeded behavioral defect: percent above 100 gives a negative total.
function applyDiscount(total, percent) {
  return total - Math.round(total * percent / 100);
}

// Seeded behavioral defect: a malformed code such as "SAVEabc" yields NaN.
function applyCoupon(total, code) {
  const percent = Number(code.replace('SAVE', ''));
  return applyDiscount(total, percent);
}

// Seeded structural defect: duplicate of applyDiscount.
function applyDiscountPercent(total, percent) {
  return total - Math.round(total * percent / 100);
}

// Seeded security-shaped defect: loads a coupon table from a caller-supplied path.
function loadCoupons(path) {
  return require(path);
}

module.exports = { subtotal, formatPrice, applyDiscount, applyCoupon, applyDiscountPercent, loadCoupons };
EOF
cat > test/discount.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { applyDiscount, applyCoupon } = require('../src/cart');

test('applyDiscount takes 10 percent off', () => {
  assert.strictEqual(applyDiscount(1000, 10), 900);
});

test('applyCoupon reads the percent from the code', () => {
  assert.strictEqual(applyCoupon(1000, 'SAVE20'), 800);
});
EOF
# Seeded incidental change and seeded forbidden change.
echo '{ "name": "fixture-shop", "lockfileVersion": 3 }' > package-lock.json
cat > src/billing/rates.js <<'EOF'
module.exports = { taxRate: 0.1 };
EOF
git add -A && git commit -q -m "feat: discounts and coupons"
echo "$dest"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run.sh`
Expected: every test file reports `0 failed`.

- [ ] **Step 6: Write `tests/SMOKE.md`**

````markdown
# /review-mine smoke test

Run before every release. Record results in the release commit message or a note.

## Setup
```bash
bash tests/fixture/setup.sh /tmp/rm-fixture
cd /tmp/rm-fixture
claude --plugin-dir "<path to this repo>"   # or the install method recorded in the spike doc
```

## Run 1: standard depth, scope and exit pair
```
/review-mine main --depth standard --scope <path to this repo>/tests/fixture/scope.txt --prove "npm run e2e" --reset "npm run db:reset" --env-file .env.test --db-pattern 'test\.db$'
```
Expected:
- [ ] No questions asked after setup.
- [ ] `baseline.md` lists the `known red: formatPrice...` test as a known red; the run continues.
- [ ] Negative total (`applyDiscount(1000, 150)`) is found, fixed, and has a red test named in the report.
- [ ] `SAVEabc` → NaN is found and fixed with a red test.
- [ ] The duplicate `applyDiscountPercent` is found as structural and marked ADDRESSED by the re-review.
- [ ] `loadCoupons` is reported, either fixed with a red test or listed under "Unreproduced findings". It is never silently dropped.
- [ ] `package-lock.json` is classified incidental; `src/billing/rates.js` is forbidden and the change is reverted by a fix round.
- [ ] Exit pair: `pass` (reset ran before each run).
- [ ] Outcome `READY`, or `BLOCKED` with a stated reason that matches the workspace files.
- [ ] Nothing was pushed; the workspace is under `~/.claude/tickets/fixture-shop/_reviews/` (or the repo folder name).

## Run 2: refusal of an unsafe reset
Edit `.env.test` to `DATABASE_URL=postgres://prod.example.com/app` and commit it, then rerun the Run 1 command.
- [ ] Exit pair reported as `refused` with "not local" or "does not match"; the reset command never ran.

## Run 3: lite depth, review only
```bash
bash tests/fixture/setup.sh /tmp/rm-fixture-2 && cd /tmp/rm-fixture-2
```
```
/review-mine main --depth lite --no-fix
```
- [ ] One combined critic; no commits made; report lists findings with IDs and evidence.

## Record
For each run: dispatches used / budget, findings raised / kept after the evidence filter / fixed, rounds used, wall time. These numbers decide whether the loop earns its cost.
````

- [ ] **Step 7: Commit**
```bash
git add tests/fixture/setup.sh tests/fixture/scope.txt tests/scripts/fixture.test.sh tests/SMOKE.md
git commit -m "test: add review-mine fixture and smoke checklist"
```

---

### Task 9: README, version, and smoke run

**Files:**
- Modify: `README.md` (add a `/review-mine` section after "Layout"), `.claude-plugin/plugin.json` (`"version": "0.2.0"`)

- [ ] **Step 1: Add the README section**

Insert after the Layout table:
````markdown
## /review-mine

Reviews the current branch with fresh critics, keeps only findings that come with evidence, fixes Critical and Important ones with a failing test first, re-reviews the fixes with a new critic, and stops at an explicit PASS, a plateau, or the budget. It commits fixes to your branch and never pushes.

```
/review-mine [base] [--depth lite|standard] [--criteria <file>] [--scope <file>] [--no-fix]
             [--prove "<cmd>" [--reset "<cmd>" --env-file <file> --db-pattern <regex>]]
```

Working files go to `~/.claude/tickets/<repo>/_reviews/`, never into your project.

**Permissions.** To run without prompts, allow the review scripts and the workspace in your settings (the exact rules are recorded in `docs/superpowers/spikes/2026-10-03-phase-1a.md`):
- running `bash` on this plugin's `skills/review-mine/scripts/*.sh`
- your gate commands (for example `npm test`, `npm run lint`)
- reading and writing `~/.claude/tickets/**`

**Exit pair safety.** `--reset` runs only when the database in `--env-file` matches `--db-pattern` and its host is local. Anything else is refused before a reset runs.

Tests: `bash tests/run.sh`. End-to-end: `tests/SMOKE.md`.
````

Replace the permission bullet list with the exact rule strings from the spike doc.

- [ ] **Step 2: Bump the version**

In `.claude-plugin/plugin.json` change `"version": "0.1.0"` to `"version": "0.2.0"`.

- [ ] **Step 3: Full verification**

Run: `./scripts/validate.sh && bash tests/run.sh && claude plugin validate .`
Expected: `OK: repo is valid`; every test file `0 failed`; `✔ Validation passed`.

- [ ] **Step 4: Smoke run**

Follow `tests/SMOKE.md` Runs 1–3. Record the numbers it asks for. Any unchecked box is a defect: fix it (test first where the defect is in a script) before committing.

- [ ] **Step 5: Commit and tag**
```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: document review-mine and bump version to 0.2.0"
git tag v0.2.0
```
Do not push; the user decides when.
