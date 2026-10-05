#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
EP="$ROOT/skills/gauntlet-review/scripts/exit-pair.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export REVIEW_WS="$tmp/ws"
cd "$tmp" || exit 1

# prove pops the next exit code from $tmp/seq
cat > "$tmp/next.sh" <<'SH'
seq="$1"; code=$(head -n 1 "$seq"); tail -n +2 "$seq" > "$seq.tmp" && mv "$seq.tmp" "$seq"; exit "${code:-1}"
SH
run() { printf '%s\n' $1 > "$tmp/seq"; shift; bash "$EP" --prove "bash '$tmp/next.sh' '$tmp/seq'" "$@"; }

out=$(run "0 0"); assert_eq 0 $? "pass pass"; assert_contains "$out" "EXIT-PAIR: pass" "pass line"
assert_contains "$(cat "$REVIEW_WS/exit-pair.txt")" "EXIT-PAIR: pass" "result line recorded in the workspace"
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

rm -f "$tmp/reset.marker"
printf 'DATABASE_URL="host=prod.example.com dbname=app_test"\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "$reset_cmd" --env-file "$tmp/.env.test" --db-pattern '_test'); assert_eq 4 $? "libpq keyword form with remote host refused"
printf 'DATABASE_URL=prod.example.com:5432/app_test\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "$reset_cmd" --env-file "$tmp/.env.test" --db-pattern '_test$'); assert_eq 4 $? "scheme-less host:port value refused"
[ -f "$tmp/reset.marker" ] && _ko "reset ran for an unrecognised value" || _ok
printf 'DATABASE_URL="host=localhost dbname=app_test"\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "true" --env-file "$tmp/.env.test" --db-pattern '_test'); assert_eq 0 $? "libpq keyword form with local host accepted"
printf 'DATABASE_URL=postgres://u:pa@ss@prod.example.com/app_test\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "true" --env-file "$tmp/.env.test" --db-pattern '_test$'); assert_eq 4 $? "unencoded @ in password still refused"
assert_not_contains "$out" "ss@" "no part of the password is printed"
assert_contains "$out" "prod.example.com" "the real host is named"
printf 'DATABASE_URL=file:./test.db\n' > "$tmp/.env.test"
out=$(run "0 0" --reset "true" --env-file "$tmp/.env.test" --db-pattern 'test\.db$'); assert_eq 0 $? "file database treated as local"

out=$(bash "$EP" --reset "true"); assert_eq 3 $? "missing --prove is could-not-run"
git init -q "$tmp/r2"; printf '%s\n' "$tmp/ws2" > "$tmp/r2/.git/patrick-workflows-review-ws"
out=$(cd "$tmp/r2" && printf '0\n0\n' > "$tmp/seq" && REVIEW_WS= bash "$EP" --prove "bash '$tmp/next.sh' '$tmp/seq'"); assert_eq 0 $? "exit pair finds workspace via pointer"
assert_file "$tmp/ws2/logs/exit-pair-1-prove.log" "exit pair logs go to pointer workspace"

printf '0\n0\n' > "$tmp/seq"
out=$(bash "$EP" --label round3 --prove "bash '$tmp/next.sh' '$tmp/seq'"); assert_eq 0 $? "labelled run passes"
assert_file "$REVIEW_WS/logs/round3-1-prove.log" "label used in log names"
printf 'DATABASE_URL=postgres://prod.example.com/app_test\n' > "$tmp/.env.check"
out=$(bash "$EP" --check --prove "true" --reset "echo x >> '$tmp/check.marker'" --env-file "$tmp/.env.check" --db-pattern '_test$'); assert_eq 4 $? "--check refuses remote"
printf 'DATABASE_URL=file:./t_test.db\n' > "$tmp/.env.check"
out=$(bash "$EP" --check --prove "true" --reset "echo x >> '$tmp/check.marker'" --env-file "$tmp/.env.check" --db-pattern '_test\.db$'); assert_eq 0 $? "--check accepts safe target"
assert_contains "$out" "EXIT-PAIR: safe" "--check reports safe"
[ -f "$tmp/check.marker" ] && _ko "--check ran reset" || _ok
finish
