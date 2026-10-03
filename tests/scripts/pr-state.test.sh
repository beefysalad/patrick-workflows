#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
PS="$ROOT/skills/ticket-workspace/scripts/pr-state.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "$STUB_STATE" = ERROR ] && exit 1
echo "$STUB_STATE"
SH
chmod +x "$tmp/bin/gh"
for pair in MERGED:merged OPEN:open CLOSED:closed-unmerged; do
  out=$(STUB_STATE=${pair%%:*} PATH="$tmp/bin:$PATH" bash "$PS" https://github.com/me/x/pull/7); assert_eq "${pair#*:}" "$out" "$pair"
done
out=$(STUB_STATE=ERROR PATH="$tmp/bin:$PATH" bash "$PS" 7); assert_eq 3 $? "gh failure is could-not-run"
assert_eq could-not-run "$out" "could-not-run printed"
out=$(PATH="/usr/bin:/bin" bash "$PS" 7); assert_eq 3 $? "no gh is could-not-run"
finish
