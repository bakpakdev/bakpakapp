const express = require('express');
const jwt = require('jsonwebtoken');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');

const router = express.Router();

function publicOrigin() {
  return (
    process.env.PUBLIC_BASE_URL
    || process.env.RENDER_EXTERNAL_URL
    || 'http://localhost:5001'
  ).replace(/\/$/, '').replace(/\/api$/i, '');
}

// Branded confirm links (www.usepopupapp.com) look less like phishing to .edu filters
// than the Render hostname. Stripe and webhooks still use PUBLIC_BASE_URL.
function emailPublicOrigin() {
  return (
    process.env.EMAIL_PUBLIC_BASE_URL
    || publicOrigin()
  ).replace(/\/$/, '').replace(/\/api$/i, '');
}

function jwtSecret() {
  const secret = (process.env.JWT_SECRET || '').trim();
  if (!secret) throw new Error('JWT_SECRET is not set');
  return secret;
}

function signCampusToken(userId, email) {
  return jwt.sign(
    { sub: userId, email, purpose: 'campus-confirm' },
    jwtSecret(),
    { expiresIn: '2h' }
  );
}

function readCampusToken(token) {
  const payload = jwt.verify(String(token || ''), jwtSecret());
  if (payload.purpose !== 'campus-confirm' || !payload.sub || !payload.email) {
    throw new Error('Invalid confirmation token');
  }
  return payload;
}

function confirmHtml(link) {
  return `<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#0A0A0A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#FAFAFA;">
  <div style="max-width:440px;margin:0 auto;padding:40px 28px;">
    <p style="font-size:32px;font-weight:900;letter-spacing:-0.5px;margin:0 0 36px;">popup</p>
    <p style="font-size:22px;font-weight:700;margin:0 0 12px;">Confirm your campus email</p>
    <p style="font-size:15px;line-height:1.55;color:#A3A3A3;margin:0 0 28px;">
      You’re almost in. Tap the button below to open popup, then tap <strong style="color:#FAFAFA;">Confirm email</strong>.
    </p>
    <p style="margin:0 0 16px;">
      <a href="${link}" style="display:inline-block;background:#FAFAFA;color:#0A0A0A;text-decoration:none;font-weight:700;font-size:16px;padding:16px 28px;border-radius:999px;">
        Open popup &amp; confirm
      </a>
    </p>
    <p style="font-size:13px;color:#737373;margin:28px 0 0;">If you didn’t create a popup account, ignore this email.</p>
  </div>
</body>
</html>`;
}

async function sendViaResend(to, link, { subject = 'Confirm your popup campus email', html = confirmHtml(link), text } = {}) {
  const key = (process.env.RESEND_API_KEY || '').trim();
  if (!key) {
    console.error('Resend email failed: RESEND_API_KEY is not set');
    return false;
  }
  const from = (process.env.RESEND_FROM || 'popup <noreply@usepopupapp.com>').trim();
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to,
      subject,
      html,
      text: text || `Confirm your campus email in popup:\n\n${link}\n\nIf you didn’t create a popup account, ignore this email.`,
    }),
  });
  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    console.error('Resend email failed:', res.status, errText);
    return false;
  }
  const payload = await res.json().catch(() => ({}));
  console.log('Resend email queued:', payload.id || 'ok');
  return true;
}

const recent = new Map();
function rateLimited(email, ip) {
  const key = `${email}|${ip}`;
  const now = Date.now();
  const hits = (recent.get(key) || []).filter((t) => now - t < 10 * 60 * 1000);
  if (hits.length >= 6) {
    recent.set(key, hits);
    return true;
  }
  hits.push(now);
  recent.set(key, hits);
  return false;
}

function isEduEmail(email) {
  return email.includes('@') && email.endsWith('.edu');
}

// Demo/dev signup that skips the confirmation email. Needs DEMO_BYPASS_ENABLED=true
// and refuses to run when NODE_ENV=production, so the hosted API can never honor it.
function demoBypassEmail() {
  return (process.env.DEMO_BYPASS_EMAIL || 'demo@popupdev.test').trim().toLowerCase();
}

