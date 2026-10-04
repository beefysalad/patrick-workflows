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
# Only images reach the scorer: a capture log names the URL and would unblind it.
mkdir -p "$tmp/ref2/sub" "$tmp/ours2"; echo r > "$tmp/ref2/home.png"; echo o > "$tmp/ours2/home.png"
echo "http://x/reference.html" > "$tmp/ref2/capture.log"; echo "http://x/" > "$tmp/ours2/capture.log"; echo n > "$tmp/ref2/sub/x.png"
GRADED_AB_FORCE=A bash "$GA" prepare "$tmp/ref2" "$tmp/ours2" "$tmp/ab2"; assert_eq 0 $? "prepare with logs exits 0"
assert_file "$tmp/ab2/A/home.png" "image copied"
[ -e "$tmp/ab2/A/capture.log" ] || [ -e "$tmp/ab2/B/capture.log" ] && _ko "capture.log copied into the blind folders" || _ok
[ -e "$tmp/ab2/B/sub" ] && _ko "subfolder copied into the blind folders" || _ok
mkdir -p "$tmp/empty"; GRADED_AB_FORCE=A bash "$GA" prepare "$tmp/empty" "$tmp/ours2" "$tmp/ab3" 2>/dev/null; assert_eq 2 $? "a side with no images is bad input"

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

# Test malformed score (no space after colon)
printf 'A x:5\nA y:5\nB x: 4\nB y: 4\n' > "$tmp/bad3.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad3.txt" >/dev/null 2>&1; assert_eq 2 $? "malformed score (no space) is bad input"

# Test non-numeric score
printf 'A x: 5\nA y: 5\nB x: n/a\nB y: 4\n' > "$tmp/bad4.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad4.txt" >/dev/null 2>&1; assert_eq 2 $? "non-numeric score is bad input"

# Test out-of-range score (>5)
printf 'A x: 5\nA y: 5\nB x: 45\nB y: 4\n' > "$tmp/bad5.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad5.txt" >/dev/null 2>&1; assert_eq 2 $? "score out of range (45) is bad input"

# Test invalid score format (1.2.3)
printf 'A x: 5\nA y: 5\nB x: 1.2.3\nB y: 4\n' > "$tmp/bad6.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/bad6.txt" >/dev/null 2>&1; assert_eq 2 $? "invalid score format (1.2.3) is bad input"

# Test trailing slash on out-dir
GRADED_AB_FORCE=A bash "$GA" prepare "$tmp/ref" "$tmp/ours" "$tmp/slash/"; assert_eq 0 $? "prepare with trailing slash exits 0"
assert_eq "ours=A" "$(cat "$tmp/slash.mapping")" "mapping at sibling of slash dir"
[ -e "$tmp/slash/.mapping" ] || [ -e "$tmp/slash/mapping" ] && _ko "mapping inside slash dir" || _ok

finish
