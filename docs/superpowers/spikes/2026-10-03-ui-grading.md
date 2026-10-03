# UI grading spike (2026-10-03)

Test page: `<html><body style="background:#3366cc"><h1>Spike</h1></body></html>` served by `python3 -m http.server 8765` from a `mktemp -d` dir (server killed afterwards).

## 1. Playwright CLI screenshot (default command)

Command:
```
npx --yes playwright screenshot --viewport-size=390,844 --full-page --color-scheme=dark http://127.0.0.1:8765/ "$S/pw.png"
```
Output (trimmed):
```
Error: command.parse: Executable doesn't exist at ~/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell
Looks like Playwright was just installed or updated. Please run: npx playwright install
pw exit=1   (about 4s; no pw.png)
```
npx resolved Playwright 1.63.0 (no visible download delay; package already in the npx cache or fetched quickly). That version wants headless-shell build 1243, but the cache only holds 1208 and 1234, so the bundled-browser default fails.

Retry using the installed Google Chrome:
```
npx --yes playwright screenshot --channel chrome --viewport-size=390,844 --full-page --color-scheme=dark http://127.0.0.1:8765/ "$S/pw2.png"
```
Result: exit 0, PNG written (5302 bytes).

Conclusion: the plain command fails on this Mac because of a browser-revision mismatch. `--channel chrome` works.
Consequence: Task 2's DEFAULT command is:
```
npx --yes playwright screenshot --channel chrome --viewport-size=<W>,<H> --full-page --color-scheme=<light|dark> <url> <out.png>
```
It needs Google Chrome installed. FALLBACK if that fails (viewport only, no full-page or color-scheme):
```
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=<W>,<H> --screenshot=<out.png> <url>
``` Do not rely on the cached ms-playwright browsers, and do not run `npx playwright install` implicitly.

## 2. Chrome headless screenshot

Command:
```
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=390,844 --screenshot="$S/chrome.png" http://127.0.0.1:8765/
```
Output (trimmed): `5283 bytes written to file .../chrome.png`, exit 0. `file`: PNG image data, 390 x 844. Stderr has harmless macOS noise (CVDisplayLinkCreateWithCGDisplay, task_policy_set).

Conclusion: works, exact viewport size, but only the viewport (no full-page, no color-scheme flag).
Consequence: use as fallback (Task 2); route stderr to /dev/null and judge success by exit code plus file existence.

## 3. Read-only plugin agent reads a PNG

Command (from repo root):
```
claude -p --model sonnet --plugin-dir "$PWD" --allowedTools "Read(//$S/**)" "Read(//private$S/**)" "Glob" -- "Dispatch patrick-workflows:final-reviewer with this text instead of a review: 'Read the image $S/pw.png and report its dominant background color in one word.' Print its answer." < /dev/null
```
File read: `$S/pw.png`. The plain Playwright run in section 1 never wrote it. It is a byte-for-byte copy (`cp $S/pw2.png $S/pw.png`) of the `--channel chrome` output pw2.png, made so the brief's probe command could be used unchanged.
(`$S` is under `/var/folders/...`; both the `//var` and `//private/var` allow rules were supplied.)

Output (trimmed): `The final-reviewer's answer: **Blue.**` (about 14s). Unrelated MCP auth warnings were also printed.

Conclusion: the read-only final-reviewer agent can read PNGs with only Read and Glob allowed, and it identified the blue background correctly.
Consequence: Task 5's scorer can receive image paths in its dispatch text and read them itself. No plan stop is needed. Permission rules for absolute paths need the double leading slash. On macOS, tmp paths under /var also need the /private/var form allowed, so Task 2 should write screenshots to a path that avoids this or realpath it.
