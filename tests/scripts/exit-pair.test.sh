#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
EP="$ROOT/skills/review-mine/scripts/exit-pair.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export REVIEW_WS="$tmp/ws"
cd "$tmp" || exit 1

# prove pops the next exit code from $tmp/seq
cat > "$tmp/next.sh" <<'SH'
seq="$1"; code=$(head -n 1 "$seq"); tail -n +2 "$seq" > "$seq.tmp" && mv "$seq.tmp" "$seq"; exit "${code:-1}"
SH
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
