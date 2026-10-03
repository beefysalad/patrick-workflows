#!/usr/bin/env bash
# Ticket workspace paths: ${TICKETS_HOME:-~/.patrick-workflows/tickets}/<repo-slug>/<ticket-id>
# Usage: ticket-ws.sh path <id> | init <id> | list
# Exit: 0 ok, 1 not a git repo, 2 bad input, 3 init on an existing workspace.
set -u
root=${TICKETS_HOME:-$HOME/.patrick-workflows/tickets}
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "not a git repository" >&2; exit 1; }
url=$(git config --get remote.origin.url 2>/dev/null || true)
if [ -n "$url" ]; then slug=$(basename "$url" .git)
else
  # The git common dir is shared by every worktree, so the main checkout's name is the same everywhere.
  case $common in */.git) slug=$(basename "$(dirname "$common")") ;; *) slug=$(basename "$common" .git) ;; esac
fi
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
base="$root/$(safe "$slug")"
cmd=${1:-}; id=${2:-}
case $cmd in
  path|init)
    [ -n "$id" ] || { echo "usage: ticket-ws.sh $cmd <id>" >&2; exit 2; }
    dir="$base/$(safe "$id")"
    if [ "$cmd" = init ]; then
      [ ! -e "$dir" ] || { echo "workspace exists: $dir" >&2; exit 3; }
      mkdir -p "$dir/logs" "$dir/briefs" "$dir/reports" || exit 2
    fi
    printf '%s\n' "$dir" ;;
  list)
    [ -d "$base" ] || exit 0
    for d in "$base"/*/; do
      [ -d "$d" ] || continue
      t=$(basename "$d"); [ "$t" = _reviews ] && continue
      ph=$(sed -n 's/^phase: //p' "$d/state.md" 2>/dev/null | head -n 1)
      printf '%s\t%s\n' "$t" "${ph:-none}"
    done ;;
  *) echo "usage: ticket-ws.sh path <id> | init <id> | list" >&2; exit 2 ;;
esac
