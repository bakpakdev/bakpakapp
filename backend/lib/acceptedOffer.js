// Price the buyer and seller agreed on in chat. Offers and answers are chat
// messages (see OfferMessageCodec in the iOS app):
//   offer:    "Offer: $12.00|productId|title|price|imageURL"
//   decision: "OfferStatus:accepted|$12.00"
// A newer offer on the same listing replaces the older one, so only the latest
// offer for the listing counts, and only if the other person accepted it.

const OFFER_PREFIXES = ['💰 Offer:', 'Offer:'];
const DECISION_PREFIX = 'OfferStatus:';

function toCents(value) {
  const n = Number(String(value || '').replace(/[$,\s]/g, ''));
  return Number.isFinite(n) ? Math.round(n * 100) : null;
}

function parseOffer(content) {
  const text = String(content || '').trim();
  if (text.startsWith(DECISION_PREFIX)) return null;
  const prefix = OFFER_PREFIXES.find((p) => text.startsWith(p));
  if (!prefix) return null;
  const parts = text.slice(prefix.length).trim().split('|');
  return { cents: toCents(parts[0]), productId: (parts[1] || '').trim().toLowerCase() || null };
}

function parseDecision(content) {
  const text = String(content || '').trim();
  if (!text.startsWith(DECISION_PREFIX)) return null;
  const [decision, amount] = text.slice(DECISION_PREFIX.length).split('|');
  if (decision !== 'accepted' && decision !== 'declined') return null;
  return { decision, cents: toCents(amount) };
}

/** Walks chat messages (oldest first); returns the accepted price in cents for the listing, or null. */
function acceptedOfferCentsFromMessages(messages, productId) {
  const product = String(productId || '').toLowerCase();
  const pending = [];
  const latestByProduct = new Map();
  for (const msg of messages) {
    const offer = parseOffer(msg.content);
    if (offer) {
      const entry = { ...offer, senderId: msg.sender_id, state: 'pending' };
      if (offer.productId) {
        const previous = latestByProduct.get(offer.productId);
        if (previous && previous.state === 'pending') previous.state = 'replaced';
        latestByProduct.set(offer.productId, entry);
      }
      pending.push(entry);
      continue;
    }
    const decision = parseDecision(msg.content);
    if (!decision) continue;
    for (let i = pending.length - 1; i >= 0; i -= 1) {
      const entry = pending[i];
      if (entry.state !== 'pending' || entry.senderId === msg.sender_id || entry.cents !== decision.cents) continue;
      entry.state = decision.decision;
      break;
    }
  }
  const latest = latestByProduct.get(product);
  if (!latest || latest.state !== 'accepted' || !latest.cents || latest.cents < 50) return null;
  return latest.cents;
}

/** Accepted offer price between the seller and this buyer for the listing, or null. */
async function acceptedOfferCents(supabase, { productId, sellerId, buyerId }) {
  if (!productId || !sellerId || !buyerId || sellerId === buyerId) return null;
  const { data: sellerRows, error: sellerError } = await supabase
    .from('conversation_participants')
    .select('conversation_id')
    .eq('user_id', sellerId);
  if (sellerError) throw sellerError;
  const sellerConvos = (sellerRows || []).map((r) => r.conversation_id);
  if (!sellerConvos.length) return null;

  const { data: shared, error: sharedError } = await supabase
    .from('conversation_participants')
    .select('conversation_id')
    .eq('user_id', buyerId)
    .in('conversation_id', sellerConvos);
  if (sharedError) throw sharedError;
  const convoIds = (shared || []).map((r) => r.conversation_id);
  if (!convoIds.length) return null;

  const { data: messages, error: messagesError } = await supabase
    .from('messages')
    .select('content, sender_id, created_at')
    .in('conversation_id', convoIds)
    .order('created_at', { ascending: false })
    .limit(500);
  if (messagesError) throw messagesError;
  return acceptedOfferCentsFromMessages((messages || []).reverse(), productId);
}

/** Every buyer who sent or received an offer on this listing, with their latest offer. */
async function offerBuyersForListing(supabase, { productId, sellerId }) {
  const product = String(productId || '').toLowerCase();
  const { data: sellerRows, error } = await supabase
    .from('conversation_participants')
    .select('conversation_id')
    .eq('user_id', sellerId);
  if (error) throw error;
  const convoIds = (sellerRows || []).map((r) => r.conversation_id);
  if (!convoIds.length) return [];

  const { data: others, error: othersError } = await supabase
    .from('conversation_participants')
    .select('conversation_id, user_id')
    .in('conversation_id', convoIds)
    .neq('user_id', sellerId);
  if (othersError) throw othersError;

  const buyers = [];
  for (const row of others || []) {
    const { data: messages, error: messagesError } = await supabase
      .from('messages')
      .select('content, sender_id, created_at')
      .eq('conversation_id', row.conversation_id)
      .like('content', '%Offer%')
      .order('created_at', { ascending: false })
      .limit(200);
    if (messagesError) throw messagesError;
    const ordered = (messages || []).reverse();
    let latest = null;
    for (const msg of ordered) {
      const offer = parseOffer(msg.content);
      if (offer && offer.productId === product && offer.cents) latest = { cents: offer.cents, at: msg.created_at };
    }
    if (!latest) continue;
    const accepted = acceptedOfferCentsFromMessages(ordered, product);
    buyers.push({
      buyerId: row.user_id,
      conversationId: row.conversation_id,
      offerCents: accepted || latest.cents,
      accepted: Boolean(accepted),
      offeredAt: latest.at,
    });
  }
  return buyers.sort((a, b) => (b.accepted - a.accepted) || String(b.offeredAt).localeCompare(String(a.offeredAt)));
}

module.exports = { acceptedOfferCents, acceptedOfferCentsFromMessages, offerBuyersForListing, parseOffer, parseDecision };
