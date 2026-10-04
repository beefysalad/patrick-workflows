#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
PS="$ROOT/skills/ticket-workspace/scripts/pr-state.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "$STUB_STATE" = ERROR ] && exit 1
case "$*" in *headRefOid*) echo "$STUB_HEAD"; exit 0 ;; esac
echo "$STUB_STATE"
SH
chmod +x "$tmp/bin/gh"
for pair in MERGED:merged OPEN:open CLOSED:closed-unmerged; do
  out=$(STUB_STATE=${pair%%:*} PATH="$tmp/bin:$PATH" bash "$PS" https://github.com/me/x/pull/7); assert_eq "${pair#*:}" "$out" "$pair"
done
out=$(STUB_STATE=ERROR PATH="$tmp/bin:$PATH" bash "$PS" 7); assert_eq 3 $? "gh failure is could-not-run"
assert_eq could-not-run "$out" "could-not-run printed"
out=$(PATH="/usr/bin:/bin" bash "$PS" 7); assert_eq 3 $? "no gh is could-not-run"
# --head-matches: is the local branch tip exactly the PR head GitHub merged?
repo="$tmp/repo"; git init -q "$repo"; git -C "$repo" -c user.name=t -c user.email=t@e commit -q --allow-empty -m one
git -C "$repo" branch feat/x; tip=$(git -C "$repo" rev-parse feat/x)
out=$(cd "$repo" && STUB_STATE=MERGED STUB_HEAD=$tip PATH="$tmp/bin:$PATH" bash "$PS" --head-matches https://github.com/me/x/pull/7 feat/x); code=$?
assert_eq 0 "$code" "same tip exits 0"; assert_eq same "$out" "same tip"
out=$(cd "$repo" && STUB_STATE=MERGED STUB_HEAD=0123456789abcdef0123456789abcdef01234567 PATH="$tmp/bin:$PATH" bash "$PS" --head-matches 7 feat/x); code=$?
assert_eq 1 "$code" "other tip exits 1"; assert_eq differs "$out" "other tip"
out=$(cd "$repo" && STUB_STATE=MERGED STUB_HEAD=$tip PATH="$tmp/bin:$PATH" bash "$PS" --head-matches 7 no/such); code=$?
assert_eq 3 "$code" "missing branch exits 3"; assert_eq could-not-run "$out" "missing branch"
out=$(cd "$repo" && STUB_STATE=ERROR PATH="$tmp/bin:$PATH" bash "$PS" --head-matches 7 feat/x); code=$?
assert_eq 3 "$code" "gh failure exits 3"; assert_eq could-not-run "$out" "gh failure"
out=$(cd "$repo" && STUB_STATE=MERGED STUB_HEAD= PATH="$tmp/bin:$PATH" bash "$PS" --head-matches 7 feat/x); code=$?
assert_eq 3 "$code" "empty head exits 3"
finish
