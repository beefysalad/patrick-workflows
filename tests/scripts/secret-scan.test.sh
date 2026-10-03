#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SS="$ROOT/skills/ticket-workspace/scripts/secret-scan.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
aws="AKIA""QWERTYUIOPASDFGH"
gh="ghp""_""abcdefghijklmnopqrstuvwxyz0123456789AB"
pw="hunter2""hunter2"
{
  echo "clean line"
  echo "key = $aws"
  echo "-----BEGIN RSA ""PRIVATE KEY-----"
  echo "token: $gh"
  echo "password = \"$pw\""
  echo "db: postgres://admin:$pw@db.internal/app"
} > "$tmp/pr body.md"
out=$(bash "$SS" "$tmp/pr body.md"); code=$?
assert_eq 1 "$code" "hits exit 1"
assert_contains "$out" "pr body.md:2: aws-access-key" "aws key with line number"
assert_contains "$out" ":3: private-key" "private key"
assert_contains "$out" ":4: github-token" "github token"
assert_contains "$out" ":5: password-assignment" "password assignment"
assert_contains "$out" ":6: url-credentials" "credentials in url"
assert_not_contains "$out" "$pw" "secret value never printed"
assert_not_contains "$out" "$aws" "key never printed"

echo "nothing to see" > "$tmp/clean.md"
out=$(bash "$SS" "$tmp/clean.md"); assert_eq 0 $? "clean exits 0"; assert_eq "" "$out" "clean prints nothing"

printf '# company strings\nAcme Internal\n' > "$tmp/deny.txt"
echo "Deploy to the acme internal cluster" > "$tmp/c.md"
out=$(bash "$SS" --deny-file "$tmp/deny.txt" "$tmp/c.md"); assert_eq 1 $? "deny list hit"
assert_contains "$out" "c.md:1: deny-list" "deny list is case-insensitive"

out=$(printf 'x\nkey %s\n' "$aws" | bash "$SS" -); assert_contains "$out" "stdin:2: aws-access-key" "stdin"
bash "$SS" "$tmp/none.md" >/dev/null 2>&1; assert_eq 2 $? "missing file exits 2"
finish
