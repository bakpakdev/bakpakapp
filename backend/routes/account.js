const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');

const router = express.Router();

const recent = new Map();
function rateLimited(userId) {
  const now = Date.now();
  const hits = (recent.get(userId) || []).filter((t) => now - t < 10 * 60 * 1000);
  if (hits.length >= 5) {
    recent.set(userId, hits);
    return true;
  }
  hits.push(now);
  recent.set(userId, hits);
  return false;
}

async function verifyPassword(email, password) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return false;
  const res = await fetch(`${url.replace(/\/$/, '')}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, password }),
  });
  return res.ok;
}

async function purge(admin, table, apply) {
  try {
    let query = admin.from(table).delete();
    query = apply(query);
    const { error } = await query;
    if (error) console.error(`delete-account purge ${table}:`, error.message);
  } catch (error) {
    console.error(`delete-account purge ${table}:`, error);
  }
}

async function removeStorageFolder(admin, bucket, folder) {
  const { data, error } = await admin.storage.from(bucket).list(folder, { limit: 1000 });
  if (error) {
    console.error('delete-account storage list:', error.message);
    return;
  }
  const files = (data || []).filter((item) => item?.name && item.id);
  if (!files.length) return;
  const paths = files.map((item) => `${folder}/${item.name}`);
  const { error: removeError } = await admin.storage.from(bucket).remove(paths);
  if (removeError) console.error('delete-account storage remove:', removeError.message);
}

async function purgeUserRows(admin, userId) {
  await purge(admin, 'payment_sessions', (q) => q.eq('seller_id', userId));
  await purge(admin, 'payment_requests', (q) => q.eq('seller_id', userId));
  await purge(admin, 'meetups', (q) => q.or(`proposer_id.eq.${userId},recipient_id.eq.${userId}`));
  await purge(admin, 'messages', (q) => q.eq('sender_id', userId));
  await purge(admin, 'reviews', (q) => q.or(`reviewer_id.eq.${userId},reviewed_id.eq.${userId}`));

  const { data: orders } = await admin
    .from('orders')
    .select('id')
    .or(`buyer_id.eq.${userId},seller_id.eq.${userId}`);
  const orderIds = (orders || []).map((row) => row.id);
  if (orderIds.length) {
    await purge(admin, 'order_items', (q) => q.in('order_id', orderIds));
    await purge(admin, 'orders', (q) => q.in('id', orderIds));
  }

  const { data: products } = await admin.from('products').select('id').eq('user_id', userId);
  const productIds = (products || []).map((row) => row.id);
  if (productIds.length) {
    await purge(admin, 'order_items', (q) => q.in('product_id', productIds));
  }
}

/**
 * Permanently delete the signed-in student after they re-enter their password.
 */
router.post('/delete-account', protectSupabase, async (req, res) => {
  try {
    const password = String(req.body?.password || '');
    if (password.length < 6) {
      return res.status(400).json({ message: 'Enter your password to delete your account.' });
    }
    if (rateLimited(req.user.id)) {
      return res.status(429).json({ message: 'Too many attempts. Wait a few minutes.' });
    }

    const email = String(req.user.email || '').trim().toLowerCase();
    if (!email) {
      return res.status(400).json({ message: 'This account has no email to verify.' });
    }

    const admin = getSupabaseAdmin();
    const verified = await verifyPassword(email, password);
    if (!verified) {
      return res.status(401).json({ message: 'Password is incorrect.' });
    }

    await purgeUserRows(admin, req.user.id);
    await removeStorageFolder(admin, 'product-images', req.user.id);

    const { error: deleteError } = await admin.auth.admin.deleteUser(req.user.id);
    if (deleteError) {
      console.error('delete-account deleteUser:', deleteError);
      return res.status(500).json({
        message: deleteError.message || 'Couldn’t delete account. Try again.',
      });
    }

    res.json({ message: 'Account deleted.' });
  } catch (error) {
    console.error('delete-account error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;
