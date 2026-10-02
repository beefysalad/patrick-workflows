# Claude Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold a portable, public-safe Claude Code plugin + marketplace repo holding skills, commands, agents, hooks, and CLAUDE.md/settings templates.

**Architecture:** The repo root is both a marketplace (`.claude-plugin/marketplace.json`) and a single plugin (`.claude-plugin/plugin.json`, source `./`). Components live in flat per-type directories. A small bash script, `scripts/validate.sh`, acts as the test suite: it checks structure, JSON validity, and frontmatter, and is written before the files it checks.

**Tech Stack:** Markdown, JSON, bash, git. Claude Code plugin system.

**Spec:** `docs/superpowers/specs/2026-10-02-claude-workflows-design.md`

## Global Constraints

- Single plugin named `jp-workflows`; repo root is both marketplace and plugin (`source: "./"`).
- Layout exactly: `.claude-plugin/{marketplace,plugin}.json`, `skills/<name>/SKILL.md`, `commands/<name>.md`, `agents/<name>.md`, `hooks/hooks.json`, `templates/{CLAUDE.md,settings.json}`, `README.md`.
- Names are short kebab-case.
- Nothing employer-specific or secret anywhere in the repo.
- Starter content is one minimal example of each type; do not invent extra workflows.
- `templates/` is never auto-loaded; plugins cannot ship a global CLAUDE.md or settings.json.
- Branch `main`; Conventional Commit messages (`feat:`, `docs:`, `chore:`); license MIT.

## Review Focus

- Path contains a space (`claude workflows`): scripts must quote all paths and work from any cwd.
- `validate.sh` run with a missing file must fail with a message naming the file, not pass silently.
- Malformed JSON in a manifest must fail validation, not be skipped.
- SKILL.md / command / agent files missing frontmatter must fail validation.
- `.gitignore` must keep `settings.local.json` and `.env*` out even inside `templates/`.

## File Structure

| File | Responsibility |
|---|---|
| `.gitignore` | Keep machine-local and secret files out of git |
| `LICENSE` | MIT |
| `scripts/validate.sh` | Structure/JSON/frontmatter checks (the test suite) |
| `.claude-plugin/plugin.json` | Plugin identity and version |
| `.claude-plugin/marketplace.json` | Lets `/plugin marketplace add` find the plugin |
| `skills/hello/SKILL.md` | Example skill |
| `commands/hello.md` | Example slash command |
| `agents/example-reviewer.md` | Example subagent |
| `hooks/hooks.json` | Empty hooks registry |
| `templates/CLAUDE.md` | Global CLAUDE.md starting point (manual copy) |
| `templates/settings.json` | Settings starting point (manual copy) |
| `README.md` | Install, update, add-a-workflow guide |

---

### Task 1: Repo hygiene and validation harness

**Files:**
- Create: `.gitignore`, `LICENSE`, `scripts/validate.sh`

**Interfaces:**
- Produces: `scripts/validate.sh`, exit code 0 when the repo is valid, non-zero otherwise, with one `FAIL: <reason>` line per problem. Later tasks run it as their test.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.DS_Store
settings.local.json
**/settings.local.json
.env
.env.*
*.local
tmp/
scratch/
```

- [ ] **Step 2: Write `LICENSE`** (standard MIT text)

```text
MIT License

Copyright (c) 2026 jpatrickzxc

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Write `scripts/validate.sh`**

```bash
#!/usr/bin/env bash
# Validates repo structure, JSON manifests, and markdown frontmatter.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
fail=0
bad() { echo "FAIL: $1"; fail=1; }

need_file() { [ -f "$1" ] || bad "missing file: $1"; }

check_json() {
  [ -f "$1" ] || { bad "missing file: $1"; return; }
  python3 -m json.tool "$1" >/dev/null 2>&1 || bad "invalid JSON: $1"
}

# Frontmatter: first line must be '---' and a closing '---' must follow.
check_frontmatter() {
  local f="$1"
  [ -f "$f" ] || { bad "missing file: $f"; return; }
  [ "$(head -n 1 "$f")" = "---" ] || { bad "no frontmatter: $f"; return; }
  tail -n +2 "$f" | grep -q '^---$' || bad "unterminated frontmatter: $f"
  sed -n '2,/^---$/p' "$f" | grep -q '^description:' || bad "no description in frontmatter: $f"
}

check_json .claude-plugin/plugin.json
check_json .claude-plugin/marketplace.json
check_json hooks/hooks.json
check_json templates/settings.json
need_file templates/CLAUDE.md
need_file README.md
need_file LICENSE
need_file .gitignore

for f in skills/*/SKILL.md commands/*.md agents/*.md; do
  [ -e "$f" ] || continue
  check_frontmatter "$f"
done

# At least one of each component type must exist.
ls skills/*/SKILL.md >/dev/null 2>&1 || bad "no skills found"
ls commands/*.md     >/dev/null 2>&1 || bad "no commands found"
ls agents/*.md       >/dev/null 2>&1 || bad "no agents found"

[ "$fail" -eq 0 ] && echo "OK: repo is valid"
exit "$fail"
```

- [ ] **Step 4: Run it to verify it fails**

