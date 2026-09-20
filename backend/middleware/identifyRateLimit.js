const WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_WINDOW = Number(process.env.IDENTIFY_RATE_LIMIT_PER_HOUR || 12);
const buckets = new Map();

function prune(now) {
  for (const [key, times] of buckets.entries()) {
    const next = times.filter((t) => now - t < WINDOW_MS);
    if (next.length === 0) buckets.delete(key);
    else buckets.set(key, next);
  }
}

function identifyRateLimit(req, res, next) {
  const now = Date.now();
  if (buckets.size > 500) prune(now);

  const key = (
    req.user?.id ||
    req.headers['x-device-id'] ||
    req.ip ||
    'anon'
  )
    .toString()
    .toLowerCase()
    .slice(0, 120);

  const recent = (buckets.get(key) || []).filter((t) => now - t < WINDOW_MS);
  if (recent.length >= MAX_PER_WINDOW) {
    return res.status(429).json({
      code: 'RATE_LIMITED',
      message: 'Too many scans right now. Try again in a bit.',
    });
  }
  recent.push(now);
  buckets.set(key, recent);
  next();
}

module.exports = { identifyRateLimit };