function isDemoBypass(email) {
  if (process.env.NODE_ENV === 'production') return false;
  if (String(process.env.DEMO_BYPASS_ENABLED || '').trim().toLowerCase() !== 'true') return false;
  return Boolean(email) && email === demoBypassEmail();
}

// App Store review account: one fixed address (APP_REVIEW_EMAIL) that signs up without the
// confirmation email so Apple's reviewers can walk the whole signup flow. Unlike the demo
// bypass this also works in production, but only for that exact address; unset it to turn off.
function isAppReviewBypass(email) {
  const reviewEmail = String(process.env.APP_REVIEW_EMAIL || '').trim().toLowerCase();
  return Boolean(reviewEmail) && email === reviewEmail;
}

// Tells the app whether to offer popup university at signup (App Review mode).
router.get('/review-campus', (req, res) => {
  res.json({ enabled: Boolean(String(process.env.APP_REVIEW_EMAIL || '').trim()) });
});

function confirmLinkFor(userId, email) {
  const token = signCampusToken(userId, email);
  return `${emailPublicOrigin()}/auth/confirm-email.html?campus_token=${encodeURIComponent(token)}`;
}

async function findUserByEmail(admin, email) {
  const base = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  if (base && key) {
    const res = await fetch(
      `${base}/auth/v1/admin/users?email=${encodeURIComponent(email)}`,
      { headers: { Authorization: `Bearer ${key}`, apikey: key } }
    );
    if (res.ok) {
      const body = await res.json();
      const users = Array.isArray(body.users) ? body.users : Array.isArray(body) ? body : [];
      const match = users.find((u) => String(u.email || '').toLowerCase() === email);
      if (match) return match;
    }
  }

  // GoTrue ignores ?email= on some versions and returns one page of everyone,
  // so walk every page rather than stopping at the first 200 users.
  const perPage = 200;
  for (let page = 1; page <= 50; page += 1) {
    const listed = await admin.auth.admin.listUsers({ page, perPage });
    const users = listed.data?.users || [];
    const match = users.find((u) => String(u.email || '').toLowerCase() === email);
    if (match) return match;
    if (users.length < perPage) break;
  }
  return null;
}

function isConfirmed(user) {
  return Boolean(user?.email_confirmed_at || user?.emailConfirmedAt);
}

async function emailConfirmLink(email, userId) {
  const link = confirmLinkFor(userId, email);
  try {
    return await sendViaResend(email, link);
  } catch (sendError) {
    console.error('campus confirm send error:', sendError);
    return false;
  }
}

/**
 * Create the auth user without Supabase sending its own verify URL
 * (iOS Mail prefetches those and burns the token). We email a landing
 * page instead; the app then calls /campus-verify.
 */
