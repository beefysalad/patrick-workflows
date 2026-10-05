#!/usr/bin/env bash
# Build a review package for critics.
# Usage: review-package.sh <base> <head> <out-dir>
# Writes diff.patch, files.txt, symbols.txt, callers.txt, README.txt.
set -u
base=${1:-}; head=${2:-}; out=${3:-}
[ -n "$base" ] && [ -n "$head" ] && [ -n "$out" ] || { echo "usage: review-package.sh <base> <head> <out-dir>" >&2; exit 1; }
for r in "$base" "$head"; do
  git rev-parse --verify -q "$r^{commit}" >/dev/null || { echo "unknown revision: $r" >&2; exit 1; }
done
mkdir -p "$out" || exit 1
git diff "$base" "$head" > "$out/diff.patch"
git -c core.quotePath=false diff --name-only "$base" "$head" > "$out/files.txt"

KW='(function|class|def|interface|type|enum|struct|trait|fn|func)'
{
  # Names declared on changed lines, and the enclosing function from hunk headers.
  git diff -U0 "$base" "$head" | grep -E '^(@@|[+-])' | grep -vE '^(\+\+\+|---) ' |
    sed -nE "s/.*(^|[^A-Za-z0-9_])$KW[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p"
  git diff -U0 "$base" "$head" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' |
    sed -nE 's/.*(^|[^A-Za-z0-9_])(const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\3/p'
} | awk 'length($0) >= 3' | sort -u > "$out/symbols.txt"

: > "$out/callers.txt"
while IFS= read -r sym; do
  hits=$(git grep -n -w -F -e "$sym" "$head" -- . 2>/dev/null | head -n 21)
  [ -n "$hits" ] || continue
  n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
  {
    echo "## $sym"
    printf '%s\n' "$hits" | head -n 20
    [ "$n" -gt 20 ] && echo "... (truncated at 20 hits)"
    echo
  } >> "$out/callers.txt"
done < "$out/symbols.txt"

cat > "$out/README.txt" <<'TXT'
This package is a starting point, not the boundary of the review.
- diff.patch / files.txt: what changed.
- symbols.txt: names declared or modified in the change (heuristic).
- callers.txt: plain-text references to those names, found with git grep.
Text search misses: dependency injection, dynamic dispatch, string-keyed routes
and event names, framework conventions (route files, ORM schemas, config-driven
wiring), reflection, and generated code. Use Grep and Glob to look beyond this
package wherever the change could have effects it does not show.
TXT
