const { getSupabaseAdmin } = require('./supabaseAdmin');
const { creditSellerSale } = require('./sellerBalance');
const { splitSale } = require('./platformFee');

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
 * Marks a meetup payment paid, lists the item sold, and credits the seller's
 * popup balance, minus popup's service fee. The money sits in popup's Stripe balance until the seller cashes
 * out, which transfers it to their Stripe Express account.
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
  sessionId = null,
}) {
  const supabase = getSupabaseAdmin();
  if (!requestRow || requestRow.status === 'paid') return { alreadyPaid: true };

  const product = await fetchProduct(supabase, productId);
  if (!product) return { skipped: true };

  const total = (requestRow.amount_cents || 0) / 100;
  const resolvedBuyer = buyerId || requestRow.buyer_id || null;
  const now = new Date().toISOString();

  // The seller is credited the sale minus popup's service fee.
  const { platformFeeCents, sellerNetCents } = splitSale(requestRow.amount_cents);
  const claim = {
    status: 'paid',
    amount_cents: requestRow.amount_cents,
    platform_fee_cents: platformFeeCents,
    seller_net_cents: sellerNetCents,
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

  // Credit first: once the row is claimed nothing retries, and the seller's money matters most.
  await creditSellerSale(supabase, sellerId, sellerNetCents);

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

  return { paid: true };
}

module.exports = {
  fulfillMeetupPayment,
  fetchProduct,
};
