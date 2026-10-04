# Guardrail Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One plugin `PreToolUse` hook on `Bash` that blocks tool attribution in commits and PRs everywhere, and blocks unapproved pushes and base-branch commits while a `/ticket` is in progress.

**Architecture:** `hooks/hooks.json` runs `hooks/guard.sh`. The guard reads the hook JSON from stdin, decodes `tool_input.command` and `cwd` with `perl`, and exits early unless the command runs `git commit`, `git push` or `gh pr create|edit`. Ticket rules read the ticket workspaces through the existing `ticket-ws.sh` and `state.sh`. Every failure to read anything allows the command (fail open).

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), BSD grep/sed, perl (core, already used by `dev-server.sh`), git.

**Spec:** `docs/superpowers/specs/2026-10-03-pipeline-completion-design.md`, section B. Spike: `docs/superpowers/spikes/2026-10-04-guard-hooks.md`.

## Global Constraints
- Scripts run on macOS bash 3.2 with BSD tools: no `mapfile`, no `timeout`, no `jq`, `sed -E`; tests run under `/bin/bash` via `bash tests/run.sh`.
- Hook contract (spike): JSON on stdin; exit 0 allows; exit 2 blocks and stderr is shown to Claude; `${CLAUDE_PLUGIN_ROOT}` expands in the hook command.
- The guard never blocks when it cannot find or parse state: fail open, print nothing.
- No tool attribution in commit messages or PR text, ever. Commit with Conventional Commit messages and no trailers; run `bash scripts/check-commits.sh <base>..HEAD` after committing.
- Nothing employer-specific.
- Checks before a task is done: `bash tests/run.sh`, `./scripts/validate.sh`, `claude plugin validate .`.

## Review Focus
- **Ordinary work must never be blocked:** any command that is not a commit, push or PR create/edit (including `git log --grep "Co-Authored""-By: Claude"` and `echo git commit`) is allowed. Pinned in Task 1's tests.
- **Messages not in the command line:** a message passed in a file (`-F`, `--file`, `--body-file`) or a heredoc is still checked. Pinned in Task 1.
- **Broken or missing input:** empty stdin, invalid JSON, a cwd that is not a repo, a missing `state.md` → exit 0 with no output. Pinned in Tasks 1 and 2.
- **Wrong ticket matched:** the push rule applies only to the ticket whose `branch` equals the current branch; the base rule only to tickets whose `base_branch` equals it, and only between `approved` and `handoff` (including `round2`). Pinned in Task 2.
- **SHIP must still be able to push:** SHIP sets `push_approved: yes` before `git push`. Pinned by Task 3's smoke run.

## File Structure
| File | Responsibility |
|---|---|
| `hooks/hooks.json` | registers the `PreToolUse` Bash hook |
| `hooks/guard.sh` | reads hook JSON, applies the three rules |
| `tests/scripts/guard.test.sh` | feeds recorded-shape hook JSON to the guard |
| `skills/ticket-ship/SKILL.md` | sets `push_approved: yes` before pushing |
| `skills/ticket-workspace/SKILL.md` | documents the `push_approved` key and the guard |
| `README.md`, `.claude-plugin/plugin.json` | docs, version 0.5.0 |
| `tests/SMOKE-guard.md` | headless smoke checklist |

---

### Task 1: Guard skeleton and the no-attribution rule

**Files:**
- Create: `hooks/guard.sh`
- Modify: `hooks/hooks.json`
- Test: `tests/scripts/guard.test.sh`

**Interfaces:**
- Produces: `hooks/guard.sh` reading hook JSON on stdin; functions `field <name>`, `has <ERE>`, `block <reason>`, and the variables `cmd`, `dir`, `G` that Task 2 extends. Exit 0 allow, 2 block (stderr starts with `patrick-workflows guard: `).

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/guard.test.sh`:

```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
GUARD="$ROOT/hooks/guard.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets"
# hook <cwd> <command>: run the guard on hook JSON shaped like the real one (spike); sets code and err.
hook() {
  err=$(perl -MJSON::PP -e 'print encode_json({session_id=>"s",cwd=>$ARGV[0],hook_event_name=>"PreToolUse",tool_name=>"Bash",tool_input=>{command=>$ARGV[1],description=>"d"}})' "$1" "$2" | bash "$GUARD" 2>&1 >/dev/null); code=$?
}
mkdir -p "$tmp/plain"
T="Co-Authored""-By: Claude Opus <noreply@anthropic.com>"

