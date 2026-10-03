#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
GA="$ROOT/skills/review-mine/scripts/graded-ab.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/ref" "$tmp/ours"; echo r > "$tmp/ref/home.png"; echo o > "$tmp/ours/home.png"

GRADED_AB_FORCE=B bash "$GA" prepare "$tmp/ref" "$tmp/ours" "$tmp/ab dir"; assert_eq 0 $? "prepare exits 0"
assert_eq o "$(cat "$tmp/ab dir/B/home.png")" "ours in B when forced"
assert_eq r "$(cat "$tmp/ab dir/A/home.png")" "reference in A"
assert_eq "ours=B" "$(cat "$tmp/ab dir.mapping")" "mapping recorded"
[ -e "$tmp/ab dir/mapping" ] || [ -e "$tmp/ab dir/.mapping" ] && _ko "mapping visible to the scorer" || _ok

printf 'A Layout fidelity: 4.5\nA Responsiveness: 4\nB Layout fidelity: 4.2\nB Responsiveness: 4\nGAP B Responsiveness: wraps\n' > "$tmp/s1.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s1.txt"); code=$?
assert_eq 0 "$code" "within margin passes"
assert_contains "$out" "GRADED: pass ours=4.10 reference=4.25 lowest=4.0 (scorer 1)" "pass line"

printf 'A Layout fidelity: 4.8\nA Responsiveness: 4.8\nB Layout fidelity: 4.2\nB Responsiveness: 4\n' > "$tmp/s2.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s1.txt" "$tmp/s2.txt"); code=$?
assert_eq 1 "$code" "confirming scorer fails the bar"
assert_contains "$out" "(scorer 2) — below reference by 0.70" "reason names the gap"

printf 'A Layout fidelity: 3\nA Responsiveness: 3\nB Layout fidelity: 3\nB Responsiveness: 3\n' > "$tmp/s3.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s3.txt"); assert_eq 1 $? "below floor fails"
assert_contains "$out" "below floor 3.50" "floor reason"
printf 'A x: 5\nA y: 5\nB x: 5\nB y: 2.5\n' > "$tmp/s4.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s4.txt" --floor 3); assert_eq 1 $? "one low criterion fails"
assert_contains "$out" "a criterion scored 2.5" "min reason"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s3.txt" --floor 3); assert_eq 0 $? "--floor overrides"

printf 'A x: 4\n' > "$tmp/bad.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad.txt" >/dev/null 2>&1; assert_eq 2 $? "missing side is bad input"
printf 'A x: 4\nA y: 4\nB x: 4\n' > "$tmp/bad2.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad2.txt" >/dev/null 2>&1; assert_eq 2 $? "unequal counts is bad input"
finish
