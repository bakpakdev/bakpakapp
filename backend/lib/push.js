// Apple Push Notification service (APNs) sender + the "who gets alerted for what" rules.
//
// Env (Render): APNS_KEY (contents of the .p8 key, \n allowed), APNS_KEY_ID, APNS_TEAM_ID,
// APNS_BUNDLE_ID (default com.popup.app). Tokens carry their own environment:
// Xcode/Debug builds register as 'sandbox', TestFlight/App Store as 'production'.
const http2 = require('http2');
const jwt = require('jsonwebtoken');
const { getSupabaseAdmin } = require('./supabaseAdmin');

const HOSTS = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};

function apnsConfig() {
  const key = (process.env.APNS_KEY || '').replace(/\\n/g, '\n').trim();
  const keyId = (process.env.APNS_KEY_ID || '').trim();
  const teamId = (process.env.APNS_TEAM_ID || '').trim();
  const bundleId = (process.env.APNS_BUNDLE_ID || 'com.popup.app').trim();
  if (!key || !keyId || !teamId) return null;
  return { key, keyId, teamId, bundleId };
}

function isPushConfigured() {
  return Boolean(apnsConfig());
}

// Apple wants a fresh provider token at most every 20-60 minutes.
let cachedToken = null;
let cachedAt = 0;
function providerToken(cfg) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedAt < 50 * 60) return cachedToken;
  cachedToken = jwt.sign({ iss: cfg.teamId, iat: now }, cfg.key, {
    algorithm: 'ES256',
    header: { alg: 'ES256', kid: cfg.keyId },
  });
  cachedAt = now;
  return cachedToken;
}

const sessions = {};
function sessionFor(environment) {
  const host = HOSTS[environment] || HOSTS.production;
  const existing = sessions[host];
  if (existing && !existing.closed && !existing.destroyed) return existing;
  const session = http2.connect(host);
  session.on('error', () => { delete sessions[host]; });
  session.on('goaway', () => { delete sessions[host]; });
  session.unref();
  sessions[host] = session;
  return session;
}

function sendOne(cfg, device, payload, { collapseId } = {}) {
  return new Promise((resolve) => {
    const headers = {
      ':method': 'POST',
      ':path': `/3/device/${device.token}`,
      authorization: `bearer ${providerToken(cfg)}`,
      'apns-topic': cfg.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
    };
    if (collapseId) headers['apns-collapse-id'] = collapseId.slice(0, 64);
    let req;
    try {
      req = sessionFor(device.environment).request(headers);
    } catch (err) {
      resolve({ ok: false, status: 0, reason: err.message });
      return;
    }
    let status = 0;
    let body = '';
    req.setEncoding('utf8');
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      let reason = '';
      try { reason = JSON.parse(body || '{}').reason || ''; } catch { /* empty */ }
      resolve({ ok: status === 200, status, reason });
    });
    req.on('error', (err) => resolve({ ok: false, status: 0, reason: err.message }));
    req.setTimeout(10000, () => { req.close(); resolve({ ok: false, status: 0, reason: 'timeout' }); });
    req.end(JSON.stringify(payload));
  });
}

async function prefsAllow(supabase, userId, kind) {
  if (!kind) return true;
  const { data } = await supabase.from('profiles').select('notification_prefs').eq('id', userId).maybeSingle();
  const prefs = (data && data.notification_prefs) || {};
  return prefs[kind] !== false;
}

async function isBlocked(supabase, a, b) {
  if (!a || !b) return false;
  const { data } = await supabase
    .from('user_blocks')
    .select('blocker_id')
    .or(`and(blocker_id.eq.${a},blocked_id.eq.${b}),and(blocker_id.eq.${b},blocked_id.eq.${a})`)
    .limit(1);
  return Boolean(data && data.length);
}

/**
 * Alert every device of `userId`. `kind` is the notification_prefs key that can mute it.
 * `fromUserId` skips the alert when either side blocked the other.
 */
async function sendToUser(userId, { title, body, data = {}, kind, fromUserId, threadId, collapseId }) {
  const cfg = apnsConfig();
  if (!cfg || !userId) return { sent: 0, skipped: 'not configured' };
  const supabase = getSupabaseAdmin();
  if (!(await prefsAllow(supabase, userId, kind))) return { sent: 0, skipped: 'muted' };
  if (await isBlocked(supabase, userId, fromUserId)) return { sent: 0, skipped: 'blocked' };

  const { data: devices } = await supabase
    .from('push_devices')
    .select('token, environment')
    .eq('user_id', userId);
  if (!devices || !devices.length) return { sent: 0, skipped: 'no devices' };

  const aps = { alert: { title, body }, sound: 'default' };
  if (threadId) aps['thread-id'] = threadId;
  const payload = { aps, ...data };

  let sent = 0;
  for (const device of devices) {
    const result = await sendOne(cfg, device, payload, { collapseId });
    if (result.ok) {
      sent += 1;
    } else if (result.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(result.reason)) {
      await supabase.from('push_devices').delete().eq('token', device.token);
    } else {
      console.error('APNs send failed:', result.status, result.reason);
    }
  }
  return { sent };
}

// --- Event rules ---------------------------------------------------------------

async function displayName(supabase, userId) {
  const { data } = await supabase
    .from('profiles')
    .select('username, first_name, shop_name')
    .eq('id', userId)
    .maybeSingle();
  if (!data) return 'Someone';
  return (data.shop_name || '').trim() || (data.first_name || '').trim() || data.username || 'Someone';
}

