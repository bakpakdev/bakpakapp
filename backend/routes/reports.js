const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');
const { sendEmail } = require('../lib/email');

const router = express.Router();

// Who gets an email for every new report (App Store guideline 1.2 expects a response within 24h).
function reportsInbox() {
  return (process.env.REPORTS_EMAIL || 'popupapp.support@gmail.com').trim();
}

const recent = new Map();
function rateLimited(userId) {
  const now = Date.now();
  const hits = (recent.get(userId) || []).filter((t) => now - t < 60 * 60 * 1000);
  if (hits.length >= 20) {
    recent.set(userId, hits);
    return true;
  }
  hits.push(now);
  recent.set(userId, hits);
  return false;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function profileLine(admin, userId) {
  if (!userId) return '—';
  const { data } = await admin
    .from('profiles')
    .select('username, first_name, last_name, country')
    .eq('id', userId)
    .maybeSingle();
  const { data: auth } = await admin.auth.admin.getUserById(userId).catch(() => ({ data: null }));
  const name = [data?.first_name, data?.last_name].filter(Boolean).join(' ');
  const parts = [
    data?.username ? `@${data.username}` : null,
    name || null,
    auth?.user?.email || null,
    data?.country || null,
  ].filter(Boolean);
  return `${parts.join(' · ') || 'unknown'} (${userId})`;
}

function reportHtml(rows) {
  const body = rows
    .map(
      ([label, value]) =>
        `<tr><td style="padding:6px 12px 6px 0;color:#737373;vertical-align:top;white-space:nowrap;">${escapeHtml(label)}</td>` +
        `<td style="padding:6px 0;">${escapeHtml(value)}</td></tr>`
    )
    .join('');
  return `<!DOCTYPE html>
<html>
<body style="margin:0;padding:24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#0A0A0A;">
  <p style="font-size:20px;font-weight:700;margin:0 0 16px;">New popup report</p>
  <table style="border-collapse:collapse;font-size:14px;">${body}</table>
  <p style="font-size:13px;color:#737373;margin:20px 0 0;">
    Review it in Supabase → Table editor → user_reports and set its status when handled.
  </p>
</body>
</html>`;
}

/**
 * Emails popup support about a report the signed-in user just filed. The app inserts the
 * report itself (RLS), then calls this with its id; we re-read it with the service role so
 * the email only ever shows what was actually saved.
 */
router.post('/notify', protectSupabase, async (req, res) => {
  try {
    const reportId = String(req.body?.report_id || '').trim();
    if (!reportId) return res.status(400).json({ message: 'Missing report.' });
    if (rateLimited(req.user.id)) return res.status(429).json({ message: 'Too many reports. Try again later.' });

    const admin = getSupabaseAdmin();
    const { data: report, error } = await admin
      .from('user_reports')
      .select('id, reporter_id, reported_id, conversation_id, product_id, reason, details, created_at')
      .eq('id', reportId)
      .eq('reporter_id', req.user.id)
      .maybeSingle();
    if (error) throw error;
    if (!report) return res.status(404).json({ message: 'Report not found.' });

    let listing = '—';
    if (report.product_id) {
      const { data: product } = await admin
        .from('products')
        .select('title, price')
        .eq('id', report.product_id)
        .maybeSingle();
      listing = product
        ? `${product.title} ($${Number(product.price || 0).toFixed(2)}) (${report.product_id})`
        : report.product_id;
    }

    const [reported, reporter] = await Promise.all([
      profileLine(admin, report.reported_id),
      profileLine(admin, report.reporter_id),
    ]);

    const sent = await sendEmail({
      to: reportsInbox(),
      subject: `popup report: ${report.reason}`,
      html: reportHtml([
        ['Reason', report.reason],
        ['Details', report.details || '—'],
        ['Reported', reported],
        ['Listing', listing],
        ['Chat', report.conversation_id || '—'],
        ['Reporter', reporter],
        ['Report ID', report.id],
        ['Filed', new Date(report.created_at).toUTCString()],
      ]),
    });
    if (!sent) console.error('report notify: email not sent for', report.id);

    res.json({ message: sent ? 'Sent.' : 'Saved.' });
  } catch (error) {
    console.error('report notify error:', error);
    res.status(500).json({ message: 'Could not send the report email.' });
  }
});

module.exports = router;
