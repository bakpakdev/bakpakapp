const { getSupabaseAdmin } = require('./supabaseAdmin');

/** Sends through Resend when RESEND_API_KEY is set; returns false (no throw) otherwise. */
async function sendEmail({ to, subject, html }) {
  const key = (process.env.RESEND_API_KEY || '').trim();
  if (!key || !to) return false;
  const from = (process.env.RESEND_FROM || 'popup <noreply@popup.app>').trim();
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to, subject, html }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    console.error('Resend email failed:', res.status, text);
    return false;
  }
  return true;
}

function payoutChangedHtml(headline, detail) {
  return `<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#0A0A0A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#FAFAFA;">
  <div style="max-width:440px;margin:0 auto;padding:40px 28px;">
    <p style="font-size:32px;font-weight:900;letter-spacing:-0.5px;margin:0 0 36px;">popup</p>
    <p style="font-size:22px;font-weight:700;margin:0 0 12px;">${headline}</p>
    <p style="font-size:15px;line-height:1.55;color:#A3A3A3;margin:0 0 28px;">${detail}</p>
    <p style="font-size:13px;color:#737373;margin:28px 0 0;">
      If this wasn’t you, change your password and contact popup support right away.
    </p>
  </div>
</body>
</html>`;
}

const PAYOUT_CHANGE_COPY = {
  connected: {
    subject: 'Your popup payout account was connected',
    headline: 'Payout account connected',
    detail: 'A Square account was just connected to your popup account for cash outs.',
  },
  disconnected: {
    subject: 'Your popup payout account was removed',
    headline: 'Payout account removed',
    detail: 'The Square account used for your popup cash outs was just disconnected.',
  },
};

/** Best-effort security notice; never throws so payout flows aren't blocked by email. */
async function notifyPayoutMethodChanged(userId, kind) {
  try {
    const copy = PAYOUT_CHANGE_COPY[kind];
    if (!copy) return false;
    const { data } = await getSupabaseAdmin().auth.admin.getUserById(userId);
    const to = data?.user?.email;
    return await sendEmail({
      to,
      subject: copy.subject,
      html: payoutChangedHtml(copy.headline, `${copy.detail} (${new Date().toUTCString()})`),
    });
  } catch (err) {
    console.error('Payout change email failed:', err.message);
    return false;
  }
}

module.exports = { sendEmail, notifyPayoutMethodChanged };
