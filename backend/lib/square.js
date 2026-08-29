const crypto = require('crypto');

const SQUARE_VERSION = '2025-10-16';
const OAUTH_SCOPES = [
  'PAYMENTS_WRITE',
  'PAYMENTS_WRITE_IN_PERSON',
  'MERCHANT_PROFILE_READ',
  'PAYMENTS_READ',
].join(' ');

function isSquareConfigured() {
  return Boolean((process.env.SQUARE_APPLICATION_ID || '').trim());
}

function platformAccessToken() {
  return (process.env.SQUARE_ACCESS_TOKEN || '').trim();
}

function platformLocationId() {
  return (process.env.SQUARE_LOCATION_ID || '').trim();
}

function canTakePayments() {
  return isSquareConfigured() && Boolean(platformAccessToken()) && Boolean(platformLocationId());
}

function canOAuthSellers() {
  return isSquareConfigured() && Boolean((process.env.SQUARE_APPLICATION_SECRET || '').trim());
}

function squareEnvironment() {
  const raw = (process.env.SQUARE_ENVIRONMENT || 'sandbox').toLowerCase();
  return raw === 'production' ? 'production' : 'sandbox';
}

function oauthBaseUrl() {
  return squareEnvironment() === 'production'
    ? 'https://connect.squareup.com'
    : 'https://connect.squareupsandbox.com';
}

function apiBaseUrl() {
  return squareEnvironment() === 'production'
    ? 'https://connect.squareup.com'
    : 'https://connect.squareupsandbox.com';
}

function oauthRedirectUri() {
  if (process.env.SQUARE_OAUTH_REDIRECT_URI) {
    return process.env.SQUARE_OAUTH_REDIRECT_URI.replace(/\/$/, '');
  }
  const base = (process.env.PUBLIC_BASE_URL || 'http://localhost:5001').replace(/\/$/, '');
  return `${base}/api/payments/square/oauth/callback`;
}

function stateSecret() {
  return process.env.SQUARE_APPLICATION_SECRET || process.env.JWT_SECRET || 'popup-square-dev';
}

function signOAuthState(userId) {
  const payload = Buffer.from(JSON.stringify({
    uid: userId,
    n: crypto.randomBytes(12).toString('hex'),
    t: Date.now(),
  })).toString('base64url');
  const sig = crypto.createHmac('sha256', stateSecret()).update(payload).digest('base64url');
  return `${payload}.${sig}`;
}

function parseOAuthState(state) {
  if (!state || typeof state !== 'string' || !state.includes('.')) return null;
  const [payload, sig] = state.split('.');
  const expected = crypto.createHmac('sha256', stateSecret()).update(payload).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (!data?.uid) return null;
    if (Date.now() - Number(data.t || 0) > 15 * 60 * 1000) return null;
    return data;
  } catch {
    return null;
  }
}

async function squareFetch(path, { method = 'GET', accessToken, body, isOAuth = false } = {}) {
  const base = isOAuth ? oauthBaseUrl() : apiBaseUrl();
  const headers = {
    'Content-Type': 'application/json',
    'Square-Version': SQUARE_VERSION,
  };
  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  }
  const response = await fetch(`${base}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let json = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }
  if (!response.ok) {
    const detail = json?.errors?.[0]?.detail || json?.message || text || `Square HTTP ${response.status}`;
    const error = new Error(detail);
    error.status = response.status;
    error.body = json;
    throw error;
  }
  return json;
}

async function obtainToken({ code, refreshToken }) {
  const body = {
    client_id: process.env.SQUARE_APPLICATION_ID,
    client_secret: process.env.SQUARE_APPLICATION_SECRET,
  };
  if (code) {
    body.grant_type = 'authorization_code';
    body.code = code;
    body.redirect_uri = oauthRedirectUri();
  } else {
    body.grant_type = 'refresh_token';
    body.refresh_token = refreshToken;
  }
  return squareFetch('/oauth2/token', { method: 'POST', body, isOAuth: true });
}

async function revokeToken(accessToken) {
  try {
    await squareFetch('/oauth2/revoke', {
      method: 'POST',
      isOAuth: true,
      body: {
        client_id: process.env.SQUARE_APPLICATION_ID,
        client_secret: process.env.SQUARE_APPLICATION_SECRET,
        access_token: accessToken,
      },
    });
  } catch (err) {
    console.warn('Square revoke warning:', err.message);
  }
}

async function listLocations(accessToken) {
  const json = await squareFetch('/v2/locations', { accessToken });
  const locations = Array.isArray(json.locations) ? json.locations : [];
  return locations.filter((loc) => (loc.status || 'ACTIVE') === 'ACTIVE');
}

async function retrievePayment(accessToken, paymentId) {
  const json = await squareFetch(`/v2/payments/${encodeURIComponent(paymentId)}`, { accessToken });
  return json.payment || json;
}

async function retrievePlatformPayment(paymentId) {
  return retrievePayment(platformAccessToken(), paymentId);
}

async function createPlatformPayment({ sourceId, amountCents, referenceId, note, idempotencyKey }) {
  const json = await squareFetch('/v2/payments', {
    method: 'POST',
    accessToken: platformAccessToken(),
    body: {
      idempotency_key: idempotencyKey || crypto.randomUUID(),
      source_id: sourceId,
      autocomplete: true,
      location_id: platformLocationId(),
      amount_money: { amount: amountCents, currency: 'USD' },
      reference_id: referenceId ? String(referenceId).slice(0, 40) : undefined,
      note: note ? String(note).slice(0, 500) : undefined,
    },
  });
  return json.payment || json;
}

function verifyWebhookSignature(rawBody, signatureHeader, notificationUrl) {
  const key = process.env.SQUARE_WEBHOOK_SIGNATURE_KEY;
  if (!key) return true;
  if (!signatureHeader) return false;
  const hmac = crypto
    .createHmac('sha256', key)
    .update(notificationUrl + rawBody)
    .digest('base64');
  const a = Buffer.from(hmac);
  const b = Buffer.from(signatureHeader);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function authorizeUrl(userId) {
  const params = new URLSearchParams({
    client_id: process.env.SQUARE_APPLICATION_ID,
    scope: OAUTH_SCOPES,
    session: squareEnvironment() === 'production' ? 'false' : 'true',
    state: signOAuthState(userId),
    redirect_uri: oauthRedirectUri(),
  });
  return `${oauthBaseUrl()}/oauth2/authorize?${params.toString()}`;
}

function expiresAtFromToken(tokenResponse) {
  if (tokenResponse.expires_at) return new Date(tokenResponse.expires_at);
  return new Date(Date.now() + 29 * 24 * 60 * 60 * 1000);
}

module.exports = {
  isSquareConfigured,
  canTakePayments,
  canOAuthSellers,
  platformAccessToken,
  platformLocationId,
  squareEnvironment,
  oauthRedirectUri,
  authorizeUrl,
  parseOAuthState,
  obtainToken,
  revokeToken,
  listLocations,
  retrievePayment,
  retrievePlatformPayment,
  createPlatformPayment,
  verifyWebhookSignature,
  expiresAtFromToken,
};
