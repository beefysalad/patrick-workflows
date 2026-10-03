# UI Grading, CLOSE and Minors (Sub-project A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the graded (UI) bar to the review loop and `/ticket`, add the CLOSE stage, and close the remaining deferred minors.

**Architecture:** Deterministic parts are bash scripts in `skills/review-mine/scripts/` (dev-server lifecycle, screenshot capture, blind A/B setup and verdict) and `skills/ticket-workspace/scripts/` (PR state), each unit-tested with stubs. Judgment is a read-only `ui-scorer` agent that scores two image folders blind. Skills wire them in: `review-mine` runs the graded bar each round; `ticket-plan` collects the graded brief; `ticket-close` handles merged PRs.

**Tech Stack:** Bash (macOS 3.2 + BSD tools), perl (process groups, free port), curl, Playwright CLI via npx, Chrome headless fallback, gh, Claude Code plugin markdown.

**Spec:** `docs/superpowers/specs/2026-10-03-pipeline-completion-design.md` section A (implements base spec `2026-10-02-ticket-pipeline-design.md` sections 9.4 and 12a).

## Global Constraints

- Public-safe repo; no tool attribution in commits or PR text (`scripts/validate.sh` enforces it); Conventional Commits; never push.
- Bash 3.2 + BSD tools; quote every expansion; paths with spaces; scripts invoked as `bash <path>`; commands Claude runs start with `bash`, `git`, `gh`, `npx`, or a gate command, never `VAR=value`.
- Workspace resolution for review scripts: `REVIEW_WS`, else the pointer in `$(git rev-parse --git-path patrick-workflows-review-ws)` (same as `run-gate.sh`).
- Graded pass rule: ours ≥ reference − margin (0.3), ours ≥ floor (3.5), no criterion of ours below min (3); every scorer file must pass (the second is the confirming scorer).
- Viewports: desktop 1440×900, phone 390×844; schemes light and dark (Chrome fallback: light only, reported).
- Read-only agents (`final-reviewer`, `task-reviewer`, `ui-scorer`) have no Write, Edit, Bash.
- Agents dispatched as `patrick-workflows:<name>`.
- Ledger timestamps come from `date -u +%Y-%m-%dT%H:%M:%SZ`, never typed by hand.

## Review Focus

- **Orphaned dev servers:** a server that never becomes ready, or a crash mid-capture, must not leave a process holding a port. Pinned by `dev-server.test.sh` (timeout path kills the process group; stale PID file cleaned on start).
- **Scorer learns which side is ours:** the mapping file must live outside the folder the scorer reads. Pinned by `graded-ab.test.sh`.
- **Score parsing:** malformed scorer output (missing side, unequal criteria counts) must be "bad input", never a pass. Pinned by `graded-ab.test.sh`.
- **CLOSE on an unmerged PR** must change nothing. Pinned by `pr-state.test.sh` and the skill's first step.
- **Capture tool missing** must be `could-not-run`, never an empty pass. Pinned by `capture.test.sh`.

## File Structure

| File | Responsibility |
|---|---|
| `skills/review-mine/scripts/dev-server.sh` | Start/stop/status of the dev server; free port; readiness; PID file |
| `skills/review-mine/scripts/capture.sh` | Screenshots per route × viewport × scheme; Playwright with Chrome fallback |
| `skills/review-mine/scripts/graded-ab.sh` | Blind A/B folders + mapping; pass/fail verdict from scorer files |
| `skills/ticket-workspace/scripts/pr-state.sh` | `merged` / `open` / `closed-unmerged` from `gh` |
| `skills/ticket-workspace/scripts/branch-name.sh` | (modify) refuse IDs that slug to nothing |
| `agents/ui-scorer.md` | Blind read-only scorer |
| `skills/review-mine/SKILL.md` | (modify) graded bar, rerun budget, ledger timestamps |
| `skills/ticket-plan/SKILL.md`, `ticket-build`, `ticket-ship`, `ticket-workspace` | (modify) graded brief, `type` key, branch rename validation, close routing, timestamps |
| `skills/ticket-close/SKILL.md` | CLOSE stage |
| `commands/ticket.md` | (modify) route `pr` to CLOSE |
| `scripts/validate.sh` | (modify) `ui-scorer` read-only |
| `tests/fixture/ui-setup.sh`, `tests/SMOKE-graded.md` | UI fixture and graded smoke |

---

### Task 0: Spike — capture tooling and image reading

**Files:** Create `docs/superpowers/spikes/2026-10-03-ui-grading.md`.

- [ ] **Step 1: Playwright CLI**
```bash
S=$(mktemp -d); printf '<html><body style="background:#3366cc"><h1>Spike</h1></body></html>' > "$S/index.html"
(cd "$S" && python3 -m http.server 8765 >/dev/null 2>&1 & echo $! > "$S/pid")
sleep 1
npx --yes playwright screenshot --viewport-size=390,844 --full-page --color-scheme=dark http://127.0.0.1:8765/ "$S/pw.png"; echo "pw exit=$?"; ls -l "$S/pw.png"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=390,844 --screenshot="$S/chrome.png" http://127.0.0.1:8765/; echo "chrome exit=$?"; ls -l "$S/chrome.png"
kill "$(cat "$S/pid")"
```
Expected: both PNGs exist. Record whether `npx --yes playwright` downloaded the package (network) and how long it took; if it fails, record the error, and Task 2's default command becomes the one that worked.

- [ ] **Step 2: A read-only agent reads images**
```bash
claude -p --model sonnet --plugin-dir "$PWD" --allowedTools "Read(//$S/**)" "Glob" -- "Dispatch patrick-workflows:final-reviewer with this text instead of a review: 'Read the image $S/pw.png and report its dominant background color in one word.' Print its answer." < /dev/null
```
Expected: an answer naming blue. Record it. If the agent cannot read images, Task 5's scorer gets the images via its dispatch text paths and the main session describes nothing; the plan stops for a ruling.

- [ ] **Step 3: Write the spike doc and commit**
```bash
git add docs/superpowers/spikes/2026-10-03-ui-grading.md
git commit -m "docs: record ui grading spike results"
```

---

### Task 1: `dev-server.sh`

