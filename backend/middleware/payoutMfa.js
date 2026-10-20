const jwt = require('jsonwebtoken');

// How recently the user must have entered an authenticator code. Keep in sync with
// PayoutMFA.freshWindow in ios/BakpakApp/Core/PayoutMFAService.swift.
const MAX_AGE_SECONDS = Number(process.env.PAYOUT_MFA_MAX_AGE_SECONDS || 10 * 60);

function lastTotpAt(claims) {
  const stamps = (Array.isArray(claims?.amr) ? claims.amr : [])
    .filter((entry) => entry?.method === 'totp')
    .map((entry) => Number(entry.timestamp))
    .filter(Number.isFinite);
  return stamps.length ? Math.max(...stamps) : null;
}

/**
 * Payout-method changes and cash outs need an AAL2 Supabase session with a recent
 * authenticator (TOTP) code. Must run after protectSupabase, which has already
 * verified the token with Supabase Auth, so decoding the claims here is safe.
 */
function requirePayoutMfa(req, res, next) {
  const token = (req.headers.authorization || '').split(' ')[1];
  const claims = jwt.decode(token) || {};
  const hasFactor = (req.user?.factors || []).some(
    (factor) => factor.factor_type === 'totp' && factor.status === 'verified'
  );

  if (!hasFactor) {
    return res.status(403).json({
      code: 'MFA_ENROLL_REQUIRED',
      message: 'Turn on two-factor with an authenticator app before changing payouts or cashing out.',
    });
  }

  const verifiedAt = lastTotpAt(claims);
  const fresh = verifiedAt && Date.now() / 1000 - verifiedAt <= MAX_AGE_SECONDS;
  if (claims.aal !== 'aal2' || !fresh) {
    return res.status(403).json({
      code: 'MFA_CODE_REQUIRED',
      message: 'Enter the 6-digit code from your authenticator app to continue.',
    });
  }

  next();
}

module.exports = { requirePayoutMfa };
