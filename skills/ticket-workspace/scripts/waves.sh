#!/usr/bin/env bash
# Group a plan's tasks into waves that can run in parallel.
# Usage: waves.sh <plan.md>
# A task is "### Task N: ..." with a "**Files:**" list ("- Create|Modify|Test: `path[:lines]`") and a
# "**Depends on:** <numbers or none>" line. In plan order, each task joins the earliest wave after all its
# dependencies whose files are disjoint from every task already in it. A task with no Files list runs
# alone; a task with no Depends line depends on the previous task; a task that shares a file with an
# earlier task always runs in a later wave than it.
# Prints "Wave <k>: <task numbers>" per wave. Exit: 0 ok, 2 bad input.
set -u
plan=${1:-}
[ -f "$plan" ] || { echo "usage: waves.sh <plan.md>" >&2; exit 2; }
awk '
  function flush() { if (cur != "") { if (!hasdep[cur]) dep[cur] = (prev == "" ? "none" : prev); prev = cur } }
  /^### Task [0-9]+/ {
    flush(); match($0, /[0-9]+/); cur = substr($0, RSTART, RLENGTH)
    order[++n] = cur; known[cur] = 1; infiles = 0; next
  }
  cur == "" { next }
  /^\*\*Files:\*\*/ { infiles = 1; next }
  infiles && /^- (Create|Modify|Test): `/ {
    p = $0; sub(/^[^`]*`/, "", p); sub(/`.*$/, "", p); sub(/:[0-9][0-9,-]*$/, "", p)
    files[cur] = files[cur] SUBSEP p; hasfiles[cur] = 1; next
  }
  infiles && !/^[[:space:]]*$/ && !/^- / { infiles = 0 }
  /^\*\*Depends on:\*\*/ {
    d = $0; sub(/^\*\*Depends on:\*\*[[:space:]]*/, "", d); gsub(/[A-Za-z_][A-Za-z0-9_]*/, " ", d); gsub(/[^0-9]+/, " ", d)   # words like sha256 are not task numbers
    dep[cur] = d; hasdep[cur] = 1; next
  }
  END {
    flush()
    if (n == 0) { print "no tasks in plan" > "/dev/stderr"; exit 2 }
    nw = 0
    for (i = 1; i <= n; i++) {
      t = order[i]; min = 1
      k = split(dep[t], ds, " ")
      for (j = 1; j <= k; j++) {
        if (ds[j] == "none" || ds[j] == "") continue
        if (!(ds[j] in known)) { print "task " t " depends on unknown task " ds[j] > "/dev/stderr"; exit 2 }
        if (!(ds[j] in wave)) { print "task " t " depends on later task " ds[j] > "/dev/stderr"; exit 2 }
        if (wave[ds[j]] + 1 > min) min = wave[ds[j]] + 1
      }
      # A file shared with an earlier task is an implicit dependency: keep plan order on that file.
      for (u = 1; u < i; u++) {
        e = order[u]; m = split(files[e], fs, SUBSEP)
        for (q = 1; q <= m; q++) if (fs[q] != "" && index(files[t] SUBSEP, SUBSEP fs[q] SUBSEP)) { if (wave[e] + 1 > min) min = wave[e] + 1; break }
      }
      for (w = min; ; w++) {
        if (w > nw) { nw = w; break }
        if (alone[w]) continue
        if (!hasfiles[t]) { if (members[w] == "") break; continue }
        clash = 0; m = split(wfiles[w], fs, SUBSEP)
        for (q = 1; q <= m; q++) if (fs[q] != "" && index(files[t] SUBSEP, SUBSEP fs[q] SUBSEP)) { clash = 1; break }
        if (!clash) break
      }
      wave[t] = w; members[w] = members[w] (members[w] == "" ? "" : " ") t
      if (!hasfiles[t]) alone[w] = 1; else wfiles[w] = wfiles[w] files[t]
    }
    for (w = 1; w <= nw; w++) print "Wave " w ": " members[w]
  }
' "$plan"
