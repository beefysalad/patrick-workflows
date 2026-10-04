# Guard hook smoke test
```bash
d=$(mktemp -d) && cd "$d" && git init -q -b main && git commit -q --allow-empty -m init
claude -p --plugin-dir "<repo>" --allowedTools "Bash(git *)" \
  -- 'Run exactly this with the Bash tool and report the full result: git commit --allow-empty -m "chore: smoke" -m "Co-Authored""-By: Claude <noreply@anthropic.com>"' < /dev/null
git log --oneline | wc -l   # still 1
```
- [ ] Claude reports a `PreToolUse:Bash hook error` whose text starts with `patrick-workflows guard:`.
- [ ] `git log` shows no new commit.
- [ ] Rerun with `-m "chore: smoke"` only: the commit is made.
