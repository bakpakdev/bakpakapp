// popup's service fee. The buyer pays it on top of the listing price, popup keeps
// it, and it covers Stripe's processing and payout costs. The seller always gets
// the full listing price. Server-side settings, so it changes without an app update.

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

/** What the buyer pays for a listing: the price plus popup's service fee. */
function buyerTotal(priceCents) {
  const price = Math.max(0, Math.round(Number(priceCents) || 0));
  const { percent, fixedCents, minCents } = feeSettings();
  const fee = Math.max(Math.round((price * percent) / 100) + fixedCents, minCents);
  return { priceCents: price, serviceFeeCents: fee, totalCents: price + fee };
}

/** Short label for the app, e.g. "10% (min $0.50)" or "8% + $0.30". */
function feeLabel() {
  const { percent, fixedCents, minCents } = feeSettings();
  let label = `${percent}%`;
  if (fixedCents > 0) label += ` + $${(fixedCents / 100).toFixed(2)}`;
  if (minCents > 0) label += ` (min $${(minCents / 100).toFixed(2)})`;
  return label;
}

module.exports = { buyerTotal, feeLabel, feeSettings };
