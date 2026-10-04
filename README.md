# patrick-workflows

Personal, portable Claude Code workflows packaged as a plugin.

## Install

```
/plugin marketplace add beefysalad/patrick-workflows
/plugin install patrick-workflows@patrick-workflows
```

Local checkout: `/plugin marketplace add /path/to/patrick-workflows`

## Update

```
/plugin marketplace update patrick-workflows
/plugin update patrick-workflows@patrick-workflows
```

Restart Claude Code afterwards. Installs are cached by `version`, so a change
only reaches other machines after `version` is bumped in
`.claude-plugin/plugin.json`.

## Layout

| Path | What |
|---|---|
| `skills/<name>/SKILL.md` | Skills |
| `commands/<name>.md` | Slash commands |
| `agents/<name>.md` | Subagents |
| `hooks/hooks.json` | Hooks |
| `templates/` | CLAUDE.md and settings.json to copy manually (plugins can't ship these) |

## /ticket

```
/ticket ABC-123        start or continue a ticket (ID, URL, or pasted text)
/ticket                list tickets in this repo
```

- **PLAN (with you):** reads the ticket, settles acceptance criteria, creates the branch (or a worktree, if you ask for one), brainstorms the design, writes the plan, and agrees an autonomy brief: gates, scope, review depth, budget, an optional exit pair, and the permission rules to add.
- **BUILD (on its own):** one fresh implementer and reviewer per task, test first, gates re-run by the orchestrator, then the `/review-mine` loop. Asks nothing.
- **SHIP (with you):** one report with numbered questions. Ask for changes and it runs a second round; say yes and it scans for secrets, then opens a draft PR.

Run `/ticket <id>` again at any time to resume where it stopped. If another plugin also defines `/ticket` or `/review-mine`, use the namespaced form: `/patrick-workflows:ticket`, `/patrick-workflows:review-mine`. Working files live in `~/.patrick-workflows/tickets/<repo>/<id>/`. After the PR is merged, run `/ticket <id>` once more: it marks the ticket done (a GitHub issue is closed by the URL recorded at intake, never by bare number) and cleans up. After a squash or rebase merge it deletes the local branch with `-D` only when the branch tip is exactly the commit GitHub merged; otherwise it keeps the branch and says why.

Optional: list company names and internal hostnames, one per line, in your work project's `.claude/patrick-workflows-deny.txt`. SHIP refuses to open a PR whose body or diff contains them.

Permission rules: absolute paths outside your home directory need a leading `//` (for example `Edit(//opt/data/**)`); paths under your home use `~/`.

## /review-mine

Reviews the current branch with fresh critics, keeps only findings that come with evidence, fixes Critical and Important ones with a failing test first, re-reviews the fixes with a new critic, and stops at an explicit PASS, a plateau, or the budget. It commits fixes to your branch and never pushes.

```
/review-mine [base] [--depth lite|standard] [--criteria <file>] [--scope <file>] [--graded <graded.md>]
             [--no-fix] [--prove "<cmd>" [--reset "<cmd>" --env-file <file> --db-pattern <regex>]]
```

**UI grading.** For features with a visual or interactive component, pass a graded scoring configuration file. The file defines reference screenshots (`image-dir:`, `route:` or `url:`), routes to capture, dev command, rubric (3–6 criteria with anchors for scores 1, 3, and 5), and thresholds (margin 0.3, floor 3.5, min 3). The reference is one page, compared with the first route in the routes file; rubric anchors describe qualities, never "same as the reference", and fixers are told not to copy it (a tie on every criterion is raised as a question in the report). The check passes when our score is at least the reference score minus 0.3, at least 3.5 overall, with no criterion below 3, and a second independent scorer agrees. A page that answers with a non-2xx HTTP status is not captured, and a graded bar that cannot run (dev server, capture or reference failure) ends the review BLOCKED with the reason. Screenshots use Playwright (default `npx --yes playwright screenshot --channel chrome`), which captures light and dark; only the headless Chrome fallback is light only. Requires `Bash(npx --yes playwright*)` permission rule.

Working files go to `~/.patrick-workflows/tickets/<repo>/_reviews/` (override with `TICKETS_HOME`), never into your project. Claude Code refuses writes under `~/.claude/`, so the workspace lives outside it.

**Permissions.** To run without prompts, allow these in your settings (confirmed in `docs/superpowers/spikes/2026-10-03-phase-1a.md`):
- `Read(~/.patrick-workflows/**)` and `Edit(~/.patrick-workflows/**)` (Edit rules cover all file-writing tools; Write rules are not matched)
- `Bash(bash *skills/review-mine/scripts/*)`
- your project's gate commands, for example `Bash(npm test*)`, `Bash(npm run lint*)`
- optional: `Bash(gh pr view*)`, so the bar can be built from your PR description
- for `/ticket` CLOSE: `Bash(git worktree*)`, `Bash(git branch*)`, `Bash(git pull*)`, `Bash(gh pr view*)`, `Bash(gh issue view*)`, `Bash(gh issue close*)`

**Exit pair safety.** `--reset` runs only when the database in `--env-file` matches `--db-pattern` and its host is local. Anything else is refused before a reset runs.

Tests: `bash tests/run.sh`. End-to-end: `tests/SMOKE.md`.

## Add a workflow

1. Create the file in the right directory with kebab-case name and `description` frontmatter.
2. Run `./scripts/validate.sh`.
3. Bump `version` in `.claude-plugin/plugin.json`. This is required for the change to reach other machines.
4. Commit (`feat:`), run `bash scripts/check-commits.sh` before pushing, then push and `git tag vX.Y.Z`.

## Rules

Keep everything generic: no employer-specific content or secrets. Work-only
context belongs in that project's own `.claude/`.

## License

MIT
