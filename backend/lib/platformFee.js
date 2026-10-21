// popup's seller service fee. It comes out of the sale before it reaches the
// seller's balance; popup keeps it, and it covers Stripe's processing and payout
// costs. Server-side settings, so the fee can change without an app update.

function envNumber(key, fallback) {
  const raw = (process.env[key] ?? '').toString().trim();
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function feeSettings() {
  return {
    percent: envNumber('PLATFORM_FEE_PERCENT', 10),
    fixedCents: Math.round(envNumber('PLATFORM_FEE_FIXED_CENTS', 0)),
    minCents: Math.round(envNumber('PLATFORM_FEE_MIN_CENTS', 50)),
  };
}

/** Splits a sale into popup's fee and what the seller receives. */
function splitSale(amountCents) {
  const amount = Math.max(0, Math.round(Number(amountCents) || 0));
  const { percent, fixedCents, minCents } = feeSettings();
  let fee = Math.round((amount * percent) / 100) + fixedCents;
  fee = Math.min(Math.max(fee, minCents), amount);
  return { platformFeeCents: fee, sellerNetCents: amount - fee };
}

/** Short label for the app, e.g. "10% (min $0.50)" or "8% + $0.30". */
function feeLabel() {
  const { percent, fixedCents, minCents } = feeSettings();
  let label = `${percent}%`;
  if (fixedCents > 0) label += ` + $${(fixedCents / 100).toFixed(2)}`;
  if (minCents > 0) label += ` (min $${(minCents / 100).toFixed(2)})`;
  return label;
}

module.exports = { splitSale, feeLabel, feeSettings };
