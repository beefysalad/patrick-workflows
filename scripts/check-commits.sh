#!/usr/bin/env bash
# Fail if any commit message in a range carries tool attribution.
# Usage: check-commits.sh [<rev-range>]   (default: origin/main..HEAD, else HEAD)
# Patterns are split so this file does not match itself.
attr1='Co-''Authored-By:.*Claude'
attr2='Generated with \[Claude'' Code\]'

range="${1:-}"
if [ -z "$range" ]; then
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then
    range="origin/main..HEAD"
  else
    range="HEAD"
  fi
fi

found=0
for sha in $(git rev-list "$range"); do
  msg=$(git log -1 --format=%B "$sha")
  if printf '%s\n' "$msg" | grep -qiE -e "$attr1" -e "$attr2"; then
    echo "attribution trailer in $(git log -1 --format='%h %s' "$sha")"
    found=1
  fi
done

if [ "$found" -ne 0 ]; then exit 1; fi
echo "OK: no attribution in commit messages"
