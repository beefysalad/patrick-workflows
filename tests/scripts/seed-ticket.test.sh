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
