#!/usr/bin/env bash
# Classify files changed between <base> and HEAD against a scope file.
# Usage: scope-check.sh <base> [scope-file]
# Scope lines: "allow: <glob>" or "forbid: <glob>"; "**" works like "*"; "#" starts a comment.
# Prints "<class>\t<file>"; classes: in-scope, incidental, out-of-scope, forbidden.
# Exit: 0 ok, 1 a forbidden file changed, 2 bad input.
set -u
set -f   # patterns are matched against names, never expanded against the filesystem
base=${1:-}
[ -n "$base" ] || { echo "usage: scope-check.sh <base> [scope-file]" >&2; exit 2; }
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "unknown base: $base" >&2; exit 2; }
scope=${2:-}
allow=""; forbid=""
trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }
if [ -n "$scope" ]; then
  [ -f "$scope" ] || { echo "scope file not found: $scope" >&2; exit 2; }
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    case $line in
      allow:*) allow="$allow
$(trim "${line#allow:}")" ;;
      forbid:*) forbid="$forbid
$(trim "${line#forbid:}")" ;;
    esac
  done < "$scope"
fi

INCIDENTAL_NAMES='package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb Cargo.lock poetry.lock uv.lock Pipfile.lock Gemfile.lock composer.lock go.sum package.json pyproject.toml go.mod Cargo.toml index.ts index.tsx index.js index.mjs *.snap'
INCIDENTAL_PATHS='*__snapshots__/* */generated/* *.generated.* *.gen.*'

matches() {   # $1 file, $2 newline-separated patterns
  local f=$1 p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p=${p//\*\*/*}
    [[ $f == $p ]] && return 0
  done <<EOF2
$2
EOF2
  return 1
}
incidental() {
  local f=$1 b p
  b=$(basename "$f")
  for p in $INCIDENTAL_NAMES; do [[ $b == $p ]] && return 0; done
  for p in $INCIDENTAL_PATHS; do [[ $f == $p ]] && return 0; done
  return 1
}

status=0
while IFS= read -r -d '' f; do
  if matches "$f" "$forbid"; then class=forbidden; status=1
  elif [ -z "$(trim "$allow")" ] || matches "$f" "$allow"; then class=in-scope
  elif incidental "$f"; then class=incidental
  else class=out-of-scope
  fi
  printf '%s\t%s\n' "$class" "$f"
done < <(git diff --name-only -z "$base" HEAD)
exit "$status"
