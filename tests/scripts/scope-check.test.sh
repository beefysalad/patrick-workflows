#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SC="$ROOT/skills/gauntlet-review/scripts/scope-check.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main
mkdir -p src/billing docs
echo a > src/a.js; echo r > src/billing/rates.js; echo d > docs/x.md
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
base=$(git rev-parse HEAD)

printf '# scope\nallow: src/**\nforbid: src/billing/**\n' > "$tmp/scope.txt"

echo b >> src/a.js; echo '{}' > package-lock.json; echo y >> docs/x.md; echo z > "src/my file.js"
mkdir -p tests/__snapshots__ && echo s > tests/__snapshots__/a.snap
git add -A && git -c user.name=t -c user.email=t@t commit -q -m change
out=$(bash "$SC" "$base" "$tmp/scope.txt"); code=$?
assert_eq 0 "$code" "no forbidden file exits 0"
assert_contains "$out" "$(printf 'in-scope\tsrc/a.js')" "allow match"
assert_contains "$out" "$(printf 'in-scope\tsrc/my file.js')" "file name with space"
assert_contains "$out" "$(printf 'incidental\tpackage-lock.json')" "lockfile incidental"
assert_contains "$out" "$(printf 'incidental\ttests/__snapshots__/a.snap')" "snapshot incidental"
assert_contains "$out" "$(printf 'out-of-scope\tdocs/x.md')" "outside allow"

echo r2 >> src/billing/rates.js
git add -A && git -c user.name=t -c user.email=t@t commit -q -m billing
out=$(bash "$SC" "$base" "$tmp/scope.txt"); code=$?
assert_eq 1 "$code" "forbidden file exits 1"
assert_contains "$out" "$(printf 'forbidden\tsrc/billing/rates.js')" "forbid beats allow"

out=$(bash "$SC" "$base"); code=$?
assert_eq 0 "$code" "no scope file: nothing forbidden"
assert_contains "$out" "$(printf 'in-scope\tdocs/x.md')" "no allow lines: all in-scope"

bash "$SC" "$base" "$tmp/nope.txt" >/dev/null 2>&1; code=$?
assert_eq 2 "$code" "missing scope file exits 2"

finish
