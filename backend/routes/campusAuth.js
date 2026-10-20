const express = require('express');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');

const router = express.Router();

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

async function sendViaResend(to, link) {
  const key = (process.env.RESEND_API_KEY || '').trim();
  if (!key) return false;
  const from = (process.env.RESEND_FROM || 'popup <noreply@popup.app>').trim();
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to,
      subject: 'Confirm your popup campus email',
      html: confirmHtml(link),
    }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    console.error('Resend email failed:', res.status, text);
    return false;
  }
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

/**
 * After client signup: generate a confirmation link and email it from our backend
 * (Resend — UO often drops Supabase's built-in sender). This never confirms the
 * address itself; the student has to click the link in their inbox.
 */
router.post('/campus-confirm', async (req, res) => {
  try {
    const email = String(req.body?.email || '').trim().toLowerCase();
    if (!email.includes('@') || !email.endsWith('.edu')) {
      return res.status(400).json({ message: 'Use a college .edu email.' });
    }
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    if (rateLimited(email, ip)) {
      return res.status(429).json({ message: 'Too many confirmation requests. Wait a few minutes.' });
    }

    const admin = getSupabaseAdmin();
    const redirectTo = (process.env.AUTH_REDIRECT_URL || 'popup://auth-callback').trim();

    const { data, error } = await admin.auth.admin.generateLink({
      type: 'magiclink',
      email,
      options: { redirectTo },
    });
    if (error) {
      console.error('generateLink error:', error);
      return res.status(400).json({ message: error.message || 'Could not create confirmation link.' });
    }

    const link = data?.properties?.action_link || '';
    let emailed = false;

    if (link) {
      try {
        emailed = await sendViaResend(email, link);
      } catch (sendError) {
        console.error('campus confirm send error:', sendError);
      }
    }

    res.json({
      emailed,
      message: emailed ? 'Confirmation email sent.' : 'Could not send the confirmation email.',
    });
  } catch (error) {
    console.error('campus-confirm error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;
