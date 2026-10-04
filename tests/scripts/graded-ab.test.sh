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

# first-route: the first route's images, renamed to the "home" slug the one-page reference uses.
mkdir -p "$tmp/cap"; for v in desktop-light desktop-dark phone-light phone-dark; do echo "p$v" > "$tmp/cap/pricing-plans-$v.png"; echo "h$v" > "$tmp/cap/home-$v.png"; done
echo "http://x" > "$tmp/cap/capture.log"; echo x > "$tmp/cap/pricing-plans-extra-desktop-light.png"
printf '# routes\n\n /pricing/plans/ \n/\n' > "$tmp/fr-routes.txt"
mkdir -p "$tmp/fr"; echo stale > "$tmp/fr/old.png"
bash "$GA" first-route "$tmp/cap" "$tmp/fr-routes.txt" "$tmp/fr"; assert_eq 0 $? "first-route exits 0"
assert_eq "pdesktop-light" "$(cat "$tmp/fr/home-desktop-light.png" 2>/dev/null)" "first route copied as home"
assert_eq "pphone-dark" "$(cat "$tmp/fr/home-phone-dark.png" 2>/dev/null)" "all four variants"
assert_eq "home-desktop-dark.png home-desktop-light.png home-phone-dark.png home-phone-light.png" "$(ls "$tmp/fr" | tr '\n' ' ' | sed 's/ $//')" "only the four first-route images, nothing stale"
printf '/\n' > "$tmp/fr-root.txt"; bash "$GA" first-route "$tmp/cap" "$tmp/fr-root.txt" "$tmp/fr2"
assert_eq "hdesktop-light" "$(cat "$tmp/fr2/home-desktop-light.png" 2>/dev/null)" "route / stays home"
printf '/none\n' > "$tmp/fr-none.txt"; bash "$GA" first-route "$tmp/cap" "$tmp/fr-none.txt" "$tmp/fr3" 2>/dev/null; assert_eq 2 $? "no images for the first route is bad input"
# images: an image-dir: reference copied into the reference folder (images only, old content removed).
mkdir -p "$tmp/idir" "$tmp/iref"; echo i > "$tmp/idir/home-desktop-light.png"; echo t > "$tmp/idir/notes.txt"; echo stale > "$tmp/iref/old.png"
bash "$GA" images "$tmp/idir" "$tmp/iref"; assert_eq 0 $? "images exits 0"
assert_eq "home-desktop-light.png" "$(ls "$tmp/iref")" "only images copied, stale removed"
bash "$GA" images "$tmp/empty" "$tmp/iref2" 2>/dev/null; assert_eq 2 $? "image dir with no images is bad input"
# A tie on every criterion (a likely copy of the reference) is flagged; the verdict is unchanged.
printf 'A Layout fidelity: 4.5\nA Responsiveness: 4\nB Layout fidelity: 4.5\nB Responsiveness: 4.0\n' > "$tmp/tie.txt"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/tie.txt"); code=$?
assert_eq 0 "$code" "a tie still passes"
assert_contains "$out" "GRADED: tie on every criterion (scorer 1)" "tie flagged"
out=$(bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s1.txt")
assert_not_contains "$out" "tie" "no tie flag when scores differ"

# Cleanup round.
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/s1.txt" --margin 2>/dev/null; assert_eq 2 $? "flag without a value is bad input"
printf 'A Layout fidelity: 4.5\r\nA Responsiveness: 4  \r\nB Layout fidelity: 4.2\r\nB Responsiveness: 4\r\n' > "$tmp/crlf.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/crlf.txt" >/dev/null 2>&1; assert_eq 0 $? "CRLF and trailing spaces accepted"
printf 'A x: 5\nA x: 5\nB x: 5\nB y: 5\n' > "$tmp/dup.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/dup.txt" >/dev/null 2>&1; assert_eq 2 $? "duplicate criterion is bad input"
printf 'A x: 5\nA y: 5\nB x: 5\nB z: 5\n' > "$tmp/mism.txt"
bash "$GA" verdict "$tmp/ab dir.mapping" "$tmp/mism.txt" >/dev/null 2>&1; assert_eq 2 $? "criteria differ between sides is bad input"
GRADED_AB_FORCE=A bash "$GA" prepare "$tmp/ref" "$tmp/ours" "$tmp/blind/r1x" "$tmp/maps/r1.mapping"; assert_eq 0 $? "prepare with a separate mapping path"
assert_eq "ours=A" "$(cat "$tmp/maps/r1.mapping")" "mapping written where asked"
[ -e "$tmp/blind/r1x.mapping" ] && _ko "default mapping also written" || _ok
mkdir -p "$tmp/precious"; echo keep > "$tmp/precious/notes.md"
bash "$GA" prepare "$tmp/ref" "$tmp/ours" "$tmp/precious" 2>/dev/null; assert_eq 2 $? "refuses to empty a folder with other files"
assert_file "$tmp/precious/notes.md" "other files kept"
finish
