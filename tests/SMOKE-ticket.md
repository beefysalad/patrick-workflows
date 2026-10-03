# /ticket smoke test

## Run A (headless): BUILD and SHIP from a seeded ticket
```bash
bash tests/fixture/setup.sh /tmp/tk-shop
bash tests/fixture/seed-ticket.sh /tmp/tk-shop
cd /tmp/tk-shop
claude -p --plugin-dir "<repo>" --permission-mode acceptEdits \
  --allowedTools "Read(~/.patrick-workflows/**)" "Edit(~/.patrick-workflows/**)" "Bash(bash *)" "Bash(git *)" "Bash(npm *)" "Bash(node *)" "Skill" "Agent" "Read" "Grep" "Glob" "Write" "Edit" \
  -- "/ticket FX-1" < /dev/null
```
Expected:
- [ ] BUILD resumes at `approved`; no questions until the SHIP report.
- [ ] `baseline.md` lists the known red formatPrice test.
- [ ] Two tasks, each with a `reports/task-N.md` naming a red test and a green run, and a `task N complete` ledger line.
- [ ] The orchestrator re-ran gates after each task (`review-mine/logs/task<N>-test.status`).
- [ ] The review loop ran in `review-mine/`; phase ends `ready` (or `blocked` with a reason matching the files).
- [ ] `handoff.md` has numbered questions ending with "Open the draft PR?"; phase `handoff`; nothing pushed (the fixture has no remote).
- [ ] `ledger.md` shows `approved -> implementing -> reviewing ... -> handoff` with no illegal jump.

## Run B (interactive): full PLAN on the fixture
```bash
bash tests/fixture/setup.sh /tmp/tk-shop-2 && cd /tmp/tk-shop-2 && claude --plugin-dir "<repo>"
```
`/ticket`, then paste the FX-1 ticket text from `tests/fixture/seed-ticket.sh`.
- [ ] Asked for an ID; acceptance criteria confirmed; branch name proposed.
- [ ] Design saved to the workspace, not `docs/`; nothing committed during PLAN.
- [ ] Plan written by `ticket-planner` into the workspace; brief shown once; permission rules printed.
- [ ] After approval, BUILD starts without a new command.

## Record
Dispatches used (implementation / review), tasks, rounds, wall time.
