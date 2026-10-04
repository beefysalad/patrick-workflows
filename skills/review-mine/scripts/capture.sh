#!/usr/bin/env bash
# Screenshot routes of a running site for the graded bar.
# Usage: capture.sh <base-url> <routes-file> <out-dir>
# Routes file: one path per line ("/", "/pricing"); "#" starts a comment.
# Writes <out-dir>/<route>-<desktop|phone>-<light|dark>.png with the Playwright CLI
# (CAPTURE_PW overrides the command, default "npx --yes playwright"); falls back to Chrome
# headless (CHROME_BIN, default the macOS app), which captures light mode only.
# CAPTURE_PW_CHANNEL (default "chrome") is passed as --channel to the Playwright screenshot
# command, so it drives the installed Chrome instead of its bundled headless shell (which can
# be missing); set it to the empty string to omit the flag.
# Before any screenshot, every route's URL is fetched with curl (CAPTURE_CURL overrides the
# command, default "curl"; it must print the HTTP status code): a non-2xx answer, such as a 404
# or 500 page, is "CAPTURE: could-not-run (HTTP <code> at <url>)", never a screenshot.
# Prints "CAPTURE: ok <n>[ (fallback: light only)]" or "CAPTURE: could-not-run <reason>". Exit 0 or 3.
set -u
base=${1:-}; routes=${2:-}; out=${3:-}
[ -n "$base" ] && [ -f "$routes" ] && [ -n "$out" ] || { echo "CAPTURE: could-not-run (usage: capture.sh <base-url> <routes-file> <out-dir>)"; exit 3; }
mkdir -p "$out" || { echo "CAPTURE: could-not-run (cannot create $out)"; exit 3; }
pw=${CAPTURE_PW:-npx --yes playwright}
pw_channel=${CAPTURE_PW_CHANNEL-chrome}
curl_cmd=${CAPTURE_CURL:-curl}
chrome=${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}
base=${base%/}
log="$out/capture.log"
slug() { s=$(printf '%s' "$1" | sed -E 's#^/+##; s#/+$##; s#[^A-Za-z0-9._-]+#-#g'); if [ -n "$s" ]; then printf '%s' "$s"; else printf 'home'; fi; }
shot_pw() {
  if [ -n "$pw_channel" ]; then
    $pw screenshot --channel "$pw_channel" --viewport-size="$1" --full-page --color-scheme="$2" "$3" "$4" >> "$log" 2>&1
  else
    $pw screenshot --viewport-size="$1" --full-page --color-scheme="$2" "$3" "$4" >> "$log" 2>&1
  fi
}
shot_chrome() { "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size="$1" --screenshot="$3" "$2" >> "$log" 2>&1; }

route_url() { if [ "$1" = / ]; then printf '%s' "$base"; else printf '%s' "$base/${1#/}"; fi; }   # "/" is the base itself (a page URL for a route: reference)
clean() { r=${1%%#*}; printf '%s' "$r" | tr -d '[:space:]'; }

# HTTP status of every route first, so an error page is never captured.
while IFS= read -r r || [ -n "$r" ]; do
  r=$(clean "$r"); [ -n "$r" ] || continue
  url=$(route_url "$r")
  code=$($curl_cmd -s -o /dev/null -w '%{http_code}' -L --max-time 10 "$url" 2>/dev/null)
  case $code in
    2[0-9][0-9]) ;;
    *) echo "CAPTURE: could-not-run (HTTP ${code:-none} at $url)"; exit 3 ;;
  esac
done < "$routes"

mode=playwright; n=0; failed=0
while IFS= read -r r || [ -n "$r" ]; do
  r=$(clean "$r"); [ -n "$r" ] || continue
  url=$(route_url "$r")
  s=$(slug "$r")
  for v in "desktop 1440,900" "phone 390,844"; do
    dev=${v%% *}; size=${v#* }
    for scheme in light dark; do
      f="$out/$s-$dev-$scheme.png"
      if [ "$mode" = playwright ]; then
        if shot_pw "$size" "$scheme" "$url" "$f" && [ -s "$f" ]; then n=$((n + 1)); continue; fi
        mode=chrome
      fi
      [ "$scheme" = dark ] && continue   # Chrome headless has no dark-mode switch
      if [ -x "$chrome" ] && shot_chrome "$size" "$url" "$f" && [ -s "$f" ]; then n=$((n + 1)); else failed=1; fi
    done
  done
done < "$routes"

if [ "$failed" -eq 1 ] || [ "$n" -eq 0 ]; then
  echo "CAPTURE: could-not-run (no screenshot tool worked; see $log)"; exit 3
fi
if [ "$mode" = chrome ]; then echo "CAPTURE: ok $n (fallback: light only)"; else echo "CAPTURE: ok $n"; fi
