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
assert_contains "$(cat "$REVIEW_WS/logs/bad.status")" "GATE bad: fail (exit 3" "status line recorded next to the log"

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

repo="$tmp/repo"; mkdir -p "$repo"; git -C "$repo" init -q
out=$(cd "$repo" && REVIEW_WS= bash "$GATE" nows 5 -- "true"); code=$?
assert_eq 3 "$code" "no REVIEW_WS and no pointer is could-not-run"
printf '%s\n' "$tmp/from pointer" > "$repo/.git/patrick-workflows-review-ws"
out=$(cd "$repo" && REVIEW_WS= bash "$GATE" ptr 5 -- "echo via-pointer"); code=$?
assert_eq 0 "$code" "pointer file used when REVIEW_WS is unset"
assert_contains "$(cat "$tmp/from pointer/logs/ptr.log")" "via-pointer" "log written to pointer workspace"

finish
