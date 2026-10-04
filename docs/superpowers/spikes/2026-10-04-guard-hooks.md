# Spike: plugin PreToolUse hooks (sub-project B)

Date: 2026-10-04. Throwaway plugin with `hooks/hooks.json` registering a `PreToolUse` hook on `Bash` that ran `bash "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"`, loaded with `claude -p --plugin-dir`.

## Questions and answers
1. **Hook JSON on stdin.** One line of JSON:
   `{"session_id":…,"transcript_path":…,"cwd":"<session cwd>","permission_mode":…,"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"…","description":"…"},"tool_use_id":…}`.
   The command is a JSON string: `"` arrives as `\"`, `\` as `\\`, and a newline as `\n`. Observed: `echo "hi \"q\" back\\slash"` arrived as `"command":"echo \"hi \\\"q\\\" back\\\\slash\""`.
2. **Block semantics.** Exit 2 blocks the tool call. Claude sees stderr as `PreToolUse:Bash hook error: [<command>]: <stderr>`, followed by the name of the plugin the hook came from. Exit 0 with no output allows the call silently.
3. **`${CLAUDE_PLUGIN_ROOT}`.** It expands in the hook command, and it is also set in the hook's environment. The hook's working directory is the session cwd, which matches the JSON's `cwd` field.

## Consequences for the plan
- Decode the JSON string with `perl`, which macOS ships and `dev-server.sh` already uses. Only escapes need handling, not full JSON parsing.
- Use the JSON `cwd` field for git and ticket lookups.
- Keep a fast path: commands that are not `git commit`, `git push` or `gh pr create|edit` exit 0 before any git or state lookup, because the hook runs on every Bash call.
