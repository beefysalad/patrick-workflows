#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
WV="$ROOT/skills/ticket-workspace/scripts/waves.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# task <n> <depends> <file>...: one plan task in the planner's format ("-" as depends omits the line).
task() {
  n=$1; d=$2; shift 2
  printf '### Task %s: thing %s\n\n**Files:**\n' "$n" "$n"
  for f; do printf -- '- Modify: `%s`\n' "$f"; done
  printf '\n'; [ "$d" = - ] || printf '**Depends on:** %s\n\n' "$d"
  printf -- '- [ ] **Step 1: Write the failing test**\n\n'
}

{ task 1 none src/a.js; task 2 none src/b.js tests/b.test.js; task 3 none src/c.js; task 4 "1, 2" src/d.js; } > "$tmp/p1.md"
assert_eq "Wave 1: 1 2 3
Wave 2: 4" "$(bash "$WV" "$tmp/p1.md")" "independent tasks share a wave; dependents wait"

{ task 1 none src/a.js; task 2 none src/a.js:10-20; task 3 none src/c.js; } > "$tmp/p2.md"
assert_eq "Wave 1: 1 3
Wave 2: 2" "$(bash "$WV" "$tmp/p2.md")" "shared file (line suffix ignored) splits waves"

{ task 1 none src/a.js; task 2 - src/b.js; task 3 none src/c.js; } > "$tmp/p3.md"
assert_eq "Wave 1: 1 3
Wave 2: 2" "$(bash "$WV" "$tmp/p3.md")" "missing Depends on line depends on the previous task"

{ task 1 none src/a.js; printf '### Task 2: no files\n\n**Depends on:** none\n\n'; task 3 none src/c.js; } > "$tmp/p4.md"
assert_eq "Wave 1: 1 3
Wave 2: 2" "$(bash "$WV" "$tmp/p4.md")" "a task without Files runs alone"

{ task 1 none src/a.js; task 2 1 src/b.js; task 3 2 src/c.js; } > "$tmp/p5.md"
assert_eq "Wave 1: 1
Wave 2: 2
Wave 3: 3" "$(bash "$WV" "$tmp/p5.md")" "a chain stays sequential"

{ printf '## Round 2\n\n'; task 5 none src/e.js; task 6 none src/f.js; } > "$tmp/p6.md"
assert_eq "Wave 1: 5 6" "$(bash "$WV" "$tmp/p6.md")" "numbers need not start at 1"

{ task 1 3 src/a.js; task 2 none src/b.js; task 3 none src/c.js; } > "$tmp/bad1.md"
bash "$WV" "$tmp/bad1.md" >/dev/null 2>&1; assert_eq 2 $? "depending on a later task is bad input"
{ task 1 none src/a.js; task 2 9 src/b.js; } > "$tmp/bad2.md"
bash "$WV" "$tmp/bad2.md" >/dev/null 2>&1; assert_eq 2 $? "unknown dependency is bad input"
printf '# no tasks\n' > "$tmp/bad3.md"
bash "$WV" "$tmp/bad3.md" >/dev/null 2>&1; assert_eq 2 $? "no tasks is bad input"
bash "$WV" "$tmp/missing.md" >/dev/null 2>&1; assert_eq 2 $? "missing file is bad input"
finish
