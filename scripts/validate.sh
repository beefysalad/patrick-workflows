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
