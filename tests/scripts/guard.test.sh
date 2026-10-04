#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
GUARD="$ROOT/hooks/guard.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TICKETS_HOME="$tmp/tickets"
# hook <cwd> <command>: run the guard on hook JSON shaped like the real one (spike); sets code and err.
hook() {
  err=$(perl -MJSON::PP -e 'print encode_json({session_id=>"s",cwd=>$ARGV[0],hook_event_name=>"PreToolUse",tool_name=>"Bash",tool_input=>{command=>$ARGV[1],description=>"d"}})' "$1" "$2" | bash "$GUARD" 2>&1 >/dev/null); code=$?
}
mkdir -p "$tmp/plain"
CO="Co-""Authored-By"   # split so validate.sh's attribution scan does not match this file
GW="Generated ""with"
T="$CO: Claude Opus <noreply@anthropic.com>"

hook "$tmp/plain" 'git commit -m "feat: add x"'; assert_eq 0 "$code" "clean commit allowed"; assert_eq "" "$err" "allow prints nothing"
hook "$tmp/plain" "git commit -m \"feat: x

$T\""; assert_eq 2 "$code" "trailer in -m blocked"
assert_contains "$err" "patrick-workflows guard: " "block reason prefix"
hook "$tmp/plain" "cd a && git commit -F - <<'EOF'
feat: x

$T
EOF"; assert_eq 2 "$code" "trailer in heredoc blocked"
printf 'feat: x\n\n%s\n' "$T" > "$tmp/plain/msg.txt"
hook "$tmp/plain" 'git commit -F msg.txt'; assert_eq 2 "$code" "trailer in -F file blocked"
hook "$tmp/plain" 'git commit --file=msg.txt'; assert_eq 2 "$code" "trailer in --file= blocked"
hook "$tmp/plain" "gh pr create --draft --title t --body \"Adds x. $GW [Claude Code](https://claude.com/claude-code)\""; assert_eq 2 "$code" "footer in PR body blocked"
printf 'Body\n\n%s Claude Code\n' "$GW" > "$tmp/plain/body.md"
hook "$tmp/plain" 'gh pr edit 3 --body-file body.md'; assert_eq 2 "$code" "footer in --body-file blocked"
hook "$tmp/plain" "git -C /x commit -m \"x

co-authored-by: claude <n@a.com>\""; assert_eq 2 "$code" "case-insensitive, git -C form"
hook "$tmp/plain" 'git commit -m "say \"hi\" to C:\\temp"'; assert_eq 0 "$code" "escaped quotes and backslashes parse"
hook "$tmp/plain" "git commit -m \"x

Co-Authored-By: Jane <j@x.org>\""; assert_eq 0 "$code" "human co-author allowed"
hook "$tmp/plain" "git log --grep \"$T\""; assert_eq 0 "$code" "searching history allowed"
hook "$tmp/plain" "echo git commit \"$T\""; assert_eq 0 "$code" "echo of the words allowed"
hook "$tmp/plain" 'ls -la'; assert_eq 0 "$code" "unrelated command allowed"

out=$(printf '' | bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "empty stdin allowed silently"
out=$(printf '{not json' | bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "invalid JSON allowed silently"
out=$(perl -MJSON::PP -e 'print encode_json({cwd=>"/x",tool_input=>{command=>"git commit -m \"x\n\n$ARGV[0]: Claude <a\@b>\""}})' "$CO" | PATRICK_WORKFLOWS_GUARD=off bash "$GUARD" 2>&1); assert_eq "0:" "$?:$out" "PATRICK_WORKFLOWS_GUARD=off disables"

hj=$(cat "$ROOT/hooks/hooks.json")
assert_contains "$hj" '"PreToolUse"' "hook event registered"
assert_contains "$hj" '"matcher": "Bash"' "Bash matcher"
assert_contains "$hj" '${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh' "runs the guard from the plugin root"
finish
