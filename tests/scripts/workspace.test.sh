#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
WS="$ROOT/skills/review-mine/scripts/workspace.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets home"

repo="$tmp/My Repo"; mkdir -p "$repo"; cd "$repo" || exit 1
git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git checkout -q -b feat/abc-1

out=$(bash "$WS"); code=$?
assert_eq 0 "$code" "exits 0 in a repo"
case "$out" in "$TICKETS_HOME/My-Repo/_reviews/feat-abc-1-"*) _ok ;; *) _ko "path shape: $out" ;; esac
[ -d "$out/logs" ] && _ok || _ko "logs dir created"
ptr=$(git rev-parse --git-path patrick-workflows-review-ws)
assert_eq "$out" "$(cat "$ptr")" "pointer file records the workspace"
out=$(TICKETS_HOME= HOME="$tmp/home" bash "$WS")
case "$out" in "$tmp/home/.patrick-workflows/tickets/"*) _ok ;; *) _ko "default root outside ~/.claude: $out" ;; esac

git remote add origin "git@github.com:me/shop-app.git"
out=$(bash "$WS")
case "$out" in "$TICKETS_HOME/shop-app/_reviews/"*) _ok ;; *) _ko "slug from remote: $out" ;; esac

git checkout -q --detach
out=$(bash "$WS")
case "$out" in *"/_reviews/detached-"*) _ok ;; *) _ko "detached head: $out" ;; esac

a=$(bash "$WS"); b=$(bash "$WS")
[ "$a" != "$b" ] && _ok || _ko "two calls in the same second get distinct dirs"

cd "$tmp" || exit 1
bash "$WS" >/dev/null 2>&1; code=$?
assert_eq 1 "$code" "outside a repo exits 1"

finish