function truncate(text, max = 140) {
  const clean = String(text || '').replace(/\s+/g, ' ').trim();
  return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
}

// Mirrors the iOS message codecs (Core/MeetupMessaging.swift).
function describeMessage(content) {
  const text = String(content || '').trim();
  if (/^(📍 )?Meetup /.test(text)) return null; // meetup rows send their own alerts
  if (text.startsWith('OfferStatus:')) {
    const [decision, amount] = text.slice('OfferStatus:'.length).split('|');
    return { kind: 'offers', body: decision === 'accepted' ? `accepted your ${amount} offer` : `declined your ${amount} offer` };
  }
  if (text.startsWith('Offer:') || text.startsWith('💰 Offer:')) {
    const rest = text.replace(/^💰 Offer:|^Offer:/, '').trim();
    const [amount, , title] = rest.split('|');
    return { kind: 'offers', body: title ? `offered ${amount.trim()} for ${title}` : `sent you a ${amount.trim()} offer` };
  }
  if (text.startsWith('Listing:')) return { kind: 'messages', body: 'shared a listing with you' };
  return { kind: 'messages', body: truncate(text) };
}

async function handleMessage(record) {
  const supabase = getSupabaseAdmin();
  const described = describeMessage(record.content);
  if (!described) return;
  const { data: participants } = await supabase
    .from('conversation_participants')
    .select('user_id')
    .eq('conversation_id', record.conversation_id);
  const name = await displayName(supabase, record.sender_id);
  const recipients = (participants || []).map((p) => p.user_id).filter((id) => id !== record.sender_id);
  for (const userId of recipients) {
    const isPlainMessage = described.kind === 'messages';
    await sendToUser(userId, {
      title: name,
      body: isPlainMessage ? described.body : `${name} ${described.body}`,
      kind: described.kind,
      fromUserId: record.sender_id,
      threadId: `chat-${record.conversation_id}`,
      data: { type: 'message', conversationId: record.conversation_id, otherUserId: record.sender_id },
    });
  }
}

function formatWhen(iso) {
  if (!iso) return '';
  const date = new Date(iso);
  return date.toLocaleString('en-US', {
    weekday: 'short', hour: 'numeric', minute: '2-digit', timeZone: 'America/Los_Angeles',
  });
}

async function handleMeetup(record, oldRecord, actorId) {
  const supabase = getSupabaseAdmin();
  const when = formatWhen(record.scheduled_at);
  const where = record.spot_name || 'campus';
  const data = { type: 'meetup', meetupId: record.id, conversationId: record.conversation_id };
  const proposer = record.proposer_id;
  const recipient = record.recipient_id;

  if (!oldRecord) {
    if (record.status !== 'proposed') return;
    const name = await displayName(supabase, proposer);
    await sendToUser(recipient, {
      title: 'Meetup request',
      body: `${name} wants to meet at ${where}, ${when}`,
      kind: 'meetups', fromUserId: proposer, data, collapseId: `meetup-${record.id}`,
    });
    return;
  }

  // actorId = whoever changed the row (auth.uid() in the trigger); alert the other person.
  const actor = actorId || null;
  const other = actor === proposer ? recipient : actor === recipient ? proposer : null;
  const send = async (title, body) => {
    const targets = other ? [other] : [proposer, recipient];
    for (const userId of targets) {
      await sendToUser(userId, {
        title, body: body(await displayName(supabase, userId === proposer ? recipient : proposer)),
        kind: 'meetups', fromUserId: userId === proposer ? recipient : proposer,
        data, collapseId: `meetup-${record.id}`,
      });
    }
  };

  if (record.status === oldRecord.status) {
    if (record.status === 'proposed' || record.status === 'confirmed') {
      await send('Meetup moved', (name) => `${name} moved your meetup to ${where}, ${when}`);
    }
    return;
  }
  if (record.status === 'confirmed') {
    await send('Meetup confirmed', (name) => `${name} accepted: ${where}, ${when}`);
  } else if (record.status === 'declined') {
    await send('Meetup declined', (name) => `${name} can’t make ${where}, ${when}`);
  } else if (record.status === 'cancelled') {
    await send('Meetup cancelled', (name) => (record.cancel_reason
      ? `${name} cancelled ${where}, ${when}: ${record.cancel_reason}`
      : `${name} cancelled ${where}, ${when}`));
  }
  // completed / expired / no_show: no alert (sales send their own).
}

async function handleFollow(record) {
  const supabase = getSupabaseAdmin();
  const name = await displayName(supabase, record.follower_id);
  await sendToUser(record.following_id, {
    title: 'New follower', body: `${name} followed your closet`,
    kind: 'follows', fromUserId: record.follower_id,
    data: { type: 'follow', userId: record.follower_id },
  });
}

/** Called right after a meetup payment is booked (lib/meetupFulfill.js). */
async function notifySale({ sellerId, buyerId, priceCents, productTitle }) {
  const supabase = getSupabaseAdmin();
  const name = buyerId ? await displayName(supabase, buyerId) : 'The buyer';
  const amount = `$${(priceCents / 100).toFixed(2).replace(/\.00$/, '')}`;
  await sendToUser(sellerId, {
    title: `You got paid ${amount}`,
    body: productTitle ? `${name} paid for ${productTitle}` : `${name} paid at your meetup`,
    kind: 'sales',
    data: { type: 'sale' },
  });
}

module.exports = {
  isPushConfigured,
  sendToUser,
  handleMessage,
  handleMeetup,
  handleFollow,
  notifySale,
  describeMessage,
};
