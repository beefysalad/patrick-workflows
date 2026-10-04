# Graded bar smoke test
```bash
# from the repo root; the target folder must not exist yet
d=$(mktemp -d)/ui-site && bash tests/fixture/ui-setup.sh "$d" && cd "$d"
claude -p --plugin-dir "<repo>" --permission-mode acceptEdits \
  --allowedTools "Read(~/.patrick-workflows/**)" "Edit(~/.patrick-workflows/**)" "Bash(bash *)" "Bash(git *)" "Bash(node *)" "Bash(npx --yes playwright*)" "Bash(curl *)" "Skill" "Agent" "Read" "Grep" "Glob" "Write" "Edit" \
  -- "/patrick-workflows:review-mine main --graded graded.md --depth standard" < /dev/null
```

- [ ] Dev server started and stopped (no `node server.js` left running: `pgrep -f "node server.js"` is empty).
- [ ] `graded/reference`, `graded/round-1/ours` and `graded/round-1/ours-first` contain 4 PNGs each (`home-*`).
- [ ] Two scorer files when round 1 passes; one when it fails; `graded-ab.sh verdict` lines in the report.
- [ ] Gaps became visual findings for the fixer (Expected states a quality, plus the do-not-copy sentence); the fix report has `FIXED-VISUAL captures:` lines; scores improve across rounds or the run stops on plateau/cap with the best score reported.
- [ ] The scorer's folders never contain the mapping file.
