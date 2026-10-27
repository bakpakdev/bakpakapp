const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');

const router = express.Router();

const RANGE_DAYS = { week: 7, month: 30, all: null };

/**
 * Campus leaderboard from real, completed sales only (payment_requests.status = 'paid'),
 * so every name on it sold something through popup. Ranked by number of sales in the
 * range; ties go to whoever sold most recently. People who hide their name (Settings →
 * Privacy, profiles.privacy.hide_on_leaderboard) still count but show as anonymous.
 */
async function paidSales(supabase, school, sinceIso) {
  const rows = [];
  const pageSize = 1000;
  for (let from = 0; from < 20000; from += pageSize) {
    let q = supabase
      .from('payment_requests')
      .select('seller_id, updated_at, products!inner(school)')
      .eq('status', 'paid')
      .order('updated_at', { ascending: false })
      .range(from, from + pageSize - 1);
    // Each campus is its own community: only sales of listings on this campus count.
    q = q.eq('products.school', school);
    if (sinceIso) q = q.gte('updated_at', sinceIso);
    const { data, error } = await q;
    if (error) throw error;
    rows.push(...(data || []));
    if (!data || data.length < pageSize) break;
  }
  return rows;
}

function rankSellers(rows) {
  const bySeller = new Map();
  for (const row of rows) {
    const id = String(row.seller_id).toLowerCase();
    const cur = bySeller.get(id) || { sellerId: id, sales: 0, lastSaleAt: row.updated_at };
    cur.sales += 1;
    if (row.updated_at > cur.lastSaleAt) cur.lastSaleAt = row.updated_at;
    bySeller.set(id, cur);
  }
  const list = [...bySeller.values()].sort((a, b) => (b.sales - a.sales) || (b.lastSaleAt > a.lastSaleAt ? 1 : -1));
  // Every seller gets their own spot; on equal sales the more recent seller is ahead.
  list.forEach((entry, i) => {
    entry.rank = i + 1;
  });
  return list;
}

router.get('/', protectSupabase, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const school = String(req.query.school || '').trim().toLowerCase() || null;
    // No campus, no board — never mix campuses together.
    if (!school) return res.json({ range: 'all', school: null, totalSellers: 0, entries: [], me: { rank: null, sales: 0, isMe: true, hidden: false, userId: req.user.id, name: 'You', avatarUrl: null, weeklyChange: null } });
    const range = Object.prototype.hasOwnProperty.call(RANGE_DAYS, req.query.range) ? req.query.range : 'all';
    const days = RANGE_DAYS[range];
    const now = Date.now();
    const since = days ? new Date(now - days * 86400000).toISOString() : null;

    const ranked = rankSellers(await paidSales(supabase, school, since));

    // Movement this week (all-time board vs. a week ago), for "+2 this week".
    const allTime = range === 'all' ? ranked : rankSellers(await paidSales(supabase, school, null));
    const weekAgoIso = new Date(now - 7 * 86400000).toISOString();
    const lastWeek = rankSellers((await paidSales(supabase, school, null)).filter((r) => r.updated_at < weekAgoIso));
    const lastWeekRank = new Map(lastWeek.map((e) => [e.sellerId, e.rank]));

    const ids = ranked.slice(0, 100).map((e) => e.sellerId);
    if (!ids.includes(req.user.id)) ids.push(req.user.id);
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, username, shop_name, avatar_url, privacy')
      .in('id', ids);
    const byId = new Map((profiles || []).map((p) => [String(p.id).toLowerCase(), p]));

    const anonymousNumber = (id) => 1000 + (parseInt(id.replace(/-/g, '').slice(0, 6), 16) % 9000);
    const present = (entry) => {
      const p = byId.get(entry.sellerId) || {};
      const hidden = Boolean(p.privacy && p.privacy.hide_on_leaderboard);
      const isMe = entry.sellerId === req.user.id;
      const allRank = allTime.find((e) => e.sellerId === entry.sellerId)?.rank || null;
      const before = lastWeekRank.get(entry.sellerId);
      return {
        rank: entry.rank,
        sales: entry.sales,
        isMe,
        hidden,
        // Hidden sellers keep their place but not their identity (except to themselves).
        userId: hidden && !isMe ? null : entry.sellerId,
        name: hidden && !isMe ? `Anonymous seller #${anonymousNumber(entry.sellerId)}` : ((p.shop_name || '').trim() || p.username || 'Seller'),
        avatarUrl: hidden && !isMe ? null : (p.avatar_url || null),
        weeklyChange: allRank && before ? before - allRank : (allRank && !before ? null : 0),
      };
    };

    const entries = ranked.slice(0, 100).map(present);
    const mineRanked = ranked.find((e) => e.sellerId === req.user.id);
    const me = mineRanked
      ? present(mineRanked)
      : { rank: null, sales: 0, isMe: true, hidden: false, userId: req.user.id, name: 'You', avatarUrl: null, weeklyChange: null };

    res.json({ range, school, totalSellers: ranked.length, entries, me });
  } catch (error) {
    console.error('leaderboard error:', error);
    res.status(500).json({ message: 'Could not load the leaderboard.', error: error.message });
  }
});

module.exports = router;
