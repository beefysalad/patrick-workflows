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
# Forms the first version missed (assembled at runtime so the repo holds no secret-shaped text).
v="supersecret""value123"
{
  echo "DB_PASSWORD=$v"
  echo "password: $v"
  echo "AWS_SECRET_ACCESS_KEY=$v"
  echo "SECRET_KEY = '$v'"
  echo "OPENAI_KEY=sk-""proj-abcdefghijklmnopqrstuvwxyz012345"
  echo "x sk-""ant-api03-abcdefghijklmnopqrstuvwxyz0123"
  echo "maps AIza""SyA1234567890abcdefghijklmnopqrstuv"
  echo "tok github_pat""_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz"
} > "$tmp/more.env"
out=$(bash "$SS" "$tmp/more.env")
for n in 1 2 3 4 5 6 7 8; do assert_contains "$out" "more.env:$n:" "line $n flagged"; done
assert_not_contains "$out" "$v" "value never printed"
{
  echo 'password=$DB_PASSWORD'
  echo 'password: ${{ secrets.DB_PASSWORD }}'
  echo 'token: <your token here>'
  echo 'const passwordLabel = "Password"'
} > "$tmp/refs.yml"
out=$(bash "$SS" "$tmp/refs.yml"); assert_eq 0 $? "references and placeholders are not secrets"
finish
