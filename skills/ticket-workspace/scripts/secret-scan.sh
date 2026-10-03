#!/usr/bin/env bash
# Flag secrets and deny-listed strings in files without printing them.
# Usage: secret-scan.sh [--deny-file <file>] <file|->...
# Prints "<file>:<line>: <rule>" per hit. Exit: 0 clean, 1 hits, 2 bad input.
set -u
deny=""
if [ "${1:-}" = "--deny-file" ]; then
  deny=${2:-}; shift 2
  [ -f "$deny" ] || { echo "deny file not found: $deny" >&2; exit 2; }
fi
[ $# -gt 0 ] || { echo "usage: secret-scan.sh [--deny-file <file>] <file|->..." >&2; exit 2; }
q="['\"]"   # either quote character
RULES="aws-access-key|AKIA[0-9A-Z]{16}
private-key|-----BEGIN [A-Z ]*PRIVATE KEY-----
github-token|gh[pousr]_[A-Za-z0-9]{36,}
slack-token|xox[baprs]-[A-Za-z0-9-]{10,}
stripe-key|[sr]k_(live|test)_[A-Za-z0-9]{16,}
jwt|eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}
password-assignment|(password|passwd|secret|api_?key|access_?token)$q?[[:space:]]*[:=][[:space:]]*$q[^'\"]{8,}$q
url-credentials|[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]+@"
tmpd=$(mktemp -d); trap 'rm -rf "$tmpd"' EXIT
hits=0
scan() {   # $1 path to read, $2 name to report
  while IFS= read -r rule; do
    name=${rule%%|*}; re=${rule#*|}
    for n in $(grep -niE -e "$re" "$1" 2>/dev/null | cut -d: -f1); do
      printf '%s:%s: %s\n' "$2" "$n" "$name"; hits=1
    done
  done <<RULES_EOF
$RULES
RULES_EOF
  if [ -n "$deny" ]; then
    while IFS= read -r s || [ -n "$s" ]; do
      case $s in ''|'#'*) continue ;; esac
      for n in $(grep -niF -e "$s" "$1" 2>/dev/null | cut -d: -f1); do
        printf '%s:%s: deny-list\n' "$2" "$n"; hits=1
      done
    done < "$deny"
  fi
}
for f in "$@"; do
  if [ "$f" = "-" ]; then cat > "$tmpd/stdin"; scan "$tmpd/stdin" stdin
  elif [ -f "$f" ]; then scan "$f" "$f"
  else echo "not a file: $f" >&2; exit 2
  fi
done
exit "$hits"
