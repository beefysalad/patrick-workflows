# /gauntlet-review smoke test

Run before every release. Record results in the release commit message or a note.

## Setup
```bash
bash tests/fixture/setup.sh /tmp/rm-fixture
cd /tmp/rm-fixture
claude --plugin-dir "<path to this repo>"
```
Allow the rules listed in the README's Permissions section first, or the run will stop at permission prompts.

## Run 1: standard depth, scope and exit pair
```
/gauntlet-review main --depth standard --scope <path to this repo>/tests/fixture/scope.txt --prove "npm run e2e" --reset "npm run db:reset" --env-file .env.test --db-pattern 'test\.db$'
```
Expected:
- [ ] No questions asked after setup.
- [ ] `baseline.md` lists the `known red: formatPrice...` test as a known red; the run continues.
- [ ] Negative total (`applyDiscount(1000, 150)`) is found, fixed, and has a red test named in the report.
- [ ] `SAVEabc` → NaN is found and fixed with a red test.
- [ ] The duplicate `applyDiscountPercent` is found as structural and marked ADDRESSED by the re-review.
- [ ] `loadCoupons` is reported, either fixed with a red test or listed under "Unreproduced findings". It is never silently dropped.
- [ ] `package-lock.json` is classified incidental; `src/billing/rates.js` is forbidden and the change is reverted by a fix round.
- [ ] Exit pair: `pass` (reset ran before each run).
- [ ] Outcome `READY`, or `BLOCKED` with a stated reason that matches the workspace files.
- [ ] Nothing was pushed; the workspace is under `~/.patrick-workflows/tickets/rm-fixture/_reviews/`.

## Run 2: refusal of an unsafe reset
Edit `.env.test` to `DATABASE_URL=postgres://prod.example.com/app` and commit it, then rerun the Run 1 command.
- [ ] Exit pair reported as `refused` with "not local" or "does not match"; the reset command never ran.

## Run 3: lite depth, review only
```bash
bash tests/fixture/setup.sh /tmp/rm-fixture-2 && cd /tmp/rm-fixture-2
```
```
/gauntlet-review main --depth lite --no-fix
```
- [ ] One combined critic; no commits made; report lists findings with IDs and evidence.

## Record
For each run: dispatches used / budget, findings raised / kept after the evidence filter / fixed, rounds used, wall time. These numbers decide whether the loop earns its cost.
