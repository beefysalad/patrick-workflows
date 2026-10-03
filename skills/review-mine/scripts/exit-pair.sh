#!/usr/bin/env bash
# Prove a feature twice in a row, resetting state before each run.
# Usage: exit-pair.sh --prove "<cmd>" [--reset "<cmd>" --env-file <path> --db-pattern <ERE>
#                     [--db-var NAME] [--allow-remote]] [--timeout SECONDS]
# Needs a workspace (REVIEW_WS, else the pointer from workspace.sh). Prints one "EXIT-PAIR: <result> (...)" line.
# Exit: 0 pass, 1 fail, 3 could-not-run, 4 refused (reset target not proven disposable), 5 flaky.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prove=""; reset=""; envfile=""; pattern=""; dbvar=DATABASE_URL; remote=no; limit=900
while [ $# -gt 0 ]; do
  case $1 in
    --prove) prove=${2:-}; shift 2 ;;
    --reset) reset=${2:-}; shift 2 ;;
    --env-file) envfile=${2:-}; shift 2 ;;
    --db-pattern) pattern=${2:-}; shift 2 ;;
    --db-var) dbvar=${2:-}; shift 2 ;;
    --allow-remote) remote=yes; shift ;;
    --timeout) limit=${2:-}; shift 2 ;;
    *) echo "EXIT-PAIR: could-not-run (unknown option $1)"; exit 3 ;;
  esac
done
[ -n "$prove" ] || { echo "EXIT-PAIR: could-not-run (--prove is required)"; exit 3; }
if [ -z "${REVIEW_WS:-}" ]; then   # same pointer fallback as run-gate.sh
  ptr=$(git rev-parse --git-path patrick-workflows-review-ws 2>/dev/null) && [ -f "$ptr" ] && REVIEW_WS=$(head -n 1 "$ptr")
fi
[ -n "${REVIEW_WS:-}" ] || { echo "EXIT-PAIR: could-not-run (no workspace: REVIEW_WS unset and no pointer file)"; exit 3; }
export REVIEW_WS
refuse() { echo "EXIT-PAIR: refused ($1)"; exit 4; }

# Value of NAME in an env file, read as text (the file is not executed here).
env_value() {
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$2[[:space:]]*=[[:space:]]*(.*)$/\2/p" "$1" | tail -n 1 |
    sed -E "s/^['\"]//; s/['\"][[:space:]]*$//"
}

if [ -n "$reset" ]; then
  [ -n "$envfile" ] || refuse "--reset needs --env-file"
  [ -f "$envfile" ] || refuse "env file not found: $envfile"
  [ -n "$pattern" ] || refuse "--reset needs --db-pattern"
  url=$(env_value "$envfile" "$dbvar")
  [ -n "$url" ] || refuse "$dbvar is not set in $envfile"
  printf '%s' "$url" | grep -Eq -- "$pattern" || refuse "$dbvar does not match the disposable pattern"
  case $url in
    *://*) host=$(printf '%s' "$url" | sed -E 's#^[A-Za-z0-9+.-]+://([^@/]*@)?(\[[^]]*\]|[^:/?]*).*#\2#') ;;
    *) host=localhost ;;   # file paths and sqlite-style URLs have no network host
  esac
  if [ "$remote" = no ]; then
    case $host in
      localhost|127.0.0.1|"[::1]"|"") ;;
      *) refuse "$dbvar host '$host' is not local; pass --allow-remote to override" ;;
    esac
  fi
fi

with_env() {   # wrap a command so it loads the env file first, when one was given
  if [ -n "$envfile" ]; then
    printf 'set -a; . %s; set +a; %s' "$(printf '%q' "$envfile")" "$1"
  else
    printf '%s' "$1"
  fi
}
run_once() {   # $1 run number; prints pass, fail or could-not-run
  if [ -n "$reset" ]; then
    bash "$here/run-gate.sh" "exit-pair-$1-reset" "$limit" -- "$(with_env "$reset")" >/dev/null
    [ $? -eq 0 ] || { echo could-not-run; return; }
  fi
  bash "$here/run-gate.sh" "exit-pair-$1-prove" "$limit" -- "$(with_env "$prove")" >/dev/null
  case $? in 0) echo pass ;; 3) echo could-not-run ;; *) echo fail ;; esac
}
report() { echo "EXIT-PAIR: $1 (runs: $2; logs: $REVIEW_WS/logs/exit-pair-*)"; }

r1=$(run_once 1); r2=$(run_once 2)
case "$r1 $r2" in *could-not-run*) report could-not-run "$r1 $r2"; exit 3 ;; esac
if [ "$r1" = "$r2" ]; then
  if [ "$r1" = pass ]; then report pass "$r1 $r2"; exit 0; fi
  report fail "$r1 $r2"; exit 1
fi
# Same commit, different results: one more pair before calling it flaky.
r3=$(run_once 3); r4=$(run_once 4)
runs="$r1 $r2 $r3 $r4"
case "$r3 $r4" in *could-not-run*) report could-not-run "$runs"; exit 3 ;; esac
if [ "$r3" = pass ] && [ "$r4" = pass ]; then report "pass, flake seen" "$runs"; exit 0; fi
if [ "$r3" = fail ] && [ "$r4" = fail ]; then report fail "$runs"; exit 1; fi
report flaky "$runs"; exit 5
