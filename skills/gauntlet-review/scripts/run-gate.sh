#!/usr/bin/env bash
# Run one gate command with a hard timeout.
# Usage: run-gate.sh <name> <timeout-seconds> -- "<command string>"
# Full output goes to <workspace>/logs/<name>.log (REVIEW_WS, else the pointer from workspace.sh); stdout gets one status line plus the last 30 lines.
# Exit codes: 0 pass, 1 fail, 2 timeout, 3 could-not-run.
set -u
if [ $# -lt 4 ] || [ "$3" != "--" ]; then
  echo "usage: run-gate.sh <name> <timeout-seconds> -- \"<command>\"" >&2
  exit 3
fi
name=$1; limit=$2; cmd=$4
ws=${REVIEW_WS:-}
if [ -z "$ws" ]; then   # fall back to the pointer workspace.sh leaves in the repo's git dir
  ptr=$(git rev-parse --git-path patrick-workflows-review-ws 2>/dev/null) && [ -f "$ptr" ] && ws=$(head -n 1 "$ptr")
  # A linked worktree (an agent worktree in parallel BUILD) has its own git dir: use the main one's pointer.
  if [ -z "$ws" ]; then
    ptr="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/patrick-workflows-review-ws"
    [ -f "$ptr" ] && ws=$(head -n 1 "$ptr")
  fi
fi
[ -n "$ws" ] || { echo "GATE $name: could-not-run (no workspace: REVIEW_WS unset and no pointer file)"; exit 3; }
mkdir -p "$ws/logs" || { echo "GATE $name: could-not-run (cannot create $ws/logs)"; exit 3; }
log="$ws/logs/$name.log"

# Own process group, so a timeout kills the whole tree (npm -> node -> workers).
# stderr is parked while the gate runs, so the shell's "Terminated" job notice stays out of the output.
exec 3>&2 2>/dev/null
perl -e 'setpgrp(0, 0); exec @ARGV' bash -c "$cmd" >"$log" 2>&1 &
pid=$!
ticks=0; max=$((limit * 5)); status=""
while kill -0 "$pid" 2>/dev/null; do
  if [ "$ticks" -ge "$max" ]; then
    kill -TERM -- "-$pid" 2>/dev/null
    sleep 1
    kill -KILL -- "-$pid" 2>/dev/null
    status=timeout
    break
  fi
  sleep 0.2
  ticks=$((ticks + 1))
done
wait "$pid"
code=$?
exec 2>&3 3>&-   # restore stderr
if [ -z "$status" ]; then
  case $code in
    0) status=pass ;;
    126|127) status=could-not-run ;;
    *) status=fail ;;
  esac
fi
line="GATE $name: $status (exit $code, log: $log)"
echo "$line"
printf '%s\n' "$line" > "$ws/logs/$name.status"   # durable record of the result
tail -n 30 "$log"
case $status in
  pass) exit 0 ;;
  fail) exit 1 ;;
  timeout) exit 2 ;;
  *) exit 3 ;;
esac
