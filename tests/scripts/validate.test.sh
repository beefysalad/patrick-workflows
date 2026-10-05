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

fresh; echo 'Run `bash "$SKILL_DIR/scripts/nope.sh"`.' >> "$tmp/repo/skills/gauntlet-review/SKILL.md"
out=$(check); assert_contains "$out" "missing script scripts/nope.sh" "missing referenced script"

fresh; printf 'x\n\nCo-%s: Claude Test <t@example.com>\n' "Authored-By" > "$tmp/repo/notes.txt"
out=$(check); assert_contains "$out" "attribution string in ./notes.txt" "attribution trailer caught"

fresh; sed -i.bak 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Edit/' "$tmp/repo/agents/task-reviewer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "read-only agent has write tools: agents/task-reviewer.md" "task-reviewer is read-only"

fresh; echo 'Run `bash "$SKILL_DIR/../ticket-workspace/scripts/state.sh" x get y`.' >> "$tmp/repo/skills/gauntlet-review/SKILL.md"
out=$(check); assert_eq 0 $? "cross-skill reference to an existing script is valid"

fresh; echo 'Run `bash "$SKILL_DIR/../ticket-workspace/scripts/nope.sh"`.' >> "$tmp/repo/skills/gauntlet-review/SKILL.md"
out=$(check); assert_contains "$out" "missing script ../ticket-workspace/scripts/nope.sh" "missing cross-skill script"

fresh; sed -i.bak 's/^tools: Read, Glob$/tools: Read, Glob, Write/' "$tmp/repo/agents/ui-scorer.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "read-only agent has write tools: agents/ui-scorer.md" "ui-scorer is read-only"

fresh; sed -i.bak 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Edit/' "$tmp/repo/agents/finding-challenger.md"; rm -f "$tmp/repo/agents/"*.bak
out=$(check); assert_contains "$out" "read-only agent has write tools: agents/finding-challenger.md" "finding-challenger is read-only"

fresh; mkdir -p "$tmp/repo/skills/hello-dup"; printf -- '---\nname: hello-dup\ndescription: dup\n---\nx\n' > "$tmp/repo/skills/hello-dup/SKILL.md"; printf -- '---\ndescription: dup\n---\nx\n' > "$tmp/repo/commands/hello-dup.md"
out=$(check); assert_contains "$out" "command shadows skill: hello-dup" "a command may not share a skill name"
finish
