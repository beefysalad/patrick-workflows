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
out=$(cd "$dest" && node --test test/*.test.js 2>&1)
assert_contains "$out" "known red" "base has the known red test"
assert_contains "$out" "# fail 1" "exactly one failing test on base"
finish
