#!/usr/bin/env bash
# Build the review-mine fixture: main (with one known red test) and feat/discounts (seeded defects).
# Usage: setup.sh <dest>
set -eu
dest=${1:?usage: setup.sh <dest>}
[ ! -e "$dest" ] || { echo "already exists: $dest" >&2; exit 1; }
mkdir -p "$dest" && cd "$dest"
git init -q -b main
git config user.name "Fixture"
git config user.email "fixture@example.com"
mkdir -p src/billing test e2e scripts

cat > package.json <<'EOF'
{
  "name": "fixture-shop",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "test": "node --test test/*.test.js",
    "e2e": "node --test e2e/*.test.js",
    "db:reset": "node scripts/reset-db.js"
  }
}
EOF
cat > .gitignore <<'EOF'
test.db
node_modules
EOF
cat > .env.test <<'EOF'
DATABASE_URL=file:./test.db
EOF
cat > src/cart.js <<'EOF'
function subtotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}

function formatPrice(cents) {
  return '$' + (cents / 100).toFixed(2);
}

module.exports = { subtotal, formatPrice };
EOF
cat > src/billing/rates.js <<'EOF'
module.exports = { taxRate: 0.08 };
EOF
cat > scripts/reset-db.js <<'EOF'
const fs = require('fs');
const file = process.env.DATABASE_URL.replace('file:', '');
fs.writeFileSync(file, '[]');
EOF
cat > test/cart.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { subtotal, formatPrice } = require('../src/cart');

test('subtotal adds price times quantity', () => {
  assert.strictEqual(subtotal([{ price: 250, qty: 2 }, { price: 100, qty: 1 }]), 600);
});

test('known red: formatPrice uses thousands separators', () => {
  assert.strictEqual(formatPrice(123456), '$1,234.56');
});
EOF
cat > e2e/checkout.e2e.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const { subtotal } = require('../src/cart');

test('checkout starts from an empty order store', () => {
  const file = process.env.DATABASE_URL.replace('file:', '');
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(file, 'utf8')), []);
  assert.strictEqual(subtotal([{ price: 500, qty: 1 }]), 500);
});
EOF
git add -A && git commit -q -m "base: cart and checkout"

git switch -q -c feat/discounts
cat > src/cart.js <<'EOF'
function subtotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}

function formatPrice(cents) {
  return '$' + (cents / 100).toFixed(2);
}

// Seeded behavioral defect: percent above 100 gives a negative total.
function applyDiscount(total, percent) {
  return total - Math.round(total * percent / 100);
}

// Seeded behavioral defect: a malformed code such as "SAVEabc" yields NaN.
function applyCoupon(total, code) {
  const percent = Number(code.replace('SAVE', ''));
  return applyDiscount(total, percent);
}

// Seeded structural defect: duplicate of applyDiscount.
function applyDiscountPercent(total, percent) {
  return total - Math.round(total * percent / 100);
}

// Seeded security-shaped defect: loads a coupon table from a caller-supplied path.
function loadCoupons(path) {
  return require(path);
}

module.exports = { subtotal, formatPrice, applyDiscount, applyCoupon, applyDiscountPercent, loadCoupons };
EOF
cat > test/discount.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { applyDiscount, applyCoupon } = require('../src/cart');

test('applyDiscount takes 10 percent off', () => {
  assert.strictEqual(applyDiscount(1000, 10), 900);
});

test('applyCoupon reads the percent from the code', () => {
  assert.strictEqual(applyCoupon(1000, 'SAVE20'), 800);
});
EOF
# Seeded incidental change and seeded forbidden change.
echo '{ "name": "fixture-shop", "lockfileVersion": 3 }' > package-lock.json
cat > src/billing/rates.js <<'EOF'
module.exports = { taxRate: 0.1 };
EOF
git add -A && git commit -q -m "feat: discounts and coupons"
echo "$dest"
