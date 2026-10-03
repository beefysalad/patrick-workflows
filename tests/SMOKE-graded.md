# Graded bar smoke test
```bash
bash tests/fixture/ui-setup.sh /tmp/ui-site && cd /tmp/ui-site
claude -p --plugin-dir "<repo>" --permission-mode acceptEdits \
  --allowedTools "Read(~/.patrick-workflows/**)" "Edit(~/.patrick-workflows/**)" "Bash(bash *)" "Bash(git *)" "Bash(node *)" "Bash(npx --yes playwright*)" "Bash(curl *)" "Skill" "Agent" "Read" "Grep" "Glob" "Write" "Edit" \
  -- "/patrick-workflows:review-mine main --graded graded.md --depth standard" < /dev/null
```

- [ ] Dev server started and stopped (no `node server.js` left running: `pgrep -f "node server.js"` is empty).
- [ ] `graded/reference` and `graded/round-1/ours` contain 4 PNGs each.
- [ ] Two scorer files when round 1 passes; one when it fails; `graded-ab.sh verdict` lines in the report.
- [ ] Gaps became visual findings for the fixer; scores improve across rounds or the run stops on plateau/cap with the best score reported.
- [ ] The scorer's folders never contain the mapping file.
