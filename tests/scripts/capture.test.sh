#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
CP="$ROOT/skills/review-mine/scripts/capture.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '/\n# comment\n/pricing/plans\n' > "$tmp/routes.txt"
cat > "$tmp/pw-ok.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/pw-args.log"; for last; do :; done; printf 'PNG' > "$last"
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/pw-bad.sh"
cat > "$tmp/chrome-ok.sh" <<'SH'
#!/usr/bin/env bash
for a; do case $a in --screenshot=*) printf 'PNG' > "${a#--screenshot=}" ;; esac; done
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/chrome-bad.sh"
# curl stub: prints the HTTP status; any URL containing "missing" is a 404.
cat > "$tmp/curl-stub.sh" <<'SH'
#!/usr/bin/env bash
for last; do :; done; echo "$last" >> "$(dirname "$0")/curl-urls.log"
case $last in *missing*) printf 404 ;; *) printf 200 ;; esac
SH
chmod +x "$tmp"/*.sh
export CAPTURE_CURL="$tmp/curl-stub.sh"

out=$(CAPTURE_PW="$tmp/pw-ok.sh" bash "$CP" http://127.0.0.1:1234/ "$tmp/routes.txt" "$tmp/shots a"); code=$?
assert_eq 0 "$code" "playwright path exits 0"
assert_eq "CAPTURE: ok 8" "$out" "2 routes x 2 viewports x 2 schemes"
for f in home-desktop-light home-desktop-dark home-phone-light home-phone-dark pricing-plans-desktop-light pricing-plans-phone-dark; do
  assert_file "$tmp/shots a/$f.png" "$f.png"
done
args=$(cat "$tmp/pw-args.log")
assert_contains "$args" "--viewport-size=390,844 --full-page --color-scheme=dark http://127.0.0.1:1234/pricing/plans" "phone dark args"
assert_contains "$args" "--viewport-size=1440,900" "desktop size"
assert_contains "$args" "screenshot --channel chrome --viewport-size=" "default channel is chrome"

mkdir "$tmp/nochan"; cp "$tmp/pw-ok.sh" "$tmp/nochan/pw-ok.sh"
out=$(CAPTURE_PW_CHANNEL= CAPTURE_PW="$tmp/nochan/pw-ok.sh" bash "$CP" http://127.0.0.1:1234/ "$tmp/routes.txt" "$tmp/shots n"); code=$?
assert_eq "CAPTURE: ok 8" "$out" "empty channel still captures"
assert_not_contains "$(cat "$tmp/nochan/pw-args.log")" "--channel" "empty CAPTURE_PW_CHANNEL omits --channel"

out=$(CAPTURE_PW="$tmp/pw-bad.sh" CHROME_BIN="$tmp/chrome-ok.sh" bash "$CP" http://127.0.0.1:1234 "$tmp/routes.txt" "$tmp/shots b"); code=$?
assert_eq 0 "$code" "chrome fallback exits 0"
assert_eq "CAPTURE: ok 4 (fallback: light only)" "$out" "fallback captures light only"
assert_file "$tmp/shots b/home-phone-light.png" "fallback file"

out=$(CAPTURE_PW="$tmp/pw-bad.sh" CHROME_BIN="$tmp/chrome-bad.sh" bash "$CP" http://127.0.0.1:1234 "$tmp/routes.txt" "$tmp/shots c"); code=$?
assert_eq 3 "$code" "nothing works is could-not-run"
assert_contains "$out" "CAPTURE: could-not-run" "reason"
out=$(bash "$CP" http://x "$tmp/missing.txt" "$tmp/d"); assert_eq 3 $? "missing routes file"
# A page base (route: reference) with route "/" must not gain a trailing slash.
mkdir -p "$tmp/pg"; cp "$tmp/pw-ok.sh" "$tmp/pg/"; printf '/\n' > "$tmp/root.txt"
out=$(CAPTURE_PW="$tmp/pg/pw-ok.sh" bash "$CP" http://127.0.0.1:1234/reference.html "$tmp/root.txt" "$tmp/shots p")
assert_eq "CAPTURE: ok 4" "$out" "page base captures"
assert_contains "$(cat "$tmp/pg/pw-args.log")" "--color-scheme=light http://127.0.0.1:1234/reference.html $tmp/shots p/home-desktop-light.png" "route / uses the base URL as-is"
assert_not_contains "$(cat "$tmp/pg/pw-args.log")" "reference.html/" "no trailing slash on the page URL"
# HTTP status is checked per route before any screenshot: a non-2xx page is could-not-run.
mkdir -p "$tmp/st"; cp "$tmp/pw-ok.sh" "$tmp/st/"; printf '/\n/missing\n' > "$tmp/st-routes.txt"
out=$(CAPTURE_PW="$tmp/st/pw-ok.sh" bash "$CP" http://127.0.0.1:1234 "$tmp/st-routes.txt" "$tmp/shots s"); code=$?
assert_eq 3 "$code" "404 route exits 3"
assert_eq "CAPTURE: could-not-run (HTTP 404 at http://127.0.0.1:1234/missing)" "$out" "404 is could-not-run with code and URL"
assert_contains "$(cat "$tmp/curl-urls.log")" "http://127.0.0.1:1234/missing" "curl asked for the route URL"
out=$(CAPTURE_PW="$tmp/st/pw-ok.sh" bash "$CP" http://127.0.0.1:1234/missing.html "$tmp/root.txt" "$tmp/shots s2"); code=$?
assert_eq 3 "$code" "404 page base (route: reference) exits 3"
assert_not_contains "$(ls "$tmp/shots s2")" ".png" "no screenshot of an error page"
# Cleanup round: stale images are cleared, colliding route names are refused.
mkdir -p "$tmp/stale"; printf 'OLD' > "$tmp/stale/old-desktop-light.png"; mkdir -p "$tmp/st"; cp "$tmp/pw-ok.sh" "$tmp/st/"
CAPTURE_PW="$tmp/st/pw-ok.sh" bash "$CP" http://127.0.0.1:1234 "$tmp/root.txt" "$tmp/stale" >/dev/null
[ -e "$tmp/stale/old-desktop-light.png" ] && _ko "stale png kept" || _ok
printf '/a/b\n/a-b\n' > "$tmp/clash.txt"; mkdir -p "$tmp/cl"; cp "$tmp/pw-ok.sh" "$tmp/cl/"
out=$(CAPTURE_PW="$tmp/cl/pw-ok.sh" bash "$CP" http://127.0.0.1:1234 "$tmp/clash.txt" "$tmp/shots cl"); code=$?
assert_eq 3 "$code" "colliding route names are could-not-run"
assert_contains "$out" "same file name" "collision reason"
finish
