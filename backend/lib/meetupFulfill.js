const { notifySale } = require('./push');
const { getSupabaseAdmin } = require('./supabaseAdmin');
const { creditSellerSale, recordDirectSale } = require('./sellerBalance');

const MEETUP_ADDRESS = 'Campus meetup';

async function fetchProduct(supabase, productId) {
  const { data, error } = await supabase
    .from('products')
    .select('id, title, price, is_sold, user_id')
    .eq('id', productId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

/**
 * Marks a meetup payment paid, lists the item sold, and books the seller's full
 * listing price. The buyer's service fee on top stays with popup.
 *
 * paidToAccountId is the seller's Express account when the charge was a
 * destination charge: Stripe already moved the price there, so we only record it.
 * Otherwise the charge sat on popup's account and we credit the seller's popup
 * balance, which goes to Stripe once they onboard or cash out.
 *
 * Safe to call more than once for the same payment (the app's confirm call and
 * the Stripe webhook usually both arrive): only the first call claims the row.
 */
async function fulfillMeetupPayment({
  requestRow,
  productId,
  sellerId,
  buyerId,
  paymentId,
  chargedCents = null,
  sessionId = null,
  paidToAccountId = null,
}) {
  const supabase = getSupabaseAdmin();
  if (!requestRow || requestRow.status === 'paid') return { alreadyPaid: true };

  const product = await fetchProduct(supabase, productId);
  if (!product) return { skipped: true };

  // amount_cents = listing price (the seller's share); the buyer paid that plus
  // popup's service fee. chargedCents is what Stripe actually collected.
  const priceCents = requestRow.amount_cents || 0;
  const charged = Number.isFinite(Number(chargedCents)) && chargedCents > 0 ? Number(chargedCents) : priceCents;
  const serviceFeeCents = Math.max(0, charged - priceCents);
  const total = charged / 100;
  const resolvedBuyer = buyerId || requestRow.buyer_id || null;
  const now = new Date().toISOString();

  const claim = {
    status: 'paid',
    platform_fee_cents: serviceFeeCents,
    total_cents: charged,
    updated_at: now,
  };
  if (paymentId && !String(paymentId).includes(':pending')) {
    claim.payment_intent_id = paymentId;
    if (requestRow.provider === 'square') claim.square_payment_id = paymentId;
  }
  const { data: claimed, error: claimError } = await supabase
    .from('payment_requests')
    .update(claim)
    .eq('id', requestRow.id)
    .neq('status', 'paid')
    .select('id')
    .maybeSingle();
  if (claimError) throw claimError;
  if (!claimed) return { alreadyPaid: true };

  // Book the seller first: once the row is claimed nothing retries, and the seller's money matters most.
  if (paidToAccountId) {
    await recordDirectSale(supabase, sellerId, priceCents);
  } else {
    await creditSellerSale(supabase, sellerId, priceCents);
  }

  if (resolvedBuyer) {
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .insert({
        total,
        status: 'processing',
        shipping_address: MEETUP_ADDRESS,
        payment_intent_id: paymentId,
        buyer_id: resolvedBuyer,
        seller_id: sellerId,
      })
      .select('id')
      .single();
    if (orderError) throw orderError;

    const { error: itemError } = await supabase.from('order_items').insert({
      order_id: order.id,
      product_id: productId,
      quantity: 1,
      price: product.price,
    });
    if (itemError) throw itemError;
  }

  const { error: soldError } = await supabase
    .from('products')
    .update({ is_sold: true, updated_at: now })
    .eq('id', productId);
  if (soldError) throw soldError;

  // Mark receive session complete so buyer/seller UIs unlock in realtime.
  const sessionUpdate = { status: 'paid', updated_at: now };
  if (sessionId) {
    await supabase.from('payment_sessions').update(sessionUpdate).eq('id', sessionId);
  } else {
    await supabase
      .from('payment_sessions')
      .update(sessionUpdate)
      .eq('payment_request_id', requestRow.id)
      .eq('status', 'waiting');
  }

  // Existing meetup status only — do not invent delivered/released here.
  const { error: meetupError } = await supabase
    .from('meetups')
    .update({ status: 'completed' })
    .eq('product_id', productId)
    .eq('status', 'confirmed');
  if (meetupError) {
    console.error('Meetup complete error:', meetupError);
  }

  // Best effort: a failed alert must never undo a booked sale.
  notifySale({ sellerId, buyerId: resolvedBuyer, priceCents, productTitle: product.title })
    .catch((err) => console.error('sale push error:', err));

  return { paid: true };
}

module.exports = {
  fulfillMeetupPayment,
  fetchProduct,
};