router.post('/campus-register', async (req, res) => {
  try {
    const email = String(req.body?.email || '').trim().toLowerCase();
    const password = String(req.body?.password || '');
    const username = String(req.body?.username || '').trim();
    const firstName = String(req.body?.first_name || '').trim();
    const lastName = String(req.body?.last_name || '').trim();
    const school = String(req.body?.school || '').trim();
    const demo = isDemoBypass(email) || isAppReviewBypass(email);

    if (!demo && !isEduEmail(email)) {
      return res.status(400).json({ message: 'Use a college .edu email.' });
    }
    if (password.length < 8) {
      return res.status(400).json({ message: 'Could not start signup. Try again.' });
    }
    if (username.length < 3) {
      return res.status(400).json({ message: 'Username must be at least 3 characters.' });
    }

    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    if (rateLimited(email, ip)) {
      return res.status(429).json({ message: 'Too many confirmation requests. Wait a few minutes.' });
    }

    const admin = getSupabaseAdmin();
    const metadata = {
      username,
      first_name: firstName,
      last_name: lastName,
      school,
    };

    let user;
    const created = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: demo,
      user_metadata: metadata,
    });

    if (created.error) {
      const already =
        /already|registered|exists/i.test(created.error.message || '');
      if (!already) {
        console.error('campus-register createUser:', created.error);
        return res.status(400).json({
          message: created.error.message || 'Could not create account.',
        });
      }
      user = await findUserByEmail(admin, email);
      if (!user) {
        return res.status(400).json({ message: 'Could not create account.' });
      }
      if (isConfirmed(user) && !demo) {
        return res.status(409).json({
          emailed: false,
          message: 'That email already has an account. Sign in instead.',
        });
      }
      const updated = await admin.auth.admin.updateUserById(user.id, {
        password,
        user_metadata: metadata,
        ...(demo ? { email_confirm: true } : {}),
      });
      if (updated.error) {
        console.error('campus-register updateUser:', updated.error);
      } else {
        user = updated.data.user || user;
      }
    } else {
      user = created.data.user;
    }

    if (!user?.id) {
      return res.status(400).json({ message: 'Could not create account.' });
    }

    if (demo) {
      return res.json({ emailed: false, confirmed: true, demo: true, message: 'Demo account ready.' });
    }

    const emailed = await emailConfirmLink(email, user.id);
    res.json({
      emailed,
      message: emailed ? 'Confirmation email sent.' : 'Could not send the confirmation email.',
    });
  } catch (error) {
    console.error('campus-register error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

/**
 * Resend the landing-page link. Never uses Supabase action_link / generateLink
 * — those HTTPS verify URLs are consumed by iOS Mail prefetch on TestFlight.
 */
router.post('/campus-confirm', async (req, res) => {
  try {
    const email = String(req.body?.email || '').trim().toLowerCase();
    if (!isEduEmail(email)) {
      return res.status(400).json({ message: 'Use a college .edu email.' });
    }
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    if (rateLimited(email, ip)) {
      return res.status(429).json({ message: 'Too many confirmation requests. Wait a few minutes.' });
    }

    const admin = getSupabaseAdmin();
    const user = await findUserByEmail(admin, email);
    if (!user?.id) {
      return res.status(400).json({ message: 'Create your account first, then resend the email.' });
    }
    if (isConfirmed(user)) {
      return res.json({
        emailed: false,
        confirmed: true,
        message: 'That email is already confirmed. Sign in instead.',
      });
    }

    const emailed = await emailConfirmLink(email, user.id);
    res.json({
      emailed,
      message: emailed ? 'Confirmation email sent.' : 'Could not send the confirmation email.',
    });
  } catch (error) {
    console.error('campus-confirm error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/campus-verify', async (req, res) => {
  try {
    const token = String(req.body?.token || req.body?.campus_token || '').trim();
    if (!token) {
      return res.status(400).json({ confirmed: false, message: 'Missing confirmation token.' });
    }

    let payload;
    try {
      payload = readCampusToken(token);
    } catch {
      return res.status(400).json({
        confirmed: false,
        message: 'That confirmation link expired. Tap Resend verification email, then open the new one on this phone.',
      });
    }

    const admin = getSupabaseAdmin();
    const email = String(payload.email).toLowerCase();
    const updated = await admin.auth.admin.updateUserById(payload.sub, {
      email_confirm: true,
    });
    if (updated.error) {
      console.error('campus-verify updateUser:', updated.error);
      return res.status(400).json({
        confirmed: false,
        message: updated.error.message || 'Could not confirm that email.',
      });
    }

    res.json({
      confirmed: true,
      email,
      message: 'Email confirmed.',
    });
  } catch (error) {
    console.error('campus-verify error:', error);
    res.status(500).json({ confirmed: false, message: 'Server error', error: error.message });
  }
});

// --- Password reset -------------------------------------------------------
// Same landing-page pattern as campus confirm: the email links to our page, which
// hands a signed token to the app, so iOS Mail prefetch can't burn a Supabase link.

const usedResetTokens = new Map();

function signResetToken(userId, email) {
  return jwt.sign(
    { sub: userId, email, purpose: 'password-reset', jti: `${userId}.${Date.now()}` },
    jwtSecret(),
    { expiresIn: '30m' }
  );
}

function readResetToken(token) {
  const payload = jwt.verify(String(token || ''), jwtSecret());
  if (payload.purpose !== 'password-reset' || !payload.sub || !payload.email || !payload.jti) {
    throw new Error('Invalid reset token');
  }
  return payload;
}

function resetHtml(link) {
  return `<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#0A0A0A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#FAFAFA;">
  <div style="max-width:440px;margin:0 auto;padding:40px 28px;">
    <p style="font-size:32px;font-weight:900;letter-spacing:-0.5px;margin:0 0 36px;">popup</p>
    <p style="font-size:22px;font-weight:700;margin:0 0 12px;">Reset your password</p>
    <p style="font-size:15px;line-height:1.55;color:#A3A3A3;margin:0 0 28px;">
      Open this on the phone with popup, then pick a new password. The link works for 30 minutes.
    </p>
    <p style="margin:0 0 16px;">
      <a href="${link}" style="display:inline-block;background:#FAFAFA;color:#0A0A0A;text-decoration:none;font-weight:700;font-size:16px;padding:16px 28px;border-radius:999px;">
        Reset password
      </a>
    </p>
    <p style="font-size:13px;color:#737373;margin:28px 0 0;">If you didn’t ask to reset your password, ignore this email. Your password stays the same.</p>
  </div>
</body>
</html>`;
}

// Mirrors AuthViewModel.passwordRules in the iOS app.
function passwordMeetsRules(password) {
  return password.length >= 6 && /[a-z]/.test(password) && /[A-Z]/.test(password) && /[0-9]/.test(password);
}

router.post('/password-reset', async (req, res) => {
  // Same answer whether or not the account exists, so this can't be used to probe emails.
  const generic = { emailed: true, message: 'If that email has a popup account, a reset link is on its way.' };
  try {
    const email = String(req.body?.email || '').trim().toLowerCase();
    if (!email.includes('@')) {
      return res.status(400).json({ message: 'Enter the email you signed up with.' });
    }
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    if (rateLimited(`reset:${email}`, ip)) {
      return res.status(429).json({ message: 'Too many reset requests. Wait a few minutes.' });
    }

    const admin = getSupabaseAdmin();
    const user = await findUserByEmail(admin, email);
    if (!user?.id || !isConfirmed(user)) return res.json(generic);

    const token = signResetToken(user.id, email);
    const link = `${publicOrigin()}/auth/reset-password.html?reset_token=${encodeURIComponent(token)}`;
    const sent = await sendViaResend(email, link, { subject: 'Reset your popup password', html: resetHtml(link) })
      .catch((err) => { console.error('password reset send error:', err); return false; });
    if (!sent && process.env.NODE_ENV !== 'production') {
      console.log(`[dev] password reset link for ${email}: ${link}`);
    }
    return res.json(generic);
  } catch (error) {
    console.error('password-reset error:', error);
    return res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/password-reset/complete', async (req, res) => {
  try {
    const token = String(req.body?.token || '').trim();
    const password = String(req.body?.password || '');
    let payload;
    try {
      payload = readResetToken(token);
    } catch {
      return res.status(400).json({ message: 'That reset link expired. Ask for a new one from the sign-in screen.' });
    }
    if (usedResetTokens.has(payload.jti)) {
      return res.status(400).json({ message: 'That reset link was already used. Ask for a new one from the sign-in screen.' });
    }
    if (!passwordMeetsRules(password)) {
      return res.status(400).json({ message: 'Use at least 6 characters with a lowercase letter, an uppercase letter, and a number.' });
    }

    const admin = getSupabaseAdmin();
    const updated = await admin.auth.admin.updateUserById(payload.sub, { password });
    if (updated.error) {
      console.error('password-reset updateUser:', updated.error);
      return res.status(400).json({ message: updated.error.message || 'Could not update the password.' });
    }

    const now = Date.now();
    for (const [jti, at] of usedResetTokens) if (now - at > 60 * 60 * 1000) usedResetTokens.delete(jti);
    usedResetTokens.set(payload.jti, now);
    return res.json({ ok: true, email: String(payload.email).toLowerCase() });
  } catch (error) {
    console.error('password-reset/complete error:', error);
    return res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;
