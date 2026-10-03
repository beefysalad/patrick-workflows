#!/usr/bin/env bash
# State of a pull request, for CLOSE.
# Usage: pr-state.sh <pr-url-or-number>
# Prints merged | open | closed-unmerged (exit 0) or could-not-run (exit 3).
set -u
pr=${1:-}
[ -n "$pr" ] || { echo could-not-run; exit 3; }
command -v gh >/dev/null 2>&1 || { echo could-not-run; exit 3; }
s=$(gh pr view "$pr" --json state --jq .state 2>/dev/null) || { echo could-not-run; exit 3; }
case $s in
  MERGED) echo merged ;;
  OPEN) echo open ;;
  CLOSED) echo closed-unmerged ;;
  *) echo could-not-run; exit 3 ;;
esac
