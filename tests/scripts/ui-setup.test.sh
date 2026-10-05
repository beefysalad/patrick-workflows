#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
tmp="$(mktemp -d)"; export REVIEW_WS="$tmp/ws"
DS="$ROOT/skills/gauntlet-review/scripts/dev-server.sh"
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
