#!/usr/bin/env bash
# Runs every tests/scripts/*.test.sh with macOS's /bin/bash (3.2) to catch bash-5-only code.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
for t in "$ROOT"/tests/scripts/*.test.sh; do
  [ -e "$t" ] || continue
  echo "== $(basename "$t")"
  /bin/bash "$t" || status=1
done
exit "$status"
