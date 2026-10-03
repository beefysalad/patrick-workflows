#!/usr/bin/env bash
# Dev-server lifecycle for UI captures.
# Usage: dev-server.sh start "<command>" [timeout-seconds]   (the command gets PORT=<port>)
#        dev-server.sh stop | status
# Files: <workspace>/dev-server.pid, dev-server.port, logs/dev-server.log
# Exit: 0 ok, 1 down (status), 3 could-not-run.
set -u
ws=${REVIEW_WS:-}
if [ -z "$ws" ]; then
  ptr=$(git rev-parse --git-path patrick-workflows-review-ws 2>/dev/null) && [ -f "$ptr" ] && ws=$(head -n 1 "$ptr")
fi
[ -n "$ws" ] || { echo "DEV-SERVER: could-not-run (no workspace)"; exit 3; }
mkdir -p "$ws/logs"
pidf="$ws/dev-server.pid"; portf="$ws/dev-server.port"

alive() { [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; }
url() { printf 'http://127.0.0.1:%s' "$(cat "$portf")"; }
stop_server() {
  if [ -f "$pidf" ]; then
    pid=$(cat "$pidf")
    kill -TERM -- "-$pid" 2>/dev/null; sleep 0.5; kill -KILL -- "-$pid" 2>/dev/null
  fi
  rm -f "$pidf" "$portf"
}
free_port() { perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => 0) or exit 1; print $s->sockport'; }

case ${1:-} in
  start)
    cmd=${2:-}; limit=${3:-60}
    [ -n "$cmd" ] || { echo "DEV-SERVER: could-not-run (no command)"; exit 3; }
    if alive && [ -f "$portf" ]; then echo "DEV-SERVER: up $(url)"; exit 0; fi
    stop_server   # clears a stale PID file
    port=$(free_port) || { echo "DEV-SERVER: could-not-run (no free port)"; exit 3; }
    trap 'stop_server; exit 3' INT TERM
    exec 3>&2 2>/dev/null   # keep the shell's job notices out of the output
    PORT=$port perl -e 'setpgrp(0, 0); exec @ARGV' bash -c "$cmd" > "$ws/logs/dev-server.log" 2>&1 3>&- &
    echo $! > "$pidf"; echo "$port" > "$portf"
    exec 2>&3 3>&-
    ticks=0
    while [ "$ticks" -lt $((limit * 5)) ]; do
      if ! alive; then stop_server; echo "DEV-SERVER: could-not-run (exited; see logs/dev-server.log)"; exit 3; fi
      if curl -s -o /dev/null --max-time 1 "$(url)/"; then trap - INT TERM; echo "DEV-SERVER: up $(url)"; exit 0; fi
      sleep 0.2; ticks=$((ticks + 1))
    done
    stop_server 2>/dev/null
    echo "DEV-SERVER: could-not-run (not ready after ${limit}s; see logs/dev-server.log)"; exit 3 ;;
  stop)
    stop_server 2>/dev/null; exit 0 ;;
  status)
    if alive && [ -f "$portf" ]; then echo "DEV-SERVER: up $(url)"; exit 0; fi
    echo "DEV-SERVER: down"; exit 1 ;;
  *)
    echo "usage: dev-server.sh start \"<command>\" [timeout] | stop | status" >&2; exit 3 ;;
esac
