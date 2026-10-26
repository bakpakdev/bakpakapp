const express = require('express');
const crypto = require('crypto');
const push = require('../lib/push');

const router = express.Router();

function secretMatches(given) {
  const expected = (process.env.PUSH_WEBHOOK_SECRET || '').trim();
  if (!expected || !given) return false;
  const a = Buffer.from(String(given));
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Called by the Supabase triggers in supabase/migrate_push_notifications.sql.
router.post('/event', async (req, res) => {
  if (!secretMatches(req.get('x-push-secret'))) {
    return res.status(401).json({ message: 'Unauthorized' });
  }
  const { type, record, old_record: oldRecord, actor_id: actorId } = req.body || {};
  // Answer right away; Supabase's pg_net doesn't need to wait on Apple.
  res.json({ ok: true });
  try {
    if (type === 'message') await push.handleMessage(record);
    else if (type === 'meetup') await push.handleMeetup(record, oldRecord, actorId);
    else if (type === 'follow') await push.handleFollow(record);
  } catch (error) {
    console.error('push event error:', type, error);
  }
});

router.get('/health', (_req, res) => {
  res.json({
    apnsConfigured: push.isPushConfigured(),
    webhookSecretSet: Boolean((process.env.PUSH_WEBHOOK_SECRET || '').trim()),
  });
});

module.exports = router;
