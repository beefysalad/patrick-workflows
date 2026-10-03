#!/usr/bin/env bash
# Blind A/B setup and pass/fail verdict for the graded (UI) bar.
# Usage: graded-ab.sh prepare <reference-dir> <ours-dir> <out-dir>
#          Copies the two image sets into <out-dir>/A and <out-dir>/B in random order and records which
#          one is ours in <out-dir>.mapping, outside the folder the scorer reads.
#        graded-ab.sh verdict <mapping-file> <scores-file>... [--margin M] [--floor F] [--min N]
#          Scores files hold "A <criterion>: <score>" and "B <criterion>: <score>" lines.
#          Every scores file must pass (the second one is the confirming scorer).
# Exit: 0 pass / ok, 1 fail, 2 bad input.
set -u
cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
  prepare)
    ref=${1:-}; ours=${2:-}; out=${3:-}
    [ -d "$ref" ] && [ -d "$ours" ] && [ -n "$out" ] || { echo "usage: graded-ab.sh prepare <reference-dir> <ours-dir> <out-dir>" >&2; exit 2; }
    side=${GRADED_AB_FORCE:-}
    if [ -z "$side" ]; then if [ $((RANDOM % 2)) -eq 0 ]; then side=A; else side=B; fi; fi
    other=B; [ "$side" = B ] && other=A
    rm -rf "$out" && mkdir -p "$out/A" "$out/B" || exit 2
    cp -R "$ours/." "$out/$side/" && cp -R "$ref/." "$out/$other/" || exit 2
    printf 'ours=%s\n' "$side" > "$out.mapping" ;;
  verdict)
    map=${1:-}; [ $# -gt 0 ] && shift
    [ -f "$map" ] || { echo "mapping not found: $map" >&2; exit 2; }
    ours=$(sed -n 's/^ours=//p' "$map")
    case $ours in A|B) ;; *) echo "bad mapping: $map" >&2; exit 2 ;; esac
    margin=0.3; floor=3.5; min=3; files=""
    while [ $# -gt 0 ]; do
      case $1 in
        --margin) margin=$2; shift 2 ;;
        --floor) floor=$2; shift 2 ;;
        --min) min=$2; shift 2 ;;
        *) files="$files
$1"; shift ;;
      esac
    done
    [ -n "$files" ] || { echo "no scores files" >&2; exit 2; }
    status=0; k=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -f "$f" ] || { echo "scores not found: $f" >&2; exit 2; }
      k=$((k + 1))
      res=$(awk -v ours="$ours" -v margin="$margin" -v floor="$floor" -v min="$min" '
        /^[AB] [^:]+:[[:space:]]*[0-9.]+[[:space:]]*$/ {
          s = $1; v = $NF + 0; sum[s] += v; cnt[s]++
          if (s == ours && (!seen || v < lo)) { lo = v; seen = 1 }
        }
        END {
          ref = (ours == "A") ? "B" : "A"
          if (cnt[ours] == 0 || cnt[ref] == 0 || cnt[ours] != cnt[ref]) { print "bad"; exit }
          o = sum[ours] / cnt[ours]; r = sum[ref] / cnt[ref]; why = ""
          if (o < r - margin - 1e-9) why = why sprintf(" below reference by %.2f", r - o)
          if (o < floor - 1e-9) why = why sprintf(" below floor %.2f", floor)
          if (lo < min - 1e-9) why = why sprintf(" a criterion scored %.1f", lo)
          printf "%s|%.2f|%.2f|%.1f|%s\n", (why == "" ? "pass" : "fail"), o, r, lo, why
        }' "$f")
      [ "$res" != bad ] || { echo "bad scores in $f" >&2; exit 2; }
      verdict=${res%%|*}; rest=${res#*|}
      o=${rest%%|*}; rest=${rest#*|}; r=${rest%%|*}; rest=${rest#*|}; lo=${rest%%|*}; why=${rest#*|}
      if [ -n "$why" ]; then
        echo "GRADED: $verdict ours=$o reference=$r lowest=$lo (scorer $k) —$why"
      else
        echo "GRADED: $verdict ours=$o reference=$r lowest=$lo (scorer $k)"
      fi
      [ "$verdict" = pass ] || status=1
    done <<EOF
$files
EOF
    exit "$status" ;;
  *) echo "usage: graded-ab.sh prepare|verdict ..." >&2; exit 2 ;;
esac
