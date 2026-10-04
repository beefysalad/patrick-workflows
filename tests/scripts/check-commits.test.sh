#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
CC="$ROOT/scripts/check-commits.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q .
git config user.email t@example.com
git config user.name t
git config commit.gpgsign false

git commit -q --allow-empty -m "base commit"
git commit -q --allow-empty -m "clean commit"
clean=$(git rev-parse --short HEAD)
git commit -q --allow-empty -m "$(printf 'bad commit\n\nCo-%s: Claude Test <t@example.com>\n' "Authored-By")"
bad=$(git rev-parse --short HEAD)
git commit -q --allow-empty -m "$(printf 'bad footer\n\nGenerated with [Claude%s]\n' " Code")"
bad2=$(git rev-parse --short HEAD)

out=$(bash "$CC" HEAD~3..HEAD~2 2>&1); rc=$?
assert_eq 0 "$rc" "clean range exits 0"
assert_contains "$out" "OK: no attribution in commit messages" "clean range prints OK"

out=$(bash "$CC" HEAD~3..HEAD~1 2>&1); rc=$?
assert_eq 1 "$rc" "trailer range exits 1"
assert_contains "$out" "attribution trailer in $bad bad commit" "prints short sha and subject"
assert_not_contains "$out" "$clean" "clean commit not flagged"

out=$(bash "$CC" HEAD~1..HEAD 2>&1); rc=$?
assert_eq 1 "$rc" "footer range exits 1"
assert_contains "$out" "attribution trailer in $bad2" "footer commit flagged"

out=$(bash "$CC" 2>&1); rc=$?
assert_eq 1 "$rc" "default range without origin/main falls back to HEAD"
finish
