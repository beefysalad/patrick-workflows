#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
RP="$ROOT/skills/review-mine/scripts/review-package.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main
mkdir -p src
cat > src/cart.js <<'JS'
function total(items) {
  return items.length;
}
module.exports = { total };
JS
cat > src/checkout.js <<'JS'
const { total } = require('./cart');
function checkout(items) { return total(items); }
JS
git add -A && git -c user.name=t -c user.email=t@t commit -q -m base
base=$(git rev-parse HEAD)
cat > src/cart.js <<'JS'
function total(items) {
  return items.reduce((s, i) => s + i.price, 0);
}
class Cart {}
const discountRate = 0.1;
module.exports = { total, Cart, discountRate };
JS
git add -A && git -c user.name=t -c user.email=t@t commit -q -m change

out="$tmp/pkg dir"
bash "$RP" "$base" HEAD "$out"; code=$?
assert_eq 0 "$code" "exits 0"
assert_contains "$(cat "$out/files.txt")" "src/cart.js" "files listed"
syms=$(cat "$out/symbols.txt")
assert_contains "$syms" "total" "modified function from hunk header"
assert_contains "$syms" "Cart" "added class"
assert_contains "$syms" "discountRate" "added const"
assert_contains "$(cat "$out/callers.txt")" "src/checkout.js" "caller in another file found"
assert_contains "$(cat "$out/README.txt")" "starting point" "README warns it is not the boundary"
assert_file "$out/diff.patch" "diff written"

bash "$RP" "$base" "$base" "$tmp/empty"; code=$?
assert_eq 0 "$code" "empty diff ok"
assert_eq "" "$(cat "$tmp/empty/files.txt")" "empty diff lists no files"

bash "$RP" not-a-rev HEAD "$tmp/x" 2>/dev/null; code=$?
assert_eq 1 "$code" "unknown revision exits 1"

finish