hook "$tmp/plain" 'git commit -m "feat: add x"'; assert_eq 0 "$code" "clean commit allowed"; assert_eq "" "$err" "allow prints nothing"
hook "$tmp/plain" "git commit -m \"feat: x

$T\""; assert_eq 2 "$code" "trailer in -m blocked"
assert_contains "$err" "patrick-workflows guard: " "block reason prefix"
hook "$tmp/plain" "cd a && git commit -F - <<'EOF'
feat: x

$T
EOF"; assert_eq 2 "$code" "trailer in heredoc blocked"
printf 'feat: x\n\n%s\n' "$T" > "$tmp/plain/msg.txt"
hook "$tmp/plain" 'git commit -F msg.txt'; assert_eq 2 "$code" "trailer in -F file blocked"
hook "$tmp/plain" 'git commit --file=msg.txt'; assert_eq 2 "$code" "trailer in --file= blocked"
hook "$tmp/plain" "gh pr create --draft --title t --body \"Adds x. \$GW\""  # GW holds the footer text, built from split strings so validate.sh does not flag this file; assert_eq 2 "$code" "footer in PR body blocked"
printf 'Body\n\nGenerated with Claude Code\n' > "$tmp/plain/body.md"
hook "$tmp/plain" 'gh pr edit 3 --body-file body.md'; assert_eq 2 "$code" "footer in --body-file blocked"
hook "$tmp/plain" "git -C /x commit -m \"x

co-authored-by: claude <n@a.com>\""; assert_eq 2 "$code" "case-insensitive, git -C form"
hook "$tmp/plain" 'git commit -m "say \"hi\" to C:\\temp"'; assert_eq 0 "$code" "escaped quotes and backslashes parse"
hook "$tmp/plain" "git commit -m \"x

Co-Authored-By: Jane <j@x.org>\""; assert_eq 0 "$code" "human co-author allowed"
hook "$tmp/plain" 'git log --grep "Co-Authored""-By: Claude"'; assert_eq 0 "$code" "searching history allowed"
hook "$tmp/plain" "echo git commit \"$T\""; assert_eq 0 "$code" "echo of the words allowed"
hook "$tmp/plain" 'ls -la'; assert_eq 0 "$code" "unrelated command allowed"

out=$(printf '' | bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "empty stdin allowed silently"
out=$(printf '{not json' | bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "invalid JSON allowed silently"
out=$(perl -MJSON::PP -e 'print encode_json({cwd=>"/x",tool_input=>{command=>"git commit -m \"x\n\nCo-Authored""-By: Claude <a\@b>\""}})' | PATRICK_WORKFLOWS_GUARD=off bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "PATRICK_WORKFLOWS_GUARD=off disables"

hj=$(cat "$ROOT/hooks/hooks.json")
assert_contains "$hj" '"PreToolUse"' "hook event registered"
assert_contains "$hj" '"matcher": "Bash"' "Bash matcher"
assert_contains "$hj" '${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh' "runs the guard from the plugin root"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/bin/bash tests/scripts/guard.test.sh`
Expected: FAIL. Every blocked case fails (the guard file does not exist, so `bash` exits 127), and the hooks.json assertions fail.

- [ ] **Step 3: Write the implementation**

`hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh\"" }
        ]
      }
    ]
  }
}
```

`hooks/guard.sh`:

```bash
#!/usr/bin/env bash
# PreToolUse guard for Bash tool calls (registered in hooks/hooks.json).
# Reads the hook JSON on stdin. Exit 0 allows the command; exit 2 blocks it and stderr tells Claude why.
# Rule 1 (always): no tool attribution (a Claude co-author trailer or a "Generated with Claude Code"
# footer) in git commit or gh pr create/edit text, including files passed with -F/--file/--body-file.
# Fails open: input it cannot read allows the command and prints nothing.
# PATRICK_WORKFLOWS_GUARD=off in Claude Code's environment turns every rule off.
set -u
[ "${PATRICK_WORKFLOWS_GUARD:-on}" = off ] && exit 0
in=$(cat 2>/dev/null) || exit 0

