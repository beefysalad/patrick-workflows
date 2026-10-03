#!/usr/bin/env bash
# Read and update a ticket's state.md ("key: value" lines) and enforce the phase machine.
# Usage: state.sh <state-file> get <key>
#        state.sh <state-file> set <key> <value>
#        state.sh <state-file> incr <key> [n]
#        state.sh <state-file> phase <new-phase>
# Exit: 0 ok, 1 key absent (get), 2 bad input or illegal phase transition.
set -u
f=${1:-}; cmd=${2:-}; key=${3:-}
[ -n "$f" ] && [ -n "$cmd" ] || { echo "usage: state.sh <file> get|set|incr|phase ..." >&2; exit 2; }

# Legal phase transitions (spec section 6). "none" is a ticket with no phase yet.
ALLOWED=" none>intake intake>designed designed>planned planned>approved approved>implementing
 implementing>reviewing implementing>blocked reviewing>fixing fixing>reviewing reviewing>ready
 reviewing>blocked fixing>blocked ready>handoff blocked>handoff handoff>round2 round2>implementing
 handoff>pr pr>closed "

valid_key() { printf '%s' "$1" | grep -Eq '^[a-z0-9_.-]+$'; }
get() {
  [ -f "$f" ] && grep -q "^$1: " "$f" || return 1
  sed -n "s/^$1: //p" "$f" | head -n 1
}
put() {
  mkdir -p "$(dirname "$f")" || exit 2
  if [ -f "$f" ] && grep -q "^$1: " "$f"; then
    tmpf="$f.tmp.$$"
    # ENVIRON, not awk -v: -v would turn backslashes in the value into escapes.
    K="$1: " V="$2" awk 'index($0, ENVIRON["K"]) == 1 { print ENVIRON["K"] ENVIRON["V"]; next } { print }' "$f" > "$tmpf" && mv "$tmpf" "$f"
  else
    printf '%s: %s\n' "$1" "$2" >> "$f"
  fi
}

case $cmd in
  get)
    valid_key "$key" || { echo "invalid key: $key" >&2; exit 2; }
    get "$key" || exit 1 ;;
  set)
    valid_key "$key" || { echo "invalid key: $key" >&2; exit 2; }
    put "$key" "${4-}" ;;
  incr)
    valid_key "$key" || { echo "invalid key: $key" >&2; exit 2; }
    n=${4:-1}; cur=$(get "$key" 2>/dev/null || echo 0)
    case "$cur$n" in *[!0-9]*) echo "not a number: $key=$cur" >&2; exit 2 ;; esac
    new=$((cur + n)); put "$key" "$new"; echo "$new" ;;
  phase)
    [ -n "$key" ] || { echo "usage: state.sh <file> phase <new>" >&2; exit 2; }
    cur=$(get phase 2>/dev/null || echo none); [ -n "$cur" ] || cur=none
    [ "$cur" = "$key" ] && exit 0
    allowed=$(printf '%s' "$ALLOWED" | tr '\n' ' ')
    case "$allowed" in
      *" $cur>$key "*) ;;
      *) echo "illegal transition: $cur -> $key" >&2; exit 2 ;;
    esac
    put phase "$key"
    printf '%s phase %s -> %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cur" "$key" >> "$(dirname "$f")/ledger.md" ;;
  *)
    echo "unknown command: $cmd" >&2; exit 2 ;;
esac
