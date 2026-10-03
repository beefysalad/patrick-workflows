#!/usr/bin/env bash
# Derive a branch name "<type>/<ticket-id>-<slug>" from a ticket.
# Usage: branch-name.sh <type> <ticket-id> [title words...]
set -u
type=${1:-}; id=${2:-}
[ -n "$type" ] && [ -n "$id" ] || { echo "usage: branch-name.sh <type> <ticket-id> [title...]" >&2; exit 2; }
shift 2
case $type in feat|fix|chore|docs|refactor|test|perf) ;; *) echo "unknown type: $type" >&2; exit 2 ;; esac
slug() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
idslug=$(slug "$id")
[ -n "$idslug" ] || { echo "ticket ID has no usable characters: $id (use a Latin ID such as T-1)" >&2; exit 2; }
name="$type/$idslug"
t=$(slug "$*")
[ -n "$t" ] && name="$name-$t"
name=$(printf '%s' "$name" | cut -c1-60 | sed -E 's/-+$//')
git check-ref-format --branch "$name" >/dev/null 2>&1 || { echo "cannot form a valid branch name from: $id $*" >&2; exit 2; }
printf '%s\n' "$name"