# field <name>: the first "<name>": "<string>" value in the hook JSON, with its JSON escapes undone.
field() {
  printf '%s' "$in" | F="$1" perl -0777 -ne '
    my $f = $ENV{F};
    if (/"\Q$f\E"\s*:\s*"((?:[^"\\]|\\.)*)"/s) {
      my $s = $1;
      my %e = ("\"" => "\"", "\\" => "\\", "/" => "/", b => "\b", f => "\f", n => "\n", r => "\r", t => "\t");
      $s =~ s/\\(?:u([0-9a-fA-F]{4})|(.))/defined $1 ? do { my $c = chr(hex $1); utf8::encode($c); $c } : (exists $e{$2} ? $e{$2} : $2)/ge;
      print $s;
    }' 2>/dev/null
}
cmd=$(field command)
[ -n "$cmd" ] || exit 0
dir=$(field cwd); [ -d "$dir" ] || dir=$PWD

# has <ERE>: the command runs it at the start, or after ; & | ( { ` or $( (so "echo git commit" does not count).
has() { printf '%s\n' "$cmd" | grep -Eq "(^|[;&|(\`{]) *$1"; }
G='git( +-[Cc] +[^ ;&|]+)* +'   # git plus its -C/-c options
is_commit() { has "${G}commit([[:space:]]|\$)"; }
is_push() { has "${G}push([[:space:]]|\$)"; }
is_pr() { has "gh +pr +(create|edit)([[:space:]]|\$)"; }
block() { printf 'patrick-workflows guard: %s\n' "$1" >&2; exit 2; }

is_commit || is_push || is_pr || exit 0

