const fs = require('fs');
const path = require('path');
const { getSupabaseAdmin } = require('./supabaseAdmin');

// Server-rendered closet share page (`/u/:username`). iMessage, WhatsApp and
// Instagram read the Open Graph tags here to draw the link preview, so the
// tags have to be in the HTML the server sends, not added later by script.

const TEMPLATE_PATH = path.join(__dirname, '..', 'public', 'share.html');
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function escapeHtml(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function plural(count, one, many) {
  return `${count} ${count === 1 ? one : many}`;
}

async function loadCloset({ username, id }) {
  let supabase;
  try {
    supabase = getSupabaseAdmin();
  } catch {
    return null;
  }

  let query = supabase
    .from('profiles')
    .select('id, username, shop_name, first_name, avatar_url, privacy, country');
  if (id && UUID_RE.test(id)) {
    query = query.eq('id', id.toLowerCase());
  } else if (username) {
    query = query.ilike('username', username);
  } else {
    return null;
  }
  const { data: profile } = await query.maybeSingle();
  if (!profile) return null;

  const [active, sold, recent, reviews] = await Promise.all([
    supabase.from('products').select('id', { count: 'exact', head: true })
      .eq('user_id', profile.id).eq('is_sold', false),
    supabase.from('products').select('id', { count: 'exact', head: true })
      .eq('user_id', profile.id).eq('is_sold', true),
    supabase.from('products')
      .select('id, images(url, is_primary, sort_order)')
      .eq('user_id', profile.id).eq('is_sold', false)
      .order('created_at', { ascending: false }).limit(4),
    supabase.from('reviews').select('rating').eq('reviewed_id', profile.id).limit(500),
  ]);

  const photos = (recent.data || [])
    .map((p) => {
      const imgs = (p.images || []).slice().sort((a, b) =>
        (b.is_primary - a.is_primary) || (a.sort_order - b.sort_order));
      return imgs[0] && imgs[0].url;
    })
    .filter(Boolean);

  const ratings = (reviews.data || []).map((r) => Number(r.rating)).filter((n) => n > 0);
  const avg = ratings.length ? ratings.reduce((a, b) => a + b, 0) / ratings.length : 0;
  const privacy = profile.privacy || {};

  return {
    school: schoolKey(profile.country),
    id: profile.id,
    username: profile.username,
    shopName: (profile.shop_name || '').trim() || (profile.first_name || '').trim() || profile.username,
    avatarUrl: profile.avatar_url || '',
    listingCount: active.count || 0,
    soldCount: privacy.show_sold_items === false ? null : (sold.count || 0),
    reviewCount: ratings.length,
    reviewAverage: avg,
    photos,
  };
}

// Same mapping as CampusTheme.from(schoolName:) in the app.
function schoolKey(raw) {
  const school = String(raw || '').toLowerCase();
  if (!school || school.includes('popup dev')) return '';
  if (school.includes('oregon state') || school.includes('osu') || school.includes('beaver')) return 'osu';
  return 'uo';
}

function describe(closet) {
  const bits = [plural(closet.listingCount, 'listing', 'listings')];
  if (closet.soldCount != null && closet.soldCount > 0) bits.push(`${closet.soldCount} sold`);
  if (closet.reviewCount > 0) bits.push(`${closet.reviewAverage.toFixed(1)}★`);
  return `${bits.join(' · ')}. Shop @${closet.username}'s closet and meet up on campus.`;
}

async function renderClosetSharePage(req) {
  const template = fs.readFileSync(TEMPLATE_PATH, 'utf8');
  const username = String(req.params.username || '').replace(/^@/, '').slice(0, 64);
  const id = typeof req.query.id === 'string' ? req.query.id : '';

  let closet = null;
  try {
    closet = await loadCloset({ username, id });
  } catch (err) {
    console.warn('closet share lookup failed:', err && err.message);
  }

  const origin = `${req.protocol}://${req.get('host')}`;
  const handle = closet ? closet.username : username;
  const title = closet ? `${closet.shopName} on popup` : (handle ? `@${handle} on popup` : 'Shop on popup');
  const description = closet
    ? describe(closet)
    : 'Shop student closets and meet up on campus with popup.';
  const image = (closet && (closet.photos[0] || closet.avatarUrl)) || `${origin}/logo.png`;
  const pageUrl = `${origin}${req.originalUrl}`;

  const meta = [
    `<title>${escapeHtml(title)}</title>`,
    `<meta name="description" content="${escapeHtml(description)}" />`,
    `<meta property="og:type" content="profile" />`,
    `<meta property="og:site_name" content="popup" />`,
    `<meta property="og:title" content="${escapeHtml(title)}" />`,
    `<meta property="og:description" content="${escapeHtml(description)}" />`,
    `<meta property="og:url" content="${escapeHtml(pageUrl)}" />`,
    `<meta property="og:image" content="${escapeHtml(image)}" />`,
    `<meta name="twitter:card" content="summary_large_image" />`,
    `<meta name="twitter:title" content="${escapeHtml(title)}" />`,
    `<meta name="twitter:description" content="${escapeHtml(description)}" />`,
    `<meta name="twitter:image" content="${escapeHtml(image)}" />`,
  ].join('\n  ');

  const data = closet
    ? {
        id: closet.id,
        username: closet.username,
        shopName: closet.shopName,
        avatarUrl: closet.avatarUrl,
        listingCount: closet.listingCount,
        soldCount: closet.soldCount,
        reviewCount: closet.reviewCount,
        reviewAverage: Number(closet.reviewAverage.toFixed(1)),
        photos: closet.photos,
        school: closet.school,
      }
    : { username: handle, id };

  // `<` is escaped so a shop name can never close the script tag.
  const json = JSON.stringify(data).replace(/</g, '\\u003c');

  return template
    .replace('<!--META-->', meta)
    .replace('/*CLOSET_DATA*/null', json);
}

module.exports = { renderClosetSharePage, escapeHtml };
