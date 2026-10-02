# Claude Workflows: Design

Date: 2026-10-02

## Purpose

A personal, portable repo of Claude Code workflows that can be installed on any machine (personal or work) in two commands and updated through git.

## Requirements

- Holds four kinds of content: skills, slash commands, subagents, and hooks/settings, plus CLAUDE.md templates.
- Distributed as a Claude Code plugin (named `patrick-workflows`; names starting with `claude-` are reserved by Claude Code) with a marketplace manifest, so install is `/plugin marketplace add <source>` then `/plugin install`.
- One public-safe plugin: nothing employer-specific or secret in the repo. Work-only context stays in that project's own `.claude/`.
- YAGNI: ship a minimal skeleton, not invented workflows.

## Approach

Single plugin plus marketplace manifest in one repo (the repo root is both). It can be split into several plugins later without breaking installs.

Rejected: a symlink install script (per-OS scripts, can clash with managed work machines) and multiple small plugins (overkill for an empty repo).

## Structure

```
claude-workflows/
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── skills/<name>/SKILL.md
├── commands/<name>.md
├── agents/<name>.md
├── hooks/hooks.json
├── templates/
│   ├── CLAUDE.md
│   └── settings.json
└── README.md
```

- Plugins cannot ship a global `CLAUDE.md` or full `settings.json`; `templates/` holds copies to place manually once per machine. They are not auto-loaded.
- Each workflow is a small self-contained file or folder. Names are short kebab-case.
- README covers install, updating, and a short "add a workflow" checklist.

## Starter content

One example of each type, to be replaced as real workflows are written:
- a minimal `hello` skill
- one command
- one agent
- a no-op `hooks/hooks.json`
- `templates/CLAUDE.md` and `templates/settings.json`

## Verification

- Run `claude plugin validate` if available.
- Add the repo locally as a marketplace (`/plugin marketplace add ./`), install the plugin, and confirm the skill, command, and agent load.

## Repo setup

- `git init` with `main` as the default branch.
- `.gitignore`: `.DS_Store`, `settings.local.json`, `.env*`, scratch folders.
- `LICENSE`: MIT.
- Conventional Commit messages (`feat:`, `docs:`, `chore:`); `plugin.json` version bumped on releases and tagged (`v0.1.0`).
- GitHub remote is **public**, so the plugin installs on any machine (including a work laptop with a different GitHub account) with no credentials. Content must stay generic and secret-free; the commit author identity and real name in LICENSE/manifests are public.

## Open items

- None.
