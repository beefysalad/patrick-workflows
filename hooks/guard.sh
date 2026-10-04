#!/usr/bin/env bash
# PreToolUse guard for Bash tool calls (registered in hooks/hooks.json).
# Reads the hook JSON on stdin. Exit 0 allows the command; exit 2 blocks it and stderr tells Claude why.
# Rule 1 (always): no tool attribution (a Claude co-author trailer or a "Generated with Claude Code"
# footer) in git commit or gh pr create/edit text, including files passed with -F/--file/--body-file.
# Fails open: input it cannot read allows the command and prints nothing.
# PATRICK_WORKFLOWS_GUARD=off in Claude Code's environment turns every rule off.
set -u
[ "${PATRICK_WORKFLOWS_GUARD:-on}" = off ] && exit 0
in=$(cat 2>/dev/null) || exit 0

# field <name>: the first "<name>": "<string>" value in the hook JSON, with its JSON escapes undone.
field() {
  printf '%s' "$in" | F="$1" perl -0777 -ne '
    my $f = $ENV{F};
    if (/"\Q$f\E"\s*:\s*"((?:[^"\\]|\\.)*)"/s) {
      my $s = $1;
      my %e = ("\"" => "\"", "\\" => "\\", "/" => "/", b => "\b", f => "\f", n => "\n", r => "\r", t => "\t");
      $s =~ s/\\(?:u([0-9a-fA-F]{4})|(.))/defined $1 ? do { my $c = chr(hex $1); utf8::encode($c); $c } : (exists $e{$2} ? $e{$2} : $2)/ge;
      print $s;
    }' 2>/dev/null
}
cmd=$(field command)
[ -n "$cmd" ] || exit 0
dir=$(field cwd); [ -d "$dir" ] || dir=$PWD

# has <ERE>: the command runs it at the start, or after ; & | ( { ` or $( (so "echo git commit" does not count).
has() { printf '%s\n' "$cmd" | grep -Eq "(^|[;&|(\`{]) *$1"; }
G='git( +-[Cc] +[^ ;&|]+)* +'   # git plus its -C/-c options
is_commit() { has "${G}commit([[:space:]]|\$)"; }
is_push() { has "${G}push([[:space:]]|\$)"; }
is_pr() { has "gh +pr +(create|edit)([[:space:]]|\$)"; }
block() { printf 'patrick-workflows guard: %s\n' "$1" >&2; exit 2; }

is_commit || is_push || is_pr || exit 0

# Rule 1: no tool attribution.
if is_commit || is_pr; then
  text=$cmd
  files=$(printf '%s\n' "$cmd" | perl -ne 'while (/(?:^|\s)(?:-F|--file|--body-file)(?:\s+|=)("[^"]*"|\x27[^\x27]*\x27|[^\s;&|]+)/g) { my $f = $1; $f =~ s/^["\x27]|["\x27]$//g; print "$f\n" }' 2>/dev/null)
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$f" != - ] || continue
    case $f in /*) p=$f ;; "~/"*) p="$HOME/${f#\~/}" ;; *) p="$dir/$f" ;; esac
    [ -f "$p" ] && text="$text
$(cat "$p" 2>/dev/null)"
  done <<EOF
$files
EOF
  if printf '%s\n' "$text" | grep -Eiq 'co-authored-by:[[:space:]]*claude|generated with \[?claude code'; then
    block 'remove the Claude co-author trailer or "Generated with Claude Code" footer from the commit message or PR text: this repo owner allows no tool attribution.'
  fi
fi
exit 0
