const fs = require('fs');
const path = require('path');
const { getSupabaseAdmin } = require('./supabaseAdmin');
const { escapeHtml } = require('./closetSharePage');

// Server-rendered listing share page (`/l/:id`). This is where a story link
// from Instagram or Snapchat lands. With popup installed, the universal link
// (usepopupapp.com/l/…) opens the app before this page loads; otherwise the
// page shows the item, tries the app once, then sends the viewer to the App Store.

const TEMPLATE_PATH = path.join(__dirname, '..', 'public', 'listing.html');
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const APP_STORE_URL = 'https://apps.apple.com/us/app/popup-campus-thrift/id6819176326';
const PUBLIC_ORIGIN = 'https://www.usepopupapp.com';

// Same mapping as CampusTheme.from(schoolName:) in the app.
function schoolKey(raw) {
  const school = String(raw || '').toLowerCase();
  if (!school || school.includes('popup dev')) return '';
  if (school.includes('oregon state') || school.includes('osu') || school.includes('beaver')) return 'osu';
  return 'uo';
}

function money(value) {
  const n = Number(value || 0);
  return Number.isInteger(n) ? `$${n}` : `$${n.toFixed(2)}`;
}

async function loadListing(id) {
  if (!id || !UUID_RE.test(id)) return null;
  let supabase;
  try {
    supabase = getSupabaseAdmin();
  } catch {
    return null;
  }
  const { data: product } = await supabase
    .from('products')
    .select('id, title, price, original_price, size, condition, brand, is_sold, school, user_id, images(url, is_primary, sort_order)')
    .eq('id', id.toLowerCase())
    .maybeSingle();
  if (!product) return null;

  const { data: seller } = await supabase
    .from('profiles')
    .select('id, username, shop_name, first_name, avatar_url, country')
    .eq('id', product.user_id)
    .maybeSingle();

  const photos = (product.images || [])
    .slice()
    .sort((a, b) => (b.is_primary - a.is_primary) || (a.sort_order - b.sort_order))
    .map((img) => img.url)
    .filter(Boolean);

  return {
    id: product.id,
    title: product.title,
    price: money(product.price),
    originalPrice: product.original_price && product.original_price > product.price + 0.009
      ? money(product.original_price) : null,
    size: product.size || '',
    condition: product.condition || '',
    brand: product.brand || '',
    sold: product.is_sold === true,
    photos: photos.slice(0, 4),
    school: schoolKey((seller && seller.country) || product.school),
    seller: seller
      ? {
          id: seller.id,
          username: seller.username,
          shopName: (seller.shop_name || '').trim() || (seller.first_name || '').trim() || seller.username,
          avatarUrl: seller.avatar_url || '',
        }
      : null,
  };
}

async function renderListingSharePage(req) {
  const template = fs.readFileSync(TEMPLATE_PATH, 'utf8');
  const id = String(req.params.id || '').slice(0, 64);

  let listing = null;
  try {
    listing = await loadListing(id);
  } catch (err) {
    console.warn('listing share lookup failed:', err && err.message);
  }

  const title = listing ? `${listing.title} · ${listing.price} on popup` : 'This listing is on popup';
  const bits = listing ? [listing.size && `Size ${listing.size}`, listing.condition].filter(Boolean) : [];
  const description = listing
    ? `${bits.length ? bits.join(' · ') + '. ' : ''}${listing.seller ? `From @${listing.seller.username}'s closet. ` : ''}Get popup to buy it and meet up on campus.`
    : 'Shop student closets and meet up on campus with popup.';
  const image = (listing && listing.photos[0]) || `${PUBLIC_ORIGIN}/logo.png`;
  const pageUrl = `${PUBLIC_ORIGIN}/l/${encodeURIComponent(id)}`;

  const meta = [
    `<title>${escapeHtml(title)}</title>`,
    `<meta name="description" content="${escapeHtml(description)}" />`,
    `<meta name="apple-itunes-app" content="app-id=6819176326, app-argument=popup://listing/${escapeHtml(encodeURIComponent(id))}" />`,
    `<meta property="og:type" content="product" />`,
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

  const data = listing
    ? { ...listing, appStoreUrl: APP_STORE_URL, origin: PUBLIC_ORIGIN }
    : { id, appStoreUrl: APP_STORE_URL, origin: PUBLIC_ORIGIN };

  // `<` is escaped so a title can never close the script tag.
  const json = JSON.stringify(data).replace(/</g, '\\u003c');

  return template
    .replace('<!--META-->', meta)
    .replace('/*LISTING_DATA*/null', json);
}

module.exports = { renderListingSharePage, loadListing };
