#!/usr/bin/env bash
# Create a standalone review workspace and print its path.
# Location: ${TICKETS_HOME:-~/.patrick-workflows/tickets}/<repo-slug>/_reviews/<branch>-<UTC timestamp>
# (not under ~/.claude: Claude Code treats that tree as sensitive and refuses writes there)
# Also records the path in .git/patrick-workflows-review-ws so the other scripts find it
# without a REVIEW_WS=... prefix, which permission allow rules would not match.
set -u
if [ "${1:-}" = "--at" ]; then   # use a given directory (embedded mode)
  dir=${2:?usage: workspace.sh --at <dir>}
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 1; }
  mkdir -p "$dir/logs" || exit 1
  printf '%s\n' "$dir" > "$(git rev-parse --git-path patrick-workflows-review-ws)"
  printf '%s\n' "$dir"
  exit 0
fi
root=${TICKETS_HOME:-$HOME/.patrick-workflows/tickets}
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repository" >&2; exit 1; }
url=$(git config --get remote.origin.url 2>/dev/null || true)
if [ -n "$url" ]; then slug=$(basename "$url" .git); else slug=$(basename "$top"); fi
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "HEAD" ] && branch="detached-$(git rev-parse --short HEAD)"
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
dir="$root/$(safe "$slug")/_reviews/$(safe "$branch")-$(date -u +%Y%m%dT%H%M%SZ)"
n=1; candidate=$dir
while [ -e "$candidate" ]; do n=$((n + 1)); candidate="$dir-$n"; done
mkdir -p "$candidate/logs" || exit 1
printf '%s\n' "$candidate" > "$(git rev-parse --git-path patrick-workflows-review-ws)"
printf '%s\n' "$candidate"
