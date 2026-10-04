#!/usr/bin/env bash
# State of a pull request, for CLOSE.
# Usage: pr-state.sh <pr-url-or-number>
#   Prints merged | open | closed-unmerged (exit 0) or could-not-run (exit 3).
# Usage: pr-state.sh --head-matches <pr-url-or-number> <branch>
#   Compares the local branch tip (in the current repo) with the PR's head commit on GitHub.
#   Prints same (exit 0), differs (exit 1) or could-not-run (exit 3).
set -u
if [ "${1:-}" = --head-matches ]; then
  pr=${2:-}; br=${3:-}
  [ -n "$pr" ] && [ -n "$br" ] || { echo could-not-run; exit 3; }
  command -v gh >/dev/null 2>&1 || { echo could-not-run; exit 3; }
  head=$(gh pr view "$pr" --json headRefOid --jq .headRefOid 2>/dev/null) || { echo could-not-run; exit 3; }
  case $head in [0-9a-f]*) ;; *) echo could-not-run; exit 3 ;; esac
  tip=$(git rev-parse --verify -q "refs/heads/$br" 2>/dev/null) || { echo could-not-run; exit 3; }
  if [ "$tip" = "$head" ]; then echo same; exit 0; fi
  echo differs; exit 1
fi
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
