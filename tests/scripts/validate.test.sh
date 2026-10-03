#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fresh() { rm -rf "$tmp/repo"; mkdir -p "$tmp/repo"; (cd "$ROOT" && tar --exclude=.git --exclude=.superpowers -cf - .) | (cd "$tmp/repo" && tar -xf -); }
check() { bash "$tmp/repo/scripts/validate.sh" 2>&1; }

fresh; out=$(check); assert_eq 0 $? "clean copy validates"

fresh; sed -i.bak '/^model:/d' "$tmp/repo/agents/ticket-fixer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "no model in frontmatter: agents/ticket-fixer.md" "agent without model"

fresh; sed -i.bak 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Bash/' "$tmp/repo/agents/final-reviewer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "read-only agent has write tools" "critic with Bash"

fresh; echo 'Run `bash "$SKILL_DIR/scripts/nope.sh"`.' >> "$tmp/repo/skills/review-mine/SKILL.md"
out=$(check); assert_contains "$out" "missing script scripts/nope.sh" "missing referenced script"

fresh; printf 'x\n\nCo-%s: Claude Test <t@example.com>\n' "Authored-By" > "$tmp/repo/notes.txt"
out=$(check); assert_contains "$out" "attribution string in ./notes.txt" "attribution trailer caught"

finish