**Files:** Create `tests/scripts/dev-server.test.sh`, `skills/review-mine/scripts/dev-server.sh`.

**Interfaces:**
- Produces: `bash dev-server.sh start "<command>" [timeout]` → `DEV-SERVER: up http://127.0.0.1:<port>` (exit 0) or `DEV-SERVER: could-not-run <reason>` (exit 3); the command runs with `PORT=<port>` in its environment (use `$PORT` inside the command for tools that need a flag); `stop` (always exit 0); `status` → `DEV-SERVER: up <url>` (exit 0) or `DEV-SERVER: down` (exit 1). Files in the workspace: `dev-server.pid`, `dev-server.port`, `logs/dev-server.log`.

- [ ] **Step 1: Failing test**

`tests/scripts/dev-server.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
DS="$ROOT/skills/review-mine/scripts/dev-server.sh"
tmp="$(mktemp -d)"; export REVIEW_WS="$tmp/work space"
trap 'bash "$DS" stop >/dev/null 2>&1; rm -rf "$tmp"' EXIT
srv="node -e \"require('http').createServer((q,s)=>s.end('ok')).listen(process.env.PORT,'127.0.0.1')\""

out=$(bash "$DS" start "$srv" 10); code=$?
assert_eq 0 "$code" "start exits 0"
assert_contains "$out" "DEV-SERVER: up http://127.0.0.1:" "prints the url"
url=${out#DEV-SERVER: up }
assert_eq "ok" "$(curl -s "$url/")" "server answers"
out2=$(bash "$DS" start "$srv" 10); assert_eq "$out" "$out2" "second start reuses the running server"
bash "$DS" status >/dev/null; assert_eq 0 $? "status up"
pid=$(cat "$REVIEW_WS/dev-server.pid")
bash "$DS" stop; assert_eq 0 $? "stop exits 0"
sleep 1
kill -0 "$pid" 2>/dev/null && _ko "process still alive after stop" || _ok
bash "$DS" status >/dev/null; assert_eq 1 $? "status down after stop"
bash "$DS" stop; assert_eq 0 $? "second stop is harmless"

echo 999999 > "$REVIEW_WS/dev-server.pid"
out=$(bash "$DS" start "$srv" 10); assert_eq 0 $? "stale pid file is cleaned"
bash "$DS" stop

start=$(date +%s)
out=$(bash "$DS" start "sleep 30" 2); code=$?
assert_eq 3 "$code" "never-ready server is could-not-run"
assert_contains "$out" "could-not-run" "reason printed"
[ $(( $(date +%s) - start )) -lt 8 ] && _ok || _ko "timeout respected"
pgrep -f "sleep 30" >/dev/null && _ko "never-ready process left running" || _ok
finish
```

- [ ] **Step 2: Run it to verify it fails** — `bash tests/run.sh`; expected failures in `dev-server.test.sh`.

- [ ] **Step 3: Implement**

`skills/review-mine/scripts/dev-server.sh`:
```bash
#!/usr/bin/env bash
# Dev-server lifecycle for UI captures.
# Usage: dev-server.sh start "<command>" [timeout-seconds]   (the command gets PORT=<port>)
#        dev-server.sh stop | status
# Files: <workspace>/dev-server.pid, dev-server.port, logs/dev-server.log
# Exit: 0 ok, 1 down (status), 3 could-not-run.
set -u
ws=${REVIEW_WS:-}
if [ -z "$ws" ]; then
  ptr=$(git rev-parse --git-path patrick-workflows-review-ws 2>/dev/null) && [ -f "$ptr" ] && ws=$(head -n 1 "$ptr")
fi
[ -n "$ws" ] || { echo "DEV-SERVER: could-not-run (no workspace)"; exit 3; }
mkdir -p "$ws/logs"
pidf="$ws/dev-server.pid"; portf="$ws/dev-server.port"

alive() { [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; }
url() { printf 'http://127.0.0.1:%s' "$(cat "$portf")"; }
stop_server() {
  if [ -f "$pidf" ]; then
    pid=$(cat "$pidf")
    kill -TERM -- "-$pid" 2>/dev/null; sleep 0.5; kill -KILL -- "-$pid" 2>/dev/null
  fi
  rm -f "$pidf" "$portf"
}
free_port() { perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => 0) or exit 1; print $s->sockport'; }

case ${1:-} in
  start)
    cmd=${2:-}; limit=${3:-60}
    [ -n "$cmd" ] || { echo "DEV-SERVER: could-not-run (no command)"; exit 3; }
    if alive && [ -f "$portf" ]; then echo "DEV-SERVER: up $(url)"; exit 0; fi
    stop_server   # clears a stale PID file
    port=$(free_port) || { echo "DEV-SERVER: could-not-run (no free port)"; exit 3; }
    exec 3>&2 2>/dev/null   # keep the shell's job notices out of the output
    PORT=$port perl -e 'setpgrp(0, 0); exec @ARGV' bash -c "$cmd" > "$ws/logs/dev-server.log" 2>&1 &
    echo $! > "$pidf"; echo "$port" > "$portf"
    exec 2>&3 3>&-
    ticks=0
    while [ "$ticks" -lt $((limit * 5)) ]; do
      if ! alive; then stop_server; echo "DEV-SERVER: could-not-run (exited; see logs/dev-server.log)"; exit 3; fi
      if curl -s -o /dev/null --max-time 1 "$(url)/"; then echo "DEV-SERVER: up $(url)"; exit 0; fi
      sleep 0.2; ticks=$((ticks + 1))
    done
    stop_server 2>/dev/null
    echo "DEV-SERVER: could-not-run (not ready after ${limit}s; see logs/dev-server.log)"; exit 3 ;;
  stop)
    stop_server 2>/dev/null; exit 0 ;;
  status)
    if alive && [ -f "$portf" ]; then echo "DEV-SERVER: up $(url)"; exit 0; fi
    echo "DEV-SERVER: down"; exit 1 ;;
  *)
    echo "usage: dev-server.sh start \"<command>\" [timeout] | stop | status" >&2; exit 3 ;;
esac
```