# Rule 1: no tool attribution.
if is_commit || is_pr; then
  text=$cmd
  files=$(printf '%s\n' "$cmd" | perl -ne 'while (/(?:^|\s)(?:-F|--file|--body-file)(?:\s+|=)("[^"]*"|\x27[^\x27]*\x27|[^\s;&|]+)/g) { my $f = $1; $f =~ s/^["\x27]|["\x27]$//g; print "$f\n" }' 2>/dev/null)
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$f" != - ] || continue
    case $f in /*) p=$f ;; "~/"*) p="$HOME/${f#\~/}" ;; *) p="$dir/$f" ;; esac
    [ -f "$p" ] && text="$text
$(cat "$p" 2>/dev/null)"
  done <<EOF
$files
EOF
  if printf '%s\n' "$text" | grep -Eiq 'co-authored-by:[[:space:]]*claude|generated with \[?claude code'; then
    block 'remove the Claude co-author trailer or "Generated with Claude Code" footer from the commit message or PR text: this repo owner allows no tool attribution.'
  fi
fi
exit 0
```

`chmod +x hooks/guard.sh`.

- [ ] **Step 4: Run test to verify it passes**

Run: `/bin/bash tests/scripts/guard.test.sh`
Expected: all checks pass, `0 failed`. Then `bash tests/run.sh`, `./scripts/validate.sh`, `claude plugin validate .` all pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/guard.sh hooks/hooks.json tests/scripts/guard.test.sh
git commit -m "feat: add a PreToolUse guard that blocks tool attribution"
bash scripts/check-commits.sh HEAD~1..HEAD
```

---

### Task 2: Ticket rules: push approval and base-branch commits

**Files:**
- Modify: `hooks/guard.sh` (replace the final `exit 0`; update the header comment)
- Test: `tests/scripts/guard.test.sh` (append before the final `finish`)

**Interfaces:**
- Consumes: Task 1's `cmd`, `dir`, `is_commit`, `is_push`, `block`; `skills/ticket-workspace/scripts/ticket-ws.sh list` (prints `<id>\t<phase>` per ticket of the current repo, workspace root `${TICKETS_HOME:-~/.patrick-workflows/tickets}/<repo-slug>/`, repo slug = basename of `remote.origin.url` without `.git`) and `ticket-ws.sh path <id>`; `state.sh <state.md> get <key>` (exit 1 when absent).
- Produces: state key `push_approved` (`yes` allows `git push` for that ticket), used by Task 3.

- [ ] **Step 1: Write the failing test**

Append to `tests/scripts/guard.test.sh`, before the final `finish`:

```bash
# A repo with tickets. Workspaces live under $TICKETS_HOME/<repo-slug>/<id>/state.md.
R="$tmp/demo"; mkdir -p "$R"
( cd "$R" && git init -q -b main && git remote add origin https://example.com/me/demo.git \
  && git -c user.name=t -c user.email=t@x commit -q --allow-empty -m init && git branch feat/t-1 )
ticket() { mkdir -p "$TICKETS_HOME/demo/$1"; printf 'ticket: %s\nphase: %s\nbranch: %s\nbase_branch: main\n%s' "$1" "$2" "$3" "${4:-}" > "$TICKETS_HOME/demo/$1/state.md"; }

hook "$R" 'git push -u origin main'; assert_eq 0 "$code" "push with no tickets allowed"
ticket T-1 implementing feat/t-1
git -C "$R" switch -q feat/t-1
hook "$R" 'git push -u origin feat/t-1'; assert_eq 2 "$code" "push before approval blocked"
assert_contains "$err" "T-1" "push block names the ticket"
ticket T-1 handoff feat/t-1 'push_approved: yes
'
hook "$R" 'git push -u origin feat/t-1'; assert_eq 0 "$code" "approved push allowed"
ticket T-1 pr feat/t-1
hook "$R" 'git push'; assert_eq 0 "$code" "push after the PR phase allowed"
ticket T-1 implementing feat/t-1
git -C "$R" switch -q main
hook "$R" 'git push origin main'; assert_eq 0 "$code" "push of another branch allowed"

hook "$R" 'git commit -m "fix: y"'; assert_eq 2 "$code" "commit on the base branch during a ticket blocked"
assert_contains "$err" "feat/t-1" "base block names the ticket branch"
for ph in intake designed planned pr closed; do
  ticket T-1 "$ph" feat/t-1
  hook "$R" 'git commit -m "fix: y"'; assert_eq 0 "$code" "commit on base allowed in phase $ph"
done
for ph in approved round2 handoff blocked; do
  ticket T-1 "$ph" feat/t-1
  hook "$R" 'git commit -m "fix: y"'; assert_eq 2 "$code" "commit on base blocked in phase $ph"
done
git -C "$R" switch -q feat/t-1
ticket T-1 implementing feat/t-1
hook "$R" 'git commit -m "feat: z"'; assert_eq 0 "$code" "commit on the ticket branch allowed"

rm "$TICKETS_HOME/demo/T-1/state.md"
git -C "$R" switch -q main
hook "$R" 'git commit -m "fix: y"'; assert_eq 0 "$code" "missing state.md fails open"
hook "$tmp/plain" 'git push'; assert_eq 0 "$code" "not a repo fails open"
assert_eq "" "$err" "fail open prints nothing"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/bin/bash tests/scripts/guard.test.sh`
Expected: FAIL on "push before approval blocked", "push block names the ticket", "commit on the base branch during a ticket blocked", "base block names the ticket branch" and the four "blocked in phase" checks; the allow checks pass.

- [ ] **Step 3: Write the implementation**

In `hooks/guard.sh`, add to the header comment after the Rule 1 lines:

```bash
# Rule 2 (a ticket for the current branch is in a phase before pr): git push needs push_approved: yes.
# Rule 3 (a ticket based on the current branch is between approved and handoff): no git commit here.
# Tickets are found with ticket-ws.sh list and read with state.sh; unreadable state allows the command.
```

Replace the final `exit 0` with:

```bash
is_push || is_commit || exit 0
TW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../skills/ticket-workspace/scripts"
br=$(git -C "$dir" branch --show-current 2>/dev/null) || exit 0
[ -n "$br" ] || exit 0
list=$(cd "$dir" && bash "$TW/ticket-ws.sh" list 2>/dev/null) || exit 0
[ -n "$list" ] || exit 0
PRE_PR=" intake designed planned approved implementing reviewing fixing ready blocked handoff round2 "
IN_BUILD=" approved implementing reviewing fixing ready blocked handoff round2 "
tab=$(printf '\t')
while IFS=$tab read -r id phase; do
  [ -n "$id" ] || continue
  ws=$(cd "$dir" && bash "$TW/ticket-ws.sh" path "$id" 2>/dev/null) || continue
  st="$ws/state.md"; [ -f "$st" ] || continue
  tbranch=$(bash "$TW/state.sh" "$st" get branch 2>/dev/null)
  if is_push && [ "$tbranch" = "$br" ]; then
    case $PRE_PR in *" $phase "*)
      [ "$(bash "$TW/state.sh" "$st" get push_approved 2>/dev/null)" = yes ] ||
        block "ticket $id is in phase $phase: push only from /ticket's SHIP step, after the user approves the PR." ;;
    esac
  fi
  if is_commit && [ "$(bash "$TW/state.sh" "$st" get base_branch 2>/dev/null)" = "$br" ]; then
    case $IN_BUILD in *" $phase "*)
      block "ticket $id is in progress on branch $tbranch, based on $br: commit on $tbranch, not on $br." ;;
    esac
  fi
done <<EOF
$list
EOF
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/bin/bash tests/scripts/guard.test.sh`
Expected: `0 failed`. Then `bash tests/run.sh`, `./scripts/validate.sh`, `claude plugin validate .` pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/guard.sh tests/scripts/guard.test.sh
git commit -m "feat: guard pushes and base-branch commits while a ticket is in progress"
bash scripts/check-commits.sh HEAD~1..HEAD
```

---

### Task 3: SHIP approval key, docs, version, smoke

**Files:**
- Modify: `skills/ticket-ship/SKILL.md` (section 3, step 3)
- Modify: `skills/ticket-workspace/SKILL.md` (state keys list; a short "Guard" paragraph)
- Modify: `README.md` (a "Guardrails" section; layout table row for `hooks/`)
- Modify: `.claude-plugin/plugin.json` (`"version": "0.5.0"`)
- Create: `tests/SMOKE-guard.md`

**Interfaces:**
- Consumes: `push_approved` from Task 2; `PATRICK_WORKFLOWS_GUARD=off` from Task 1.

- [ ] **Step 1: Write the failing check**

Run: `grep -n "push_approved" skills/ticket-ship/SKILL.md skills/ticket-workspace/SKILL.md README.md; grep -n '"version": "0.5.0"' .claude-plugin/plugin.json`
Expected: no output (nothing documents the key or the version yet).

- [ ] **Step 2: Edit the files**

1. `skills/ticket-ship/SKILL.md`, section 3 step 3 becomes:
   `3. \`S set push_approved yes\` (the guard hook blocks a ticket's push without it), then \`git push -u origin <branch>\`, then \`gh pr create --draft --base <pr_target> --title "<title>" --body-file "<WS>/pr-body.md"\`.`
2. `skills/ticket-workspace/SKILL.md`: add `` `push_approved` (`yes` once the user approved the PR; SHIP sets it right before pushing) `` to the state keys line, and add after the phase paragraph:
   `**Guard hook.** While a ticket is open, the plugin's PreToolUse hook (\`hooks/guard.sh\`) blocks \`git push\` from the ticket branch before phase \`pr\` unless \`push_approved: yes\`, and blocks \`git commit\` on the ticket's \`base_branch\` from \`approved\` to \`handoff\` (including \`round2\`). It always blocks tool attribution in commits and PRs. A block is a message to act on (commit on the ticket branch; push only from SHIP), never a reason to work around the hook.`
3. `README.md`: add a `## Guardrails` section after the workflows sections:
   - what the hook blocks (the three rules, one line each, same scopes as above);
   - it fails open and never blocks other commands;
   - to turn it off for a session, start Claude Code with `PATRICK_WORKFLOWS_GUARD=off` in its environment (setting it inside a Bash command does nothing, because the hook runs in Claude Code's environment);
   - known limits: a message built at runtime (for example `-m "$(cat file)"`) is not seen; `git -C <dir>` uses the session folder for ticket lookups.
   Also make the layout table's `hooks/hooks.json` row read `` `hooks/` | PreToolUse guard (`guard.sh`) ``.
4. `.claude-plugin/plugin.json`: `"version": "0.5.0"`.
5. `tests/SMOKE-guard.md`:

````markdown
# Guard hook smoke test
```bash
d=$(mktemp -d) && cd "$d" && git init -q -b main && git commit -q --allow-empty -m init
claude -p --plugin-dir "<repo>" --allowedTools "Bash(git *)" \
  -- 'Run exactly this with the Bash tool and report the full result: git commit --allow-empty -m "chore: smoke" -m "Co-Authored""-By: Claude <noreply@anthropic.com>"' < /dev/null
git log --oneline | wc -l   # still 1
```
- [ ] Claude reports a `PreToolUse:Bash hook error` whose text starts with `patrick-workflows guard:`.
- [ ] `git log` shows no new commit.
- [ ] Rerun with `-m "chore: smoke"` only: the commit is made.
````

- [ ] **Step 3: Run the checks**

Run: the grep from Step 1, then `bash tests/run.sh`, `./scripts/validate.sh`, `claude plugin validate .`.
Expected: the grep shows the key in all three files and the version line; all checks pass.

- [ ] **Step 4: Commit**

```bash
git add skills/ticket-ship/SKILL.md skills/ticket-workspace/SKILL.md README.md .claude-plugin/plugin.json tests/SMOKE-guard.md
git commit -m "docs: document the guard hook and set push approval in SHIP"
bash scripts/check-commits.sh HEAD~1..HEAD
```

- [ ] **Step 5: Smoke (controller)**

The controller runs `tests/SMOKE-guard.md` headless after the task review and ticks its checklist.
