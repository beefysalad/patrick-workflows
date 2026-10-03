#!/usr/bin/env bash
# Seed an approved FX-1 ticket on a fixture repo (from setup.sh) for headless BUILD/SHIP smoke runs.
# Usage: seed-ticket.sh <fixture-repo>   → prints the ticket workspace path
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$ROOT/skills/ticket-workspace/scripts"
repo=${1:?usage: seed-ticket.sh <fixture-repo>}
cd "$repo"
git switch -q main
git switch -q -c feat/fx-1-percentage-discounts
ws=$(bash "$T/ticket-ws.sh" init FX-1)
S() { bash "$T/state.sh" "$ws/state.md" "$@"; }

cat > "$ws/ticket.md" <<'EOF'
# FX-1: Percentage discounts
Shoppers can apply a percentage discount and a coupon code at checkout.
Acceptance criteria:
- A discount between 0 and 100 percent reduces the total by that percentage, rounded to the nearest cent.
- A discount outside 0-100 or not a number is rejected with an error.
- Coupon SAVE10 gives 10 percent; unknown codes are rejected with an error.
EOF
cat > "$ws/bar.md" <<'EOF'
AC1: applyDiscount(total, percent) returns total minus round(total*percent/100) for 0 <= percent <= 100.
AC2: applyDiscount throws a RangeError for percent < 0, > 100, or not a finite number.
AC3: applyCoupon(total, 'SAVE10') returns applyDiscount(total, 10); an unknown code throws an Error.
Deferred:
EOF
cat > "$ws/design.md" <<'EOF'
# FX-1 design
Add applyDiscount and applyCoupon to src/cart.js. Coupons come from a fixed table in the same file. Errors are thrown, not returned.
EOF
cat > "$ws/plan.md" <<'EOF'
# FX-1 plan
Tests run with: npm test

### Task 1: applyDiscount
Files: src/cart.js, test/discount.test.js
- Write failing tests in test/discount.test.js: applyDiscount(1000, 10) === 900; applyDiscount(999, 50) === 499 (rounded); applyDiscount(1000, 150), applyDiscount(1000, -1) and applyDiscount(1000, NaN) throw RangeError.
- Implement applyDiscount(total, percent) in src/cart.js and export it.
- Run npm test: only the known red formatPrice test may fail.
- Commit: feat: add applyDiscount

### Task 2: applyCoupon
Files: src/cart.js, test/coupon.test.js
- Write failing tests in test/coupon.test.js: applyCoupon(1000, 'SAVE10') === 900; applyCoupon(1000, 'BOGUS') throws Error.
- Implement applyCoupon(total, code) in src/cart.js with const COUPONS = { SAVE10: 10 } and export it.
- Run npm test: only the known red formatPrice test may fail.
- Commit: feat: add applyCoupon
EOF
printf 'R1 — Coupons from a fixed table (source: user)\nDecision: COUPONS = { SAVE10: 10 } in src/cart.js / Why: no coupon service yet / Cost if wrong: one refactor / Applies to: task 2\n' > "$ws/rulings.md"
printf 'allow: src/**\nallow: test/**\nforbid: src/billing/**\n' > "$ws/scope.txt"

S set ticket FX-1; S set title "Percentage discounts"
S set branch feat/fx-1-percentage-discounts; S set base "$(git rev-parse main)"; S set base_branch main
S set checkout main; S set pr_target main; S set depth standard
S set tasks_total 2; S set tasks_done 0; S set round2 no
S set budget_impl_max 8; S set budget_impl_used 0; S set budget_review_max 10
S set gate.test "npm test"; S set gate_timeout 300; S set exit_pair none
for p in intake designed planned approved; do S phase "$p"; done
printf '%s\n' "$ws"
