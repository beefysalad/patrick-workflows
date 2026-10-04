#!/usr/bin/env bash
# Build the graded-bar fixture: a tiny static site with a reference page and a weaker landing page.
# Usage: ui-setup.sh <dest>
set -eu
dest=${1:?usage: ui-setup.sh <dest>}
[ ! -e "$dest" ] || { echo "already exists: $dest" >&2; exit 1; }
mkdir -p "$dest/site" && cd "$dest"
git init -q -b main
git config user.name "Fixture"; git config user.email "fixture@example.com"
cat > server.js <<'EOF'
const http = require('http'), fs = require('fs'), path = require('path');
http.createServer((req, res) => {
  const p = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  const f = path.join(__dirname, 'site', path.normalize(p).replace(/^(\.\.[\/\\])+/, ''));
  fs.readFile(f, (err, data) => { if (err) { res.statusCode = 404; return res.end('not found'); } res.setHeader('Content-Type', 'text/html'); res.end(data); });
}).listen(process.env.PORT, '127.0.0.1');
EOF
cat > site/reference.html <<'EOF'
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
body{margin:0;font-family:Georgia,serif;background:#f6f3ee;color:#1d2a35}
header{display:flex;justify-content:space-between;align-items:center;padding:20px 32px}
.hero{padding:72px 32px;max-width:720px}.hero h1{font-size:48px;line-height:1.1;margin:0 0 16px}
.cta{display:inline-block;background:#1d6b5f;color:#fff;padding:14px 22px;border-radius:6px;text-decoration:none}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;padding:0 32px 64px}
.card{background:#fff;padding:20px;border-radius:8px}
@media (max-width:600px){.hero h1{font-size:32px}.grid{grid-template-columns:1fr}}
@media (prefers-color-scheme:dark){body{background:#151b21;color:#e8e4dc}.card{background:#1f2730}}
</style></head><body><header><b>Fieldnote</b><a class="cta" href="#">Start free</a></header>
<section class="hero"><h1>Notes that keep up with your field work</h1><p>Capture, tag and share observations offline.</p><a class="cta" href="#">Start free</a></section>
<section class="grid"><div class="card"><h3>Offline first</h3><p>Works without signal.</p></div><div class="card"><h3>Photo tags</h3><p>Tag what you see.</p></div><div class="card"><h3>Team sync</h3><p>Share when back online.</p></div></section></body></html>
EOF
printf '<!doctype html><html><body><h1>Fieldnote</h1><p>Coming soon.</p></body></html>\n' > site/index.html
printf 'dev: PORT=$PORT node server.js\nroutes: routes.txt\nreference: route:/reference.html\nrubric: rubric.md\nmargin: 0.3\nfloor: 3.5\nmin: 3\n' > graded.md
printf '/\n' > routes.txt
cat > rubric.md <<'EOF'
# Landing page rubric
- Layout fidelity: 1 = no recognisable structure; 3 = header, hero and features present but misaligned; 5 = clear header, hero and feature sections, aligned on one grid with even spacing.
- Visual hierarchy: 1 = everything the same weight; 3 = headline stands out, call to action does not; 5 = headline, call to action and features read in order at a glance.
- Responsiveness: 1 = broken or overflowing on phone; 3 = usable on phone but cramped; 5 = designed for phone, single column, readable.
- Dark mode: 1 = unreadable or unchanged; 3 = readable but harsh; 5 = deliberate dark palette with good contrast.
EOF
git add -A && git commit -q -m "base: site skeleton"
git switch -q -c feat/landing
cat > site/index.html <<'EOF'
<!doctype html><html><head><style>body{font-family:Arial;margin:40px} .cta{background:blue;color:white;padding:4px}</style></head>
<body><h1>Fieldnote</h1><p>Notes that keep up with your field work.</p><a class="cta" href="#">Start free</a>
<h3>Offline first</h3><h3>Photo tags</h3><h3>Team sync</h3></body></html>
EOF
git add -A && git commit -q -m "feat: first landing page attempt"
echo "$dest"