Run: `chmod +x "scripts/validate.sh" && ./scripts/validate.sh; echo "exit=$?"`
Expected: several `FAIL:` lines (missing manifests, skills, etc.) and `exit=1`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore LICENSE scripts/validate.sh
git commit -m "chore: add gitignore, MIT license, and validation script"
```

---

### Task 2: Plugin and marketplace manifests

**Files:**
- Create: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: plugin name `claude-workflows`, version `0.1.0`, marketplace name `claude-workflows`.

- [ ] **Step 1: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "claude-workflows",
  "version": "0.1.0",
  "description": "Personal, portable Claude Code workflows: skills, commands, agents, and hooks.",
  "license": "MIT"
}
```

- [ ] **Step 2: Write `.claude-plugin/marketplace.json`**

```json
{
  "name": "claude-workflows",
  "owner": { "name": "jpatrickzxc" },
  "plugins": [
    {
      "name": "claude-workflows",
      "source": "./",
      "description": "Personal, portable Claude Code workflows."
    }
  ]
}
```

- [ ] **Step 3: Verify the manifests parse**

Run: `./scripts/validate.sh | grep -E "plugin.json|marketplace.json"`
Expected: no output (no failures mention the manifests).

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin
git commit -m "feat: add plugin and marketplace manifests"
```

---

### Task 3: Starter components (skill, command, agent, hooks)

**Files:**
- Create: `skills/hello/SKILL.md`, `commands/hello.md`, `agents/example-reviewer.md`, `hooks/hooks.json`

**Interfaces:**
- Consumes: `scripts/validate.sh` frontmatter and JSON checks (Task 1).

- [ ] **Step 1: Write `skills/hello/SKILL.md`**

```markdown
---
name: hello
description: Example skill. Use when the user asks to test that the claude-workflows plugin is installed and loading.
---

# Hello

Reply with one line confirming the `claude-workflows` plugin is loaded, then
list the components it provides (skills, commands, agents). Replace this skill
with a real workflow.
```

- [ ] **Step 2: Write `commands/hello.md`**

```markdown
---
description: Example command that confirms the claude-workflows plugin is loaded
---

Confirm the `claude-workflows` plugin is installed by replying "claude-workflows
is loaded" and naming any arguments passed: $ARGUMENTS
```

- [ ] **Step 3: Write `agents/example-reviewer.md`**

```markdown
---
name: example-reviewer
description: Example subagent. Reviews a given file for clarity and reports concrete suggestions. Replace with a real agent.
tools: Read, Grep, Glob
---

You are a concise reviewer. Read the file(s) you are given and report up to
five concrete, specific suggestions to improve clarity. Do not edit files.
```

- [ ] **Step 4: Write `hooks/hooks.json`**

```json
{
  "hooks": {}
}
```

- [ ] **Step 5: Run validation**

Run: `./scripts/validate.sh`
Expected: only remaining failures are `templates/` and `README.md` (Tasks 4-5).

- [ ] **Step 6: Commit**

```bash
git add skills commands agents hooks
git commit -m "feat: add example skill, command, agent, and empty hooks"
```

---

### Task 4: Templates

**Files:**
- Create: `templates/CLAUDE.md`, `templates/settings.json`

- [ ] **Step 1: Write `templates/CLAUDE.md`**

```markdown
# Global Claude instructions

<!-- Copy to ~/.claude/CLAUDE.md (global) or <project>/CLAUDE.md (per project). -->
<!-- Keep this generic: no employer names, internal URLs, or secrets. -->

## Working style
- Prefer small, reviewable changes.
- Ask before destructive or outward-facing actions.

## Code
- Match the surrounding code's style and conventions.
- Run the project's tests before declaring work done.
```

- [ ] **Step 2: Write `templates/settings.json`**

```json
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
```

- [ ] **Step 3: Verify**

Run: `./scripts/validate.sh | grep templates`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add templates
git commit -m "feat: add CLAUDE.md and settings.json templates"
```

---

### Task 5: README, final verification, tag

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# claude-workflows

Personal, portable Claude Code workflows packaged as a plugin.

## Install

```
/plugin marketplace add <github-user>/claude-workflows
/plugin install claude-workflows@claude-workflows
```

Local checkout: `/plugin marketplace add /path/to/claude-workflows`

For a private repo, the machine needs git credentials for GitHub.

## Update

```
/plugin marketplace update claude-workflows
```

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
3. Bump `version` in `.claude-plugin/plugin.json` when releasing.
4. Commit (`feat:`), push, and `git tag vX.Y.Z`.

## Rules

Keep everything generic: no employer-specific content or secrets. Work-only
context belongs in that project's own `.claude/`.

## License

MIT
````

- [ ] **Step 2: Run the full validation**

Run: `./scripts/validate.sh; echo "exit=$?"`
Expected: `OK: repo is valid` and `exit=0`.

- [ ] **Step 3: Validate with Claude Code, if available**

Run: `claude plugin validate .`
Expected: passes. If the subcommand is not available, skip and say so in the report.

- [ ] **Step 4: Confirm it loads from a local marketplace**

In a Claude Code session, run `/plugin marketplace add "<repo path>"` then `/plugin install claude-workflows@claude-workflows`, then run `/claude-workflows:hello`.
Expected: replies "claude-workflows is loaded". (Manual step; report the outcome.)

- [ ] **Step 5: Commit and tag**

```bash
git add README.md
git commit -m "docs: add README"
git tag v0.1.0
```

- [ ] **Step 6 (optional, needs approval): Create the private GitHub remote**

```bash
gh repo create claude-workflows --private --source . --push
git push --tags
```
Do this only after the user confirms; it publishes content to an external service.
