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

# Test 1: leaked fd 3 should not hang caller when capturing output with 2>&1
out=$(perl -e 'alarm 10; exec @ARGV' bash "$DS" start "$srv" 10 2>&1); code=$?
assert_eq 0 "$code" "fd 3 leak test returns successfully"
assert_contains "$out" "DEV-SERVER: up http://127.0.0.1:" "fd 3 test prints the up line"
bash "$DS" stop

# Test 2: signal trap during start should clean up server on interrupt
bash "$DS" start "sleep 45" 30 &
bg_pid=$!
sleep 1
kill -TERM $bg_pid 2>/dev/null
wait $bg_pid
pgrep -f "sleep 45" >/dev/null && _ko "server process still running after SIGTERM" || _ok
[ -f "$REVIEW_WS/dev-server.pid" ] && _ko "pid file still exists after SIGTERM" || _ok

# A recycled PID (a stale file pointing at someone else's process) is never "up" and never signalled.
bash "$DS" stop >/dev/null 2>&1
sleep 30 & other=$!
mkdir -p "$REVIEW_WS"; echo "$other" > "$REVIEW_WS/dev-server.pid"; echo 1 > "$REVIEW_WS/dev-server.port"
out=$(bash "$DS" status); assert_eq "1:DEV-SERVER: down" "$?:$out" "foreign PID is not our server"
bash "$DS" stop >/dev/null 2>&1
kill -0 "$other" 2>/dev/null && _ok || _ko "stop killed an unrelated process"
kill "$other" 2>/dev/null
finish
