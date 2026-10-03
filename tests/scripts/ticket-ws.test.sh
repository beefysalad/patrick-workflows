#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
TW="$ROOT/skills/ticket-workspace/scripts/ticket-ws.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets home"
repo="$tmp/Shop App"; mkdir -p "$repo"; cd "$repo" || exit 1
git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

p=$(bash "$TW" path ABC-123); assert_eq "$TICKETS_HOME/Shop-App/ABC-123" "$p" "path from folder name"
[ -e "$p" ] && _ko "path must not create" || _ok
p2=$(bash "$TW" init ABC-123); assert_eq "$p" "$p2" "init prints the same path"
[ -d "$p/logs" ] && [ -d "$p/briefs" ] && [ -d "$p/reports" ] && _ok || _ko "init creates subdirs"
bash "$TW" init ABC-123 >/dev/null 2>&1; assert_eq 3 $? "second init exits 3"

git worktree add -q "$tmp/wt dir" -b feat/x
p3=$(cd "$tmp/wt dir" && bash "$TW" path ABC-123); assert_eq "$p" "$p3" "same path from a worktree"

bash "$ROOT/skills/ticket-workspace/scripts/state.sh" "$p/state.md" phase intake
mkdir -p "$TICKETS_HOME/Shop-App/_reviews"
out=$(bash "$TW" list); assert_eq "$(printf 'ABC-123\tintake')" "$out" "list shows id and phase, skips _reviews"

git remote add origin "git@github.com:me/shop.git"
assert_eq "$TICKETS_HOME/shop/X-1" "$(bash "$TW" path X-1)" "slug from remote"
assert_eq "$TICKETS_HOME/shop/a-b-c" "$(bash "$TW" path 'a/b c')" "unsafe id characters replaced"
cd "$tmp" && bash "$TW" path X >/dev/null 2>&1; assert_eq 1 $? "outside a repo exits 1"
finish
