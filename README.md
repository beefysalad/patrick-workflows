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

## /review-mine

Reviews the current branch with fresh critics, keeps only findings that come with evidence, fixes Critical and Important ones with a failing test first, re-reviews the fixes with a new critic, and stops at an explicit PASS, a plateau, or the budget. It commits fixes to your branch and never pushes.

```
/review-mine [base] [--depth lite|standard] [--criteria <file>] [--scope <file>] [--no-fix]
             [--prove "<cmd>" [--reset "<cmd>" --env-file <file> --db-pattern <regex>]]
```

Working files go to `~/.patrick-workflows/tickets/<repo>/_reviews/` (override with `TICKETS_HOME`), never into your project. Claude Code refuses writes under `~/.claude/`, so the workspace lives outside it.

**Permissions.** To run without prompts, allow these in your settings (confirmed in `docs/superpowers/spikes/2026-10-03-phase-1a.md`):
- `Read(~/.patrick-workflows/**)` and `Edit(~/.patrick-workflows/**)` (Edit rules cover all file-writing tools; Write rules are not matched)
- `Bash(bash *skills/review-mine/scripts/*)`
- your project's gate commands, for example `Bash(npm test*)`, `Bash(npm run lint*)`
- optional: `Bash(gh pr view*)`, so the bar can be built from your PR description

**Exit pair safety.** `--reset` runs only when the database in `--env-file` matches `--db-pattern` and its host is local. Anything else is refused before a reset runs.

Tests: `bash tests/run.sh`. End-to-end: `tests/SMOKE.md`.

## Add a workflow

1. Create the file in the right directory with kebab-case name and `description` frontmatter.
2. Run `./scripts/validate.sh`.
3. Bump `version` in `.claude-plugin/plugin.json`. This is required for the change to reach other machines.
4. Commit (`feat:`), push, and `git tag vX.Y.Z`.

## Rules

Keep everything generic: no employer-specific content or secrets. Work-only
context belongs in that project's own `.claude/`.

## License

MIT
