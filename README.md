# jp-workflows

Personal, portable Claude Code workflows packaged as a plugin.

## Install

```
/plugin marketplace add <github-user>/claude-workflows
/plugin install jp-workflows@jp-workflows
```

Local checkout: `/plugin marketplace add /path/to/claude-workflows`

For a private repo, the machine needs git credentials for GitHub.

## Update

```
/plugin marketplace update jp-workflows
/plugin update jp-workflows@jp-workflows
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
