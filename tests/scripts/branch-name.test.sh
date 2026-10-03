#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
BN="$ROOT/skills/ticket-workspace/scripts/branch-name.sh"

assert_eq "feat/abc-123-add-csv-export" "$(bash "$BN" feat ABC-123 "Add CSV export")" "basic"
assert_eq "fix/abc-9-orders-page-crashes-on-empty-list" "$(bash "$BN" fix abc-9 "Orders page: crashes on empty list!!")" "punctuation collapsed"
assert_eq "feat/42-caf-menu-a-b" "$(bash "$BN" feat "#42" "Café menu / a\\b")" "unicode, slash and backslash removed"
assert_eq "chore/x-1" "$(bash "$BN" chore X-1)" "no title"
long=$(bash "$BN" feat ABC-1 "a very long title that keeps going and going well past the sixty character limit for names")
[ ${#long} -le 60 ] && _ok || _ko "length capped: ${#long}"
case "$long" in *-) _ko "trailing dash: $long" ;; *) _ok ;; esac
git check-ref-format --branch "$long" >/dev/null && _ok || _ko "valid ref: $long"
bash "$BN" wip ABC-1 "x" >/dev/null 2>&1; assert_eq 2 $? "unknown type rejected"
finish
