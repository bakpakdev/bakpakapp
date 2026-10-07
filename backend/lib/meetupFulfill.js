const { getSupabaseAdmin } = require('./supabaseAdmin');
const { creditSellerSale } = require('./sellerBalance');

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
 * popup wallet. Square holds the cash on Popup's merchant account until cash out.
 */
async function fulfillMeetupPayment({
  requestRow,
  productId,
  sellerId,
  buyerId,
  paymentId,
}) {
  const supabase = getSupabaseAdmin();
  if (!requestRow || requestRow.status === 'paid') return { alreadyPaid: true };

  const product = await fetchProduct(supabase, productId);
  if (!product) return { skipped: true };

  const total = (requestRow.amount_cents || 0) / 100;
  const resolvedBuyer = buyerId || requestRow.buyer_id || null;

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
    .update({ is_sold: true, updated_at: new Date().toISOString() })
    .eq('id', productId);
  if (soldError) throw soldError;

  const update = {
    status: 'paid',
    updated_at: new Date().toISOString(),
  };
  if (paymentId && !String(paymentId).startsWith('square:pending')) {
    update.square_payment_id = paymentId;
    update.payment_intent_id = paymentId;
  }

  await supabase.from('payment_requests').update(update).eq('id', requestRow.id);

  await creditSellerSale(supabase, sellerId, requestRow.amount_cents);

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