- [ ] **Step 4: Run to verify it passes** — `bash tests/run.sh`; `dev-server.test.sh` `0 failed`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/dev-server.test.sh skills/review-mine/scripts/dev-server.sh
git commit -m "feat: add dev-server lifecycle script for UI captures"
```

---

### Task 2: `capture.sh`

**Files:** Create `tests/scripts/capture.test.sh`, `skills/review-mine/scripts/capture.sh`.

**Interfaces:**
- Produces: `bash capture.sh <base-url> <routes-file> <out-dir>` → files `<out-dir>/<route>-<desktop|phone>-<light|dark>.png` (route `/` → `home`, `/a/b` → `a-b`), prints `CAPTURE: ok <n>` (or `CAPTURE: ok <n> (fallback: light only)`) / `CAPTURE: could-not-run <reason>`; exit 0 or 3. `CAPTURE_PW` overrides the Playwright command (default `npx --yes playwright`, or what the spike found); `CHROME_BIN` overrides the Chrome path.

- [ ] **Step 1: Failing test**

`tests/scripts/capture.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
CP="$ROOT/skills/review-mine/scripts/capture.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '/\n# comment\n/pricing/plans\n' > "$tmp/routes.txt"
cat > "$tmp/pw-ok.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/pw-args.log"; for last; do :; done; printf 'PNG' > "$last"
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/pw-bad.sh"
cat > "$tmp/chrome-ok.sh" <<'SH'
#!/usr/bin/env bash
for a; do case $a in --screenshot=*) printf 'PNG' > "${a#--screenshot=}" ;; esac; done
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/chrome-bad.sh"
chmod +x "$tmp"/*.sh

out=$(CAPTURE_PW="$tmp/pw-ok.sh" bash "$CP" http://127.0.0.1:1234/ "$tmp/routes.txt" "$tmp/shots a"); code=$?
assert_eq 0 "$code" "playwright path exits 0"
assert_eq "CAPTURE: ok 8" "$out" "2 routes x 2 viewports x 2 schemes"
for f in home-desktop-light home-desktop-dark home-phone-light home-phone-dark pricing-plans-desktop-light pricing-plans-phone-dark; do
  assert_file "$tmp/shots a/$f.png" "$f.png"
done
args=$(cat "$tmp/pw-args.log")
assert_contains "$args" "--viewport-size=390,844 --full-page --color-scheme=dark http://127.0.0.1:1234/pricing/plans" "phone dark args"
assert_contains "$args" "--viewport-size=1440,900" "desktop size"

out=$(CAPTURE_PW="$tmp/pw-bad.sh" CHROME_BIN="$tmp/chrome-ok.sh" bash "$CP" http://127.0.0.1:1234 "$tmp/routes.txt" "$tmp/shots b"); code=$?
assert_eq 0 "$code" "chrome fallback exits 0"
assert_eq "CAPTURE: ok 4 (fallback: light only)" "$out" "fallback captures light only"
assert_file "$tmp/shots b/home-phone-light.png" "fallback file"

out=$(CAPTURE_PW="$tmp/pw-bad.sh" CHROME_BIN="$tmp/chrome-bad.sh" bash "$CP" http://127.0.0.1:1234 "$tmp/routes.txt" "$tmp/shots c"); code=$?
assert_eq 3 "$code" "nothing works is could-not-run"
assert_contains "$out" "CAPTURE: could-not-run" "reason"
out=$(bash "$CP" http://x "$tmp/missing.txt" "$tmp/d"); assert_eq 3 $? "missing routes file"
finish
```

- [ ] **Step 2: Run it to verify it fails** — `bash tests/run.sh`.

- [ ] **Step 3: Implement**

`skills/review-mine/scripts/capture.sh`:
```bash
#!/usr/bin/env bash
# Screenshot routes of a running site for the graded bar.
# Usage: capture.sh <base-url> <routes-file> <out-dir>
# Routes file: one path per line ("/", "/pricing"); "#" starts a comment.
# Writes <out-dir>/<route>-<desktop|phone>-<light|dark>.png with the Playwright CLI
# (CAPTURE_PW overrides the command, default "npx --yes playwright"); falls back to Chrome
# headless (CHROME_BIN, default the macOS app), which captures light mode only.
# Prints "CAPTURE: ok <n>[ (fallback: light only)]" or "CAPTURE: could-not-run <reason>". Exit 0 or 3.
set -u
base=${1:-}; routes=${2:-}; out=${3:-}
[ -n "$base" ] && [ -f "$routes" ] && [ -n "$out" ] || { echo "CAPTURE: could-not-run (usage: capture.sh <base-url> <routes-file> <out-dir>)"; exit 3; }
mkdir -p "$out" || { echo "CAPTURE: could-not-run (cannot create $out)"; exit 3; }
pw=${CAPTURE_PW:-npx --yes playwright}
chrome=${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}
base=${base%/}
log="$out/capture.log"
slug() { s=$(printf '%s' "$1" | sed -E 's#^/+##; s#/+$##; s#[^A-Za-z0-9._-]+#-#g'); if [ -n "$s" ]; then printf '%s' "$s"; else printf 'home'; fi; }
shot_pw() { $pw screenshot --viewport-size="$1" --full-page --color-scheme="$2" "$3" "$4" >> "$log" 2>&1; }
shot_chrome() { "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size="$1" --screenshot="$3" "$2" >> "$log" 2>&1; }

mode=playwright; n=0; failed=0
while IFS= read -r r || [ -n "$r" ]; do
  r=${r%%#*}; r=$(printf '%s' "$r" | tr -d '[:space:]'); [ -n "$r" ] || continue
  url="$base/${r#/}"; s=$(slug "$r")
  for v in "desktop 1440,900" "phone 390,844"; do
    dev=${v%% *}; size=${v#* }
    for scheme in light dark; do
      f="$out/$s-$dev-$scheme.png"
      if [ "$mode" = playwright ]; then
        if shot_pw "$size" "$scheme" "$url" "$f" && [ -s "$f" ]; then n=$((n + 1)); continue; fi
        mode=chrome
      fi
      [ "$scheme" = dark ] && continue   # Chrome headless has no dark-mode switch
      if [ -x "$chrome" ] && shot_chrome "$size" "$url" "$f" && [ -s "$f" ]; then n=$((n + 1)); else failed=1; fi
    done
  done
done < "$routes"

if [ "$failed" -eq 1 ] || [ "$n" -eq 0 ]; then
  echo "CAPTURE: could-not-run (no screenshot tool worked; see $log)"; exit 3
fi
if [ "$mode" = chrome ]; then echo "CAPTURE: ok $n (fallback: light only)"; else echo "CAPTURE: ok $n"; fi
```

Note: once Playwright fails, later shots use Chrome, and shots already taken with Playwright stay; the fallback count in the test (4) assumes Playwright failed on the first shot.

- [ ] **Step 4: Run to verify it passes** — `bash tests/run.sh`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/capture.test.sh skills/review-mine/scripts/capture.sh
git commit -m "feat: add screenshot capture script with chrome fallback"
```

---

### Task 3: `graded-ab.sh`

**Files:** Create `tests/scripts/graded-ab.test.sh`, `skills/review-mine/scripts/graded-ab.sh`.

**Interfaces:**
- Produces: `bash graded-ab.sh prepare <reference-dir> <ours-dir> <out-dir>` → `<out-dir>/A`, `<out-dir>/B` (random; `GRADED_AB_FORCE=A|B` fixes it for tests), mapping in `<out-dir>.mapping` (`ours=A|B`, outside the scorer's folder). `bash graded-ab.sh verdict <mapping> <scores>... [--margin M] [--floor F] [--min N]` → one `GRADED: pass|fail ours=<x.xx> reference=<y.yy> lowest=<z.z> (scorer <k>)[ — <reasons>]` line per scores file; exit 0 if all pass, 1 if any fails, 2 bad input. Scores file lines: `A <criterion>: <score>`, `B <criterion>: <score>`; other lines ignored.

- [ ] **Step 1: Failing test**

`tests/scripts/graded-ab.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
GA="$ROOT/skills/review-mine/scripts/graded-ab.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/ref" "$tmp/ours"; echo r > "$tmp/ref/home.png"; echo o > "$tmp/ours/home.png"

GRADED_AB_FORCE=B bash "$GA" prepare "$tmp/ref" "$tmp/ours" "$tmp/ab dir"; assert_eq 0 $? "prepare exits 0"
assert_eq o "$(cat "$tmp/ab dir/B/home.png")" "ours in B when forced"
assert_eq r "$(cat "$tmp/ab dir/A/home.png")" "reference in A"
assert_eq "ours=B" "$(cat "$tmp/ab dir.mapping")" "mapping recorded"
[ -e "$tmp/ab dir/mapping" ] || [ -e "$tmp/ab dir/.mapping" ] && _ko "mapping visible to the scorer" || _ok

printf 'A Layout fidelity: 4.5\nA Responsiveness: 4\nB Layout fidelity: 4.2\nB Responsiveness: 4\nGAP B Responsiveness: wraps\n' > "$tmp/s1.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s1.txt"); code=$?
assert_eq 0 "$code" "within margin passes"
assert_contains "$out" "GRADED: pass ours=4.10 reference=4.25 lowest=4.0 (scorer 1)" "pass line"

printf 'A Layout fidelity: 4.8\nA Responsiveness: 4.8\nB Layout fidelity: 4.2\nB Responsiveness: 4\n' > "$tmp/s2.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s1.txt" "$tmp/s2.txt"); code=$?
assert_eq 1 "$code" "confirming scorer fails the bar"
assert_contains "$out" "(scorer 2) — below reference by 0.70" "reason names the gap"

printf 'A Layout fidelity: 3\nA Responsiveness: 3\nB Layout fidelity: 3\nB Responsiveness: 3\n' > "$tmp/s3.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s3.txt"); assert_eq 1 $? "below floor fails"
assert_contains "$out" "below floor 3.50" "floor reason"
printf 'A x: 5\nA y: 5\nB x: 5\nB y: 2.5\n' > "$tmp/s4.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s4.txt" --floor 3); assert_eq 1 $? "one low criterion fails"
assert_contains "$out" "a criterion scored 2.5" "min reason"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s3.txt" --floor 3); assert_eq 0 $? "--floor overrides"

printf 'A x: 4\n' > "$tmp/bad.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad.txt" >/dev/null 2>&1; assert_eq 2 $? "missing side is bad input"
printf 'A x: 4\nA y: 4\nB x: 4\n' > "$tmp/bad2.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad2.txt" >/dev/null 2>&1; assert_eq 2 $? "unequal counts is bad input"
finish
```

- [ ] **Step 2: Run it to verify it fails** — `bash tests/run.sh`.

- [ ] **Step 3: Implement**

`skills/review-mine/scripts/graded-ab.sh`:
```bash
#!/usr/bin/env bash
# Blind A/B setup and pass/fail verdict for the graded (UI) bar.
# Usage: graded-ab.sh prepare <reference-dir> <ours-dir> <out-dir>
#          Copies the two image sets into <out-dir>/A and <out-dir>/B in random order and records which
#          one is ours in <out-dir>.mapping, outside the folder the scorer reads.
#        graded-ab.sh verdict <mapping-file> <scores-file>... [--margin M] [--floor F] [--min N]
#          Scores files hold "A <criterion>: <score>" and "B <criterion>: <score>" lines.
#          Every scores file must pass (the second one is the confirming scorer).
# Exit: 0 pass / ok, 1 fail, 2 bad input.
set -u
cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
  prepare)
    ref=${1:-}; ours=${2:-}; out=${3:-}
    [ -d "$ref" ] && [ -d "$ours" ] && [ -n "$out" ] || { echo "usage: graded-ab.sh prepare <reference-dir> <ours-dir> <out-dir>" >&2; exit 2; }
    side=${GRADED_AB_FORCE:-}
    if [ -z "$side" ]; then if [ $((RANDOM % 2)) -eq 0 ]; then side=A; else side=B; fi; fi
    other=B; [ "$side" = B ] && other=A
    rm -rf "$out" && mkdir -p "$out/A" "$out/B" || exit 2
    cp -R "$ours/." "$out/$side/" && cp -R "$ref/." "$out/$other/" || exit 2
    printf 'ours=%s\n' "$side" > "$out.mapping" ;;
  verdict)
    map=${1:-}; [ $# -gt 0 ] && shift
    [ -f "$map" ] || { echo "mapping not found: $map" >&2; exit 2; }
    ours=$(sed -n 's/^ours=//p' "$map")
    case $ours in A|B) ;; *) echo "bad mapping: $map" >&2; exit 2 ;; esac
    margin=0.3; floor=3.5; min=3; files=""
    while [ $# -gt 0 ]; do
      case $1 in
        --margin) margin=$2; shift 2 ;;
        --floor) floor=$2; shift 2 ;;
        --min) min=$2; shift 2 ;;
        *) files="$files
$1"; shift ;;
      esac
    done
    [ -n "$files" ] || { echo "no scores files" >&2; exit 2; }
    status=0; k=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -f "$f" ] || { echo "scores not found: $f" >&2; exit 2; }
      k=$((k + 1))
      res=$(awk -v ours="$ours" -v margin="$margin" -v floor="$floor" -v min="$min" '
        /^[AB] [^:]+:[[:space:]]*[0-9.]+[[:space:]]*$/ {
          s = $1; v = $NF + 0; sum[s] += v; cnt[s]++
          if (s == ours && (!seen || v < lo)) { lo = v; seen = 1 }
        }
        END {
          ref = (ours == "A") ? "B" : "A"
          if (cnt[ours] == 0 || cnt[ref] == 0 || cnt[ours] != cnt[ref]) { print "bad"; exit }
          o = sum[ours] / cnt[ours]; r = sum[ref] / cnt[ref]; why = ""
          if (o < r - margin - 1e-9) why = why sprintf(" below reference by %.2f", r - o)
          if (o < floor - 1e-9) why = why sprintf(" below floor %.2f", floor)
          if (lo < min - 1e-9) why = why sprintf(" a criterion scored %.1f", lo)
          printf "%s|%.2f|%.2f|%.1f|%s\n", (why == "" ? "pass" : "fail"), o, r, lo, why
        }' "$f")
      [ "$res" != bad ] || { echo "bad scores in $f" >&2; exit 2; }
      verdict=${res%%|*}; rest=${res#*|}
      o=${rest%%|*}; rest=${rest#*|}; r=${rest%%|*}; rest=${rest#*|}; lo=${rest%%|*}; why=${rest#*|}
      if [ -n "$why" ]; then
        echo "GRADED: $verdict ours=$o reference=$r lowest=$lo (scorer $k) —$why"
      else
        echo "GRADED: $verdict ours=$o reference=$r lowest=$lo (scorer $k)"
      fi
      [ "$verdict" = pass ] || status=1
    done <<EOF
$files
EOF
    exit "$status" ;;
  *) echo "usage: graded-ab.sh prepare|verdict ..." >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run to verify it passes** — `bash tests/run.sh`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/graded-ab.test.sh skills/review-mine/scripts/graded-ab.sh
git commit -m "feat: add blind A/B setup and verdict for the graded bar"
```

---

### Task 4: `pr-state.sh` and branch-name ID check

**Files:** Create `tests/scripts/pr-state.test.sh`, `skills/ticket-workspace/scripts/pr-state.sh`; modify `skills/ticket-workspace/scripts/branch-name.sh`, `tests/scripts/branch-name.test.sh`.

**Interfaces:**
- Produces: `bash pr-state.sh <pr-url-or-number>` → prints `merged`, `open`, or `closed-unmerged` (exit 0), or `could-not-run` (exit 3). `branch-name.sh` exits 2 when the ID slugs to nothing.

- [ ] **Step 1: Failing tests**

`tests/scripts/pr-state.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
PS="$ROOT/skills/ticket-workspace/scripts/pr-state.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "$STUB_STATE" = ERROR ] && exit 1
echo "$STUB_STATE"
SH
chmod +x "$tmp/bin/gh"
for pair in MERGED:merged OPEN:open CLOSED:closed-unmerged; do
  out=$(STUB_STATE=${pair%%:*} PATH="$tmp/bin:$PATH" bash "$PS" https://github.com/me/x/pull/7); assert_eq "${pair#*:}" "$out" "$pair"
done
out=$(STUB_STATE=ERROR PATH="$tmp/bin:$PATH" bash "$PS" 7); assert_eq 3 $? "gh failure is could-not-run"
assert_eq could-not-run "$out" "could-not-run printed"
out=$(PATH="/usr/bin:/bin" bash "$PS" 7); assert_eq 3 $? "no gh is could-not-run"
finish
```

Append to `tests/scripts/branch-name.test.sh` before `finish`:
```bash
bash "$BN" feat "#" "x" >/dev/null 2>&1; assert_eq 2 $? "ID that slugs to nothing is refused"
bash "$BN" feat "票据" "x" >/dev/null 2>&1; assert_eq 2 $? "non-Latin ID is refused"
```

- [ ] **Step 2: Run to verify they fail** — `bash tests/run.sh`.

- [ ] **Step 3: Implement**

`skills/ticket-workspace/scripts/pr-state.sh`:
```bash
#!/usr/bin/env bash
# State of a pull request, for CLOSE.
# Usage: pr-state.sh <pr-url-or-number>
# Prints merged | open | closed-unmerged (exit 0) or could-not-run (exit 3).
set -u
pr=${1:-}
[ -n "$pr" ] || { echo could-not-run; exit 3; }
command -v gh >/dev/null 2>&1 || { echo could-not-run; exit 3; }
s=$(gh pr view "$pr" --json state --jq .state 2>/dev/null) || { echo could-not-run; exit 3; }
case $s in
  MERGED) echo merged ;;
  OPEN) echo open ;;
  CLOSED) echo closed-unmerged ;;
  *) echo could-not-run; exit 3 ;;
esac
```

In `branch-name.sh`, replace `name="$type/$(slug "$id")"` with:
```bash
idslug=$(slug "$id")
[ -n "$idslug" ] || { echo "ticket ID has no usable characters: $id (use a Latin ID such as T-1)" >&2; exit 2; }
name="$type/$idslug"
```

- [ ] **Step 4: Run to verify they pass** — `bash tests/run.sh`.

- [ ] **Step 5: Commit**
```bash
git add tests/scripts/pr-state.test.sh tests/scripts/branch-name.test.sh skills/ticket-workspace/scripts
git commit -m "feat: add pr-state script and refuse empty ticket IDs"
```

---

### Task 5: `ui-scorer` agent and validation

**Files:** Create `agents/ui-scorer.md`; modify `scripts/validate.sh`, `tests/scripts/validate.test.sh`.

**Interfaces:** Produces the scorer output contract consumed by `graded-ab.sh verdict` and the review loop's gap list.

- [ ] **Step 1: Failing validate test** — append before `finish` in `tests/scripts/validate.test.sh`:
```bash
fresh; sed -i.bak 's/^tools: Read, Glob$/tools: Read, Glob, Write/' "$tmp/repo/agents/ui-scorer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "read-only agent has write tools: agents/ui-scorer.md" "ui-scorer is read-only"
```

- [ ] **Step 2: Run to verify it fails** — `bash tests/run.sh`.

- [ ] **Step 3: Write `agents/ui-scorer.md`**

````markdown
---
name: ui-scorer
description: Blind, read-only scorer for the graded (UI) bar. Scores two screenshot sets, A and B, on the same rubric without knowing which one is the work under review.
tools: Read, Glob
model: opus
---

You compare two screenshot sets of web pages against a rubric. One set is a reference and one is work under review; you are not told which, and you must not guess. Judge only what the rubric asks.

## Inputs (given in your dispatch)
- `DIR_A`, `DIR_B`: folders of PNG screenshots (`<route>-<desktop|phone>-<light|dark>.png`).
- `RUBRIC`: criteria, each with written anchors for scores 1, 3 and 5.

## How to score
1. Glob both folders and Read every image. Compare the same route, viewport and scheme side by side.
2. Score every criterion for A and for B from 1 to 5 (one decimal allowed), using the anchors. Ignore differences in copy, brand names and logos unless the rubric names them.
3. For every criterion where a side scores below 4, write one concrete, actionable gap (what is wrong, where, at which viewport).

## Output (exactly these lines, nothing before them)
```
A <criterion>: <score>
B <criterion>: <score>
GAP A <criterion>: <gap>
GAP B <criterion>: <gap>
```
List every criterion for both A and B, using the rubric's exact criterion names.
````

- [ ] **Step 4: Update `scripts/validate.sh`** — change `for f in agents/final-reviewer.md agents/task-reviewer.md; do` to `for f in agents/final-reviewer.md agents/task-reviewer.md agents/ui-scorer.md; do`.

- [ ] **Step 5: Run to verify** — `./scripts/validate.sh && bash tests/run.sh`.

- [ ] **Step 6: Commit**
```bash
git add agents/ui-scorer.md scripts/validate.sh tests/scripts/validate.test.sh
git commit -m "feat: add blind ui-scorer agent"
```

---

### Task 6: Graded bar in `review-mine`, rerun budget, timestamps

**Files:** Modify `skills/review-mine/SKILL.md`.

**Interfaces:**
- Consumes: Tasks 1–3, 5.
- Produces: `--graded <graded.md>` flag. `graded.md` format:
```
dev: <command; use $PORT>
routes: <path to a routes file>
reference: image-dir:<path> | route:<path on the same site> | url:<http(s) url>
rubric: <path to rubric.md>
margin: 0.3
floor: 3.5
min: 3
```

- [ ] **Step 1: Edit `skills/review-mine/SKILL.md`**

1. In section 1 add:
```markdown
- `--graded <graded.md>`: adds the graded (UI) bar (section 4b). Adds 5 to the review budget (3 for lite).
```
2. In "Rules for the whole run" add: "Ledger lines use `date -u +%Y-%m-%dT%H:%M:%SZ` for the time; never type a time by hand."
3. In the embedded-mode bullet add: "If `<WS>/state.md` already exists with `status: running`, this is a rerun after a crash: keep its `budget_used`, `round` and findings and continue from them."
4. Insert a new section after section 4:
````markdown
## 4b. Graded bar (only with `--graded`)
Run in round 1 and after every fix round, before the re-review decides the exit.
1. `bash "$SKILL_DIR/scripts/dev-server.sh" start "<dev>" 120`. `could-not-run` → the graded bar is `could-not-run` (reported, never skipped silently); go on without it.
2. `bash "$SKILL_DIR/scripts/capture.sh" <url> <routes> "<WS>/graded/round-<N>/ours"`. Reference, once per run: `route:` → capture `<url><path>` the same way into `<WS>/graded/reference`; `url:` → capture that URL; `image-dir:` → use the folder as-is.
3. Always `bash "$SKILL_DIR/scripts/dev-server.sh" stop` before going on, even after a failure.
4. `bash "$SKILL_DIR/scripts/graded-ab.sh" prepare "<WS>/graded/reference" "<WS>/graded/round-<N>/ours" "<WS>/graded/round-<N>/ab"`.
5. Dispatch `patrick-workflows:ui-scorer` (model opus, +1 budget) with `DIR_A`, `DIR_B` (the two `ab` folders) and `RUBRIC`. Save its output to `<WS>/graded/round-<N>/score-1.txt`.
6. `bash "$SKILL_DIR/scripts/graded-ab.sh" verdict "<WS>/graded/round-<N>/ab.mapping" score-1.txt --margin <m> --floor <f> --min <n>`. If it passes, dispatch a second, fresh `ui-scorer` (+1) into `score-2.txt` and run the verdict on both files; the bar is met only if both pass.
7. Not met: read the mapping to know which side is ours, turn each `GAP <ours> <criterion>` line into a finding (Kind: visual, Severity: Important, Location: the route and viewport, Trigger/Expected/Actual from the gap) for the next fix round. The fixer verifies visual fixes by recapturing, not with a red test.
8. Progress for the plateau rule (standard and full): ours overall rising by at least 0.2. Two rounds without that → stop and report the best score.
9. The report's Bars section lists ours and reference per round, e.g. `Graded: 3.4 → 3.9 → 4.2 (reference 4.4, margin 0.3)`.
````
5. In section 4 step 10 and section 6 step 2, add "and the graded bar is met (when `--graded` was given)" to the exit / ready conditions.

- [ ] **Step 2: Validate** — `./scripts/validate.sh && claude plugin validate .`

- [ ] **Step 3: Commit**
```bash
git add skills/review-mine/SKILL.md
git commit -m "feat: add the graded bar to review-mine"
```

---

### Task 7: Ticket stages: graded brief, type, close

**Files:** Modify `skills/ticket-plan/SKILL.md`, `skills/ticket-build/SKILL.md`, `skills/ticket-ship/SKILL.md`, `skills/ticket-workspace/SKILL.md`, `commands/ticket.md`; create `skills/ticket-close/SKILL.md`.

- [ ] **Step 1: `ticket-plan`**
- Section 4, step 1: after showing `BR`, add: "If the user renames it, check the new name with `git check-ref-format --branch <name>` and ask again if it fails." and "`S set type <feat|fix>`."
- Section 7: insert before "Permissions":
```markdown
5b. **Graded bar (optional, for UI or anything with a reference):** collect the reference (`image-dir:`, `route:` or `url:`), the routes to capture (write `WS/routes.txt`), and the dev command (use `$PORT`). Write `WS/rubric.md` with the user: 3–6 criteria, each with anchors for 1, 3 and 5. Write `WS/graded.md` in the format of `review-mine`'s `--graded` flag (margin 0.3, floor 3.5, min 3 unless the user changes them). `S set graded WS/graded.md`. Add `Bash(npx --yes playwright*)` and the dev command to the permission rules.
```
- [ ] **Step 2: `ticket-build`** — in section 3 step 2, add "`--graded \"<graded>\"` when `graded` is set".
- [ ] **Step 3: `ticket-ship`** — in report item 1 replace "The PR title type is `fix` if the branch starts with `fix/`, else `feat`." with "The PR title type is the `type` state key."; in item 6 add "graded scores per round".
- [ ] **Step 4: `ticket-workspace`** — state keys add `type`, `graded`; phase table: `pr` → `patrick-workflows:ticket-close`; add under Formats: "Ledger time: always `date -u +%Y-%m-%dT%H:%M:%SZ`." Scripts table add `pr-state.sh <pr>`.
- [ ] **Step 5: `commands/ticket.md`** — replace the `pr` sentence with "For `pr`, invoke `patrick-workflows:ticket-close`."
- [ ] **Step 6: Create `skills/ticket-close/SKILL.md`**
````markdown
---
name: ticket-close
description: CLOSE stage of /ticket - once the ticket's PR is merged, marks the ticket done, cleans up the branch and worktree, and closes the workspace. Changes nothing while the PR is not merged.
---

# CLOSE

Read `patrick-workflows:ticket-workspace` first. `S` = `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" <WS>/state.md`. Ask nothing; running `/ticket <id>` is the request.

1. Phase must be `pr`. `STATE=$(bash "$SKILL_DIR/../ticket-workspace/scripts/pr-state.sh" <pr_url>)`.
   - `open` → say the PR is still open (and its URL); change nothing.
   - `closed-unmerged` → say it was closed without merging; change nothing; suggest reopening or starting a new round with `/ticket <id>` after reopening.
   - `could-not-run` → say `gh` could not read the PR; change nothing.
2. `merged`:
   1. Mark the ticket done with what the machine offers: a GitHub issue → `gh issue close <n> --comment "Done in <pr_url>"`; another tracker → its MCP tool if available; otherwise print the one manual step. Report which happened.
   2. If the session is in the ticket's worktree, `ExitWorktree` with `action: "keep"` first.
   3. If the tree is clean: `git switch <base_branch>` and, when a remote exists, `git pull --ff-only`. Delete the local branch with `git branch -d <branch>` (never `-D`; if git refuses, report it and leave the branch).
   4. If `checkout` is a worktree path: `git worktree remove <path>` (never with `--force`; report a refusal).
   5. Ledger line with `date -u`; `S phase closed`. Tell the user the ticket is closed.
````
- [ ] **Step 7: Validate** — `./scripts/validate.sh && claude plugin validate .`
- [ ] **Step 8: Commit**
```bash
git add skills commands
git commit -m "feat: add graded brief, ticket type and the CLOSE stage"
```

---

### Task 8: UI fixture and graded smoke

**Files:** Create `tests/fixture/ui-setup.sh`, `tests/scripts/ui-setup.test.sh`, `tests/SMOKE-graded.md`.

**Interfaces:** `bash tests/fixture/ui-setup.sh <dest>` → a git repo with `server.js` (serves files from `site/` on `$PORT`), `site/reference.html` (the target design), `site/index.html` on `main` (a plain version) and branch `feat/landing` (a partial attempt that misses the reference's layout), plus `graded.md`, `routes.txt`, `rubric.md` at the repo root.

- [ ] **Step 1: Failing test** — `tests/scripts/ui-setup.test.sh`:
```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
tmp="$(mktemp -d)"; export REVIEW_WS="$tmp/ws"
DS="$ROOT/skills/review-mine/scripts/dev-server.sh"
trap 'bash "$DS" stop >/dev/null 2>&1; rm -rf "$tmp"' EXIT
bash "$ROOT/tests/fixture/ui-setup.sh" "$tmp/ui site" >/dev/null; assert_eq 0 $? "setup exits 0"
assert_eq "feat/landing" "$(git -C "$tmp/ui site" rev-parse --abbrev-ref HEAD)" "on the feature branch"
for f in graded.md routes.txt rubric.md server.js site/reference.html site/index.html; do assert_file "$tmp/ui site/$f" "$f"; done
cd "$tmp/ui site" || exit 1
out=$(bash "$DS" start "$(sed -n 's/^dev: //p' graded.md)" 20); assert_eq 0 $? "fixture dev server starts"
url=${out#DEV-SERVER: up }
assert_contains "$(curl -s "$url/reference.html")" "<h1" "reference served"
assert_contains "$(curl -s "$url/")" "<html" "index served"
finish
```
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Implement `tests/fixture/ui-setup.sh`**
````bash
#!/usr/bin/env bash
# Build the graded-bar fixture: a tiny static site with a reference page and a weaker landing page.
# Usage: ui-setup.sh <dest>
set -eu
dest=${1:?usage: ui-setup.sh <dest>}
[ ! -e "$dest" ] || { echo "already exists: $dest" >&2; exit 1; }
mkdir -p "$dest/site" && cd "$dest"
git init -q -b main
git config user.name "Fixture"; git config user.email "fixture@example.com"
cat > server.js <<'EOF'
const http = require('http'), fs = require('fs'), path = require('path');
http.createServer((req, res) => {
  const p = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  const f = path.join(__dirname, 'site', path.normalize(p).replace(/^(\.\.[\/\\])+/, ''));
  fs.readFile(f, (err, data) => { if (err) { res.statusCode = 404; return res.end('not found'); } res.setHeader('Content-Type', 'text/html'); res.end(data); });
}).listen(process.env.PORT, '127.0.0.1');
EOF
cat > site/reference.html <<'EOF'
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
body{margin:0;font-family:Georgia,serif;background:#f6f3ee;color:#1d2a35}
header{display:flex;justify-content:space-between;align-items:center;padding:20px 32px}
.hero{padding:72px 32px;max-width:720px}.hero h1{font-size:48px;line-height:1.1;margin:0 0 16px}
.cta{display:inline-block;background:#1d6b5f;color:#fff;padding:14px 22px;border-radius:6px;text-decoration:none}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;padding:0 32px 64px}
.card{background:#fff;padding:20px;border-radius:8px}
@media (max-width:600px){.hero h1{font-size:32px}.grid{grid-template-columns:1fr}}
@media (prefers-color-scheme:dark){body{background:#151b21;color:#e8e4dc}.card{background:#1f2730}}
</style></head><body><header><b>Fieldnote</b><a class="cta" href="#">Start free</a></header>
<section class="hero"><h1>Notes that keep up with your field work</h1><p>Capture, tag and share observations offline.</p><a class="cta" href="#">Start free</a></section>
<section class="grid"><div class="card"><h3>Offline first</h3><p>Works without signal.</p></div><div class="card"><h3>Photo tags</h3><p>Tag what you see.</p></div><div class="card"><h3>Team sync</h3><p>Share when back online.</p></div></section></body></html>
EOF
printf '<!doctype html><html><body><h1>Fieldnote</h1><p>Coming soon.</p></body></html>\n' > site/index.html
printf 'dev: PORT=$PORT node server.js\nroutes: routes.txt\nreference: route:/reference.html\nrubric: rubric.md\nmargin: 0.3\nfloor: 3.5\nmin: 3\n' > graded.md
printf '/\n' > routes.txt
cat > rubric.md <<'EOF'
# Landing page rubric
- Layout fidelity: 1 = no recognisable structure; 3 = header, hero and features present but misaligned; 5 = same structure and spacing as the reference.
- Visual hierarchy: 1 = everything the same weight; 3 = headline stands out, call to action does not; 5 = headline, call to action and features read in order at a glance.
- Responsiveness: 1 = broken or overflowing on phone; 3 = usable on phone but cramped; 5 = designed for phone, single column, readable.
- Dark mode: 1 = unreadable or unchanged; 3 = readable but harsh; 5 = deliberate dark palette with good contrast.
EOF
git add -A && git commit -q -m "base: site skeleton"
git switch -q -c feat/landing
cat > site/index.html <<'EOF'
<!doctype html><html><head><style>body{font-family:Arial;margin:40px} .cta{background:blue;color:white;padding:4px}</style></head>
<body><h1>Fieldnote</h1><p>Notes that keep up with your field work.</p><a class="cta" href="#">Start free</a>
<h3>Offline first</h3><h3>Photo tags</h3><h3>Team sync</h3></body></html>
EOF
git add -A && git commit -q -m "feat: first landing page attempt"
echo "$dest"
````
Ruling recorded here: the `dev:` command starts with `PORT=$PORT` only because the server reads `PORT`; `dev-server.sh` already exports `PORT`, so `node server.js` alone also works.

- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Write `tests/SMOKE-graded.md`**
````markdown
# Graded bar smoke test
```bash
bash tests/fixture/ui-setup.sh /tmp/ui-site && cd /tmp/ui-site
claude -p --plugin-dir "<repo>" --permission-mode acceptEdits \
  --allowedTools "Read(~/.patrick-workflows/**)" "Edit(~/.patrick-workflows/**)" "Bash(bash *)" "Bash(git *)" "Bash(node *)" "Bash(npx --yes playwright*)" "Bash(curl *)" "Skill" "Agent" "Read" "Grep" "Glob" "Write" "Edit" \
  -- "/patrick-workflows:review-mine main --graded graded.md --depth standard" < /dev/null
```
- [ ] Dev server started and stopped (no `node server.js` left running: `pgrep -f "node server.js"` is empty).
- [ ] `graded/reference` and `graded/round-1/ours` contain 4 PNGs each.
- [ ] Two scorer files when round 1 passes; one when it fails; `graded-ab.sh verdict` lines in the report.
- [ ] Gaps became visual findings for the fixer; scores improve across rounds or the run stops on plateau/cap with the best score reported.
- [ ] The scorer's folders never contain the mapping file.
````
- [ ] **Step 6: Run the smoke** (headless, background) and tick the boxes from the workspace. Any failure in a script is fixed test-first.
- [ ] **Step 7: Commit**
```bash
git add tests/fixture/ui-setup.sh tests/scripts/ui-setup.test.sh tests/SMOKE-graded.md
git commit -m "test: add graded bar fixture and smoke checklist"
```

---

### Task 9: README and version

- [ ] **Step 1:** README `/review-mine` usage line gains `[--graded <graded.md>]`; add a short "UI grading" paragraph (what `graded.md` holds, that screenshots need Playwright via `npx` or Chrome, the pass rule, and the `Bash(npx --yes playwright*)` allow rule). In the `/ticket` section replace "Marking the ticket done after merge (CLOSE) and UI grading come in later versions." with "After the PR is merged, run `/ticket <id>` once more: it marks the ticket done and cleans up."
- [ ] **Step 2:** `.claude-plugin/plugin.json` version `0.3.0` → `0.4.0`.
- [ ] **Step 3:** `./scripts/validate.sh && bash tests/run.sh && claude plugin validate .` all green.
- [ ] **Step 4:** Commit `docs: document UI grading and CLOSE, bump version to 0.4.0`; tag `v0.4.0`. Do not push.
