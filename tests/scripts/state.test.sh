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

bash "$ST" "$f" set exit_pair "--db-pattern 'test\.db\$'"
bash "$ST" "$f" set exit_pair "--db-pattern 'app\.db\$'"
assert_eq "--db-pattern 'app\.db\$'" "$(bash "$ST" "$f" get exit_pair)" "backslashes survive an overwrite"
finish
