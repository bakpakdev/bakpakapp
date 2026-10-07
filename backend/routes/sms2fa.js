const crypto = require('crypto');
const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');

const router = express.Router();
const pending = new Map(); // userId -> { via, hash?, expires, phone }
let cachedVerifySid = process.env.TWILIO_VERIFY_SERVICE_SID || null;

function hashCode(code) {
  return crypto.createHash('sha256').update(String(code)).digest('hex');
}

function normalizePhone(raw) {
  const digits = String(raw || '').replace(/[^\d+]/g, '');
  if (digits.startsWith('+') && digits.length >= 11) return digits;
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+${digits}`;
  return null;
}

function twilioCreds() {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  if (!sid || !token) {
    const err = new Error('SMS is not configured on the server.');
    err.status = 503;
    throw err;
  }
  return { sid, token };
}

function twilioAuthHeader() {
  const { sid, token } = twilioCreds();
  return `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`;
}

function parseTwilioBody(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function friendlyTwilioMessage(payload, fallback) {
  const code = payload?.code;
  const raw = String(payload?.message || fallback || 'Twilio rejected the SMS.');
  if (code === 63016 || /predefined SMS templates/i.test(raw)) {
    return 'Twilio trial accounts can’t send custom SMS. Popup will use Twilio Verify instead.';
  }
  if (
    code === 21211 ||
    code === 21408 ||
    code === 21608 ||
    code === 21610 ||
    /unverified/i.test(raw) ||
    /not a valid mobile/i.test(raw)
  ) {
    return 'Twilio trial can only text numbers you’ve verified in the Twilio Console (Phone Numbers → Verified Caller IDs). Add this phone there, then try again.';
  }
  if (code === 20003) return 'Twilio rejected the account credentials.';
  if (code === 60200) return 'That phone number isn’t valid for Twilio Verify.';
  if (code === 60202) return 'Too many attempts. Wait a minute and request a new code.';
  if (code === 60203) return 'Max send attempts reached. Wait a few minutes, then request a new code.';
  return raw;
}

function twilioError(text, status) {
  const payload = parseTwilioBody(text);
  const err = new Error(friendlyTwilioMessage(payload, text || 'Twilio rejected the SMS.'));
  err.status = status >= 500 ? 502 : 400;
  err.twilioCode = payload?.code;
  err.twilioRaw = text;
  return err;
}

async function twilioPost(url, params) {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: twilioAuthHeader(),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(params),
  });
  const text = await res.text();
  if (!res.ok) throw twilioError(text, res.status);
  return parseTwilioBody(text) || {};
}

async function twilioGet(url) {
  const res = await fetch(url, {
    headers: { Authorization: twilioAuthHeader() },
  });
  const text = await res.text();
  if (!res.ok) throw twilioError(text, res.status);
  return parseTwilioBody(text) || {};
}

async function getVerifyServiceSid() {
  if (cachedVerifySid) return cachedVerifySid;
  twilioCreds();
  try {
    const listed = await twilioGet('https://verify.twilio.com/v2/Services?PageSize=20');
    const existing = listed.services?.find((s) => s.sid) || listed.services?.[0];
    if (existing?.sid) {
      cachedVerifySid = existing.sid;
      return cachedVerifySid;
    }
  } catch (err) {
    console.warn('[sms2fa] Could not list Verify services:', err.message);
  }
  const created = await twilioPost('https://verify.twilio.com/v2/Services', {
    FriendlyName: 'Popup',
    CodeLength: '6',
  });
  if (!created.sid) {
    const err = new Error(
      'Create a Verify service in Twilio Console (Identity → Verify → Create new), then add TWILIO_VERIFY_SERVICE_SID to backend/.env.'
    );
    err.status = 502;
    throw err;
  }
  cachedVerifySid = created.sid;
  return cachedVerifySid;
}

async function sendViaVerify(to) {
  const serviceSid = await getVerifyServiceSid();
  await twilioPost(
    `https://verify.twilio.com/v2/Services/${serviceSid}/Verifications`,
    { To: to, Channel: 'sms' }
  );
}

async function checkViaVerify(to, code) {
  const serviceSid = await getVerifyServiceSid();
  const result = await twilioPost(
    `https://verify.twilio.com/v2/Services/${serviceSid}/VerificationCheck`,
    { To: to, Code: code }
  );
  return String(result.status || '').toLowerCase() === 'approved';
}

async function sendViaMessages(to, body) {
  const from = process.env.TWILIO_FROM_NUMBER;
  const params = { To: to, Body: body };
  if (from) params.From = from;
  const { sid } = twilioCreds();
  await twilioPost(
    `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
    params
  );
}

function isTrialTemplateError(err) {
  return err?.twilioCode === 63016 || /predefined SMS templates/i.test(err?.message || '');
}

router.post('/send', protectSupabase, async (req, res) => {
  try {
    const phone = normalizePhone(req.body?.phone);
    if (!phone) {
      return res.status(400).json({ message: 'Enter a valid mobile number.' });
    }

    try {
      await sendViaVerify(phone);
      pending.set(req.user.id, {
        via: 'verify',
        expires: Date.now() + 10 * 60 * 1000,
        phone,
      });
      return res.json({ message: 'Code sent.', phone });
    } catch (verifyErr) {
      if (verifyErr.status === 503) throw verifyErr;
      console.warn('[sms2fa] Verify send failed, trying Messages:', verifyErr.message);

      const code = String(crypto.randomInt(100000, 999999));
      try {
        await sendViaMessages(phone, `popup code: ${code}. It expires in 10 minutes.`);
        pending.set(req.user.id, {
          via: 'local',
          hash: hashCode(code),
          expires: Date.now() + 10 * 60 * 1000,
          phone,
        });
        return res.json({ message: 'Code sent.', phone });
      } catch (smsErr) {
        if (smsErr.status === 503 && process.env.NODE_ENV !== 'production') {
          console.log(`[sms2fa] Twilio not configured. Preview code for ${phone}: ${code}`);
          pending.set(req.user.id, {
            via: 'local',
            hash: hashCode(code),
            expires: Date.now() + 10 * 60 * 1000,
            phone,
          });
          return res.json({
            message: 'Code generated. SMS is not configured, so enter the preview code in the app.',
            phone,
            previewCode: code,
          });
        }
        if (isTrialTemplateError(smsErr)) {
          throw verifyErr.twilioCode ? verifyErr : smsErr;
        }
        throw smsErr;
      }
    }
  } catch (err) {
    res.status(err.status || 500).json({ message: err.message || 'Could not send SMS.' });
  }
});

router.post('/verify', protectSupabase, async (req, res) => {
  try {
    const entry = pending.get(req.user.id);
    const code = String(req.body?.code || '').trim();
    if (!entry || Date.now() > entry.expires) {
      return res.status(400).json({ message: 'Code expired. Send a new one.' });
    }
    if (entry.via === 'verify') {
      const ok = await checkViaVerify(entry.phone, code);
      if (!ok) {
        return res.status(400).json({ message: 'That code doesn’t match.' });
      }
    } else if (entry.hash !== hashCode(code)) {
      return res.status(400).json({ message: 'That code doesn’t match.' });
    }
    pending.delete(req.user.id);
    res.json({ message: 'Verified.', phone: entry.phone });
  } catch (err) {
    res.status(err.status || 500).json({ message: err.message || 'Could not verify the code.' });
  }
});

module.exports = router;
