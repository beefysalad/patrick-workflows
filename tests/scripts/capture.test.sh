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
chmod +x "$tmp"/*.sh

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
finish
