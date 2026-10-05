#!/usr/bin/env bash
# Blind A/B setup and pass/fail verdict for the graded (UI) bar.
# Usage: graded-ab.sh prepare <reference-dir> <ours-dir> <out-dir> [<mapping-file>]
#          Copies the two image sets (top-level png/jpg/jpeg/webp only) into <out-dir>/A and <out-dir>/B in random order and records which
#          one is ours in <mapping-file> (default <out-dir>.mapping), outside the folder the scorer reads.
#          Output folders are emptied first, but only if they hold nothing except images and A/B folders.
#        graded-ab.sh first-route <capture-dir> <routes-file> <out-dir>
#          Copies the first route's capture images into <out-dir> (emptied first), renamed to the
#          "home-<desktop|phone>-<light|dark>.png" names of the one-page reference, so both sides pair.
#        graded-ab.sh images <image-dir> <out-dir>
#          Copies an image-dir: reference (top-level images only) into <out-dir> (emptied first).
#        graded-ab.sh verdict <mapping-file> <scores-file>... [--margin M] [--floor F] [--min N]
#          Scores files hold "A <criterion>: <score>" and "B <criterion>: <score>" lines.
#          Every scores file must pass (the second one is the confirming scorer).
#          When ours equals the reference on every criterion it also prints
#          "GRADED: tie on every criterion (scorer <k>)" (a possible copy of the reference).
# Exit: 0 pass / ok, 1 fail, 2 bad input.
set -u
# Copy only the top-level images: anything else (capture.log names the URL) could unblind the scorer.
copy_images() {
  n=0
  for f in "$1"/*.png "$1"/*.jpg "$1"/*.jpeg "$1"/*.webp; do
    [ -f "$f" ] || continue
    cp "$f" "$2/" || return 2
    n=$((n + 1))
  done
  [ "$n" -gt 0 ]
}
# reset_dir <dir>: empty it for new images, refusing when it holds anything a run did not put there.
reset_dir() {
  if [ -e "$1" ]; then
    [ -d "$1" ] || { echo "refusing to replace $1: not a folder" >&2; return 2; }
    for x in "$1"/* "$1"/.[!.]*; do
      [ -e "$x" ] || continue
      case ${x##*/} in A|B|*.png|*.jpg|*.jpeg|*.webp) ;; *) echo "refusing to empty $1: it holds ${x##*/}" >&2; return 2 ;; esac
    done
  fi
  rm -rf "$1" && mkdir -p "$1"
}
cmd=${1:-}; [ $# -gt 0 ] && shift
# Same file-name prefix as capture.sh uses for a route.
slug() { x=$(printf '%s' "$1" | sed -E 's#^/+##; s#/+$##; s#[^A-Za-z0-9._-]+#-#g'); if [ -n "$x" ]; then printf '%s' "$x"; else printf 'home'; fi; }
case $cmd in
  first-route)
    cap=${1:-}; routes=${2:-}; out=${3:-}
    [ -d "$cap" ] && [ -f "$routes" ] && [ -n "$out" ] || { echo "usage: graded-ab.sh first-route <capture-dir> <routes-file> <out-dir>" >&2; exit 2; }
    first=""
    while IFS= read -r r || [ -n "$r" ]; do
      r=${r%%#*}; r=$(printf '%s' "$r" | tr -d '[:space:]'); [ -n "$r" ] || continue
      first=$r; break
    done < "$routes"
    [ -n "$first" ] || { echo "no route in $routes" >&2; exit 2; }
    s=$(slug "$first"); n=0
    reset_dir "$out" || exit 2
    for v in desktop-light desktop-dark phone-light phone-dark; do
      [ -f "$cap/$s-$v.png" ] || continue
      cp "$cap/$s-$v.png" "$out/home-$v.png" || exit 2
      n=$((n + 1))
    done
    [ "$n" -gt 0 ] || { echo "no images for route $first in $cap" >&2; exit 2; } ;;
  images)
    src=${1:-}; out=${2:-}
    [ -d "$src" ] && [ -n "$out" ] || { echo "usage: graded-ab.sh images <image-dir> <out-dir>" >&2; exit 2; }
    reset_dir "$out" || exit 2
    copy_images "$src" "$out" || { echo "no images in $src" >&2; exit 2; } ;;
  prepare)
    ref=${1:-}; ours=${2:-}; out=${3:-}; map=${4:-}
    [ -d "$ref" ] && [ -d "$ours" ] && [ -n "$out" ] || { echo "usage: graded-ab.sh prepare <reference-dir> <ours-dir> <out-dir>" >&2; exit 2; }
    # Strip trailing slashes from out
    while [ -n "${out%/}" ] && [ "$out" != "${out%/}" ]; do
      out="${out%/}"
    done
    side=${GRADED_AB_FORCE:-}
    if [ -z "$side" ]; then if [ $((RANDOM % 2)) -eq 0 ]; then side=A; else side=B; fi; fi
    other=B; [ "$side" = B ] && other=A
    reset_dir "$out" && mkdir -p "$out/A" "$out/B" || exit 2
    copy_images "$ours" "$out/$side" && copy_images "$ref" "$out/$other" || { echo "no images in $ours or $ref" >&2; exit 2; }
    [ -n "$map" ] || map="$out.mapping"
    mkdir -p "$(dirname "$map")" && printf 'ours=%s\n' "$side" > "$map" || exit 2 ;;
  verdict)
    map=${1:-}; [ $# -gt 0 ] && shift
    [ -f "$map" ] || { echo "mapping not found: $map" >&2; exit 2; }
    ours=$(sed -n 's/^ours=//p' "$map")
    case $ours in A|B) ;; *) echo "bad mapping: $map" >&2; exit 2 ;; esac
    margin=0.3; floor=3.5; min=3; files=""
    while [ $# -gt 0 ]; do
      case $1 in
        --margin) [ $# -ge 2 ] || { echo "--margin needs a value" >&2; exit 2; }; margin=$2; shift 2 ;;
        --floor) [ $# -ge 2 ] || { echo "--floor needs a value" >&2; exit 2; }; floor=$2; shift 2 ;;
        --min) [ $# -ge 2 ] || { echo "--min needs a value" >&2; exit 2; }; min=$2; shift 2 ;;
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
        BEGIN { bad = 0 }
        { sub(/\r$/, ""); sub(/[ \t]+$/, "") }
        /^[AB] [^:]+: [0-9]+\.[0-9]+$/ || /^[AB] [^:]+: [0-9]+$/ {
          # Valid score line: A/B, space, criterion, colon, space, number (int or decimal)
          s = substr($0, 1, 1)
          rest = $0
          sub(/^[AB] [^:]+: */, "", rest)
          v = rest + 0
          # Validate score range [0, 5]
          if (v < 0 || v > 5) { bad = 1 }
          c = substr($0, 3); sub(/: .*$/, "", c); if ((s, c) in val) bad = 1; val[s, c] = v; names[c] = 1
          if (!bad) { sum[s] += v; cnt[s]++; if (s == ours && (!seen || v < lo)) { lo = v; seen = 1 } }
          next
        }
        /^[AB] / {
          # Line starts with A or B but does not match valid score format
          bad = 1
          next
        }
        {
          # Other lines (e.g., GAP ...) are ignored
          next
        }
        END {
          if (bad) { print "bad"; exit }
          ref = (ours == "A") ? "B" : "A"
          if (cnt[ours] == 0 || cnt[ref] == 0 || cnt[ours] != cnt[ref]) { print "bad"; exit }
          for (c in names) if (!((ours, c) in val) || !((ref, c) in val)) { print "bad"; exit }
          o = sum[ours] / cnt[ours]; r = sum[ref] / cnt[ref]; why = ""
          if (o < r - margin - 1e-9) why = why sprintf(" below reference by %.2f", r - o)
          if (o < floor - 1e-9) why = why sprintf(" below floor %.2f", floor)
          if (lo < min - 1e-9) why = why sprintf(" a criterion scored %.1f", lo)
          tie = "tie"
          for (c in names) { if (!((ours, c) in val) || !((ref, c) in val)) tie = ""; else { d = val[ours, c] - val[ref, c]; if (d > 1e-9 || d < -1e-9) tie = "" } }
          printf "%s|%.2f|%.2f|%.1f|%s|%s\n", (why == "" ? "pass" : "fail"), o, r, lo, tie, why
        }' "$f")
      [ "$res" != bad ] || { echo "bad scores in $f" >&2; exit 2; }
      verdict=${res%%|*}; rest=${res#*|}
      o=${rest%%|*}; rest=${rest#*|}; r=${rest%%|*}; rest=${rest#*|}; lo=${rest%%|*}; rest=${rest#*|}; tie=${rest%%|*}; why=${rest#*|}
      if [ -n "$why" ]; then
        echo "GRADED: $verdict ours=$o reference=$r lowest=$lo (scorer $k) —$why"
      else
        echo "GRADED: $verdict ours=$o reference=$r lowest=$lo (scorer $k)"
      fi
      [ -z "$tie" ] || echo "GRADED: tie on every criterion (scorer $k)"
      [ "$verdict" = pass ] || status=1
    done <<EOF
$files
EOF
    exit "$status" ;;
  *) echo "usage: graded-ab.sh prepare|first-route|images|verdict ..." >&2; exit 2 ;;
esac
