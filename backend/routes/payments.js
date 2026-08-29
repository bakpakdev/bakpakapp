const crypto = require('crypto');
const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');
const { fulfillMeetupPayment, fetchProduct } = require('../lib/meetupFulfill');
const square = require('../lib/square');

const router = express.Router();
const ACTIVE_STATUSES = ['awaiting_payment'];

function requireSquarePayments(_req, res, next) {
  if (!square.canTakePayments()) {
    return res.status(503).json({
      message: 'Square payments are not configured. Add SQUARE_APPLICATION_ID, SQUARE_ACCESS_TOKEN, and SQUARE_LOCATION_ID.',
    });
  }
  next();
}

async function cancelOpenRequestsForProduct(supabase, productId) {
  const { data: openRows, error } = await supabase
    .from('payment_requests')
    .select('id')
    .eq('product_id', productId)
    .in('status', ACTIVE_STATUSES);
  if (error) throw error;
  if (openRows?.length) {
    await supabase
      .from('payment_requests')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('product_id', productId)
      .in('status', ACTIVE_STATUSES);
  }
}

router.get('/health', (_req, res) => {
  res.json({
    squareConfigured: square.isSquareConfigured(),
    squareCanTakePayments: square.canTakePayments(),
    squareEnvironment: square.squareEnvironment(),
    supabaseUrl: !!process.env.SUPABASE_URL,
    supabaseServiceRole: !!process.env.SUPABASE_SERVICE_ROLE_KEY,
    publicBaseUrl: process.env.PUBLIC_BASE_URL || null,
  });
});

// Seller starts Tap to Pay, or buyer starts Apple Pay checkout.
// Charge lands on Popup's Square account and credits the seller's popup wallet.
router.post('/meetup/request', protectSupabase, requireSquarePayments, async (req, res) => {
  try {
    const { productId } = req.body;
    if (!productId) {
      return res.status(400).json({ message: 'productId is required' });
    }

    const supabase = getSupabaseAdmin();
    const product = await fetchProduct(supabase, productId);
    if (!product) {
      return res.status(404).json({ message: 'Listing not found' });
    }
    if (product.is_sold) {
      return res.status(400).json({ message: 'This item is already sold' });
    }

    const isSeller = product.user_id === req.user.id;
    const amountCents = Math.round(Number(product.price) * 100);
    if (!Number.isFinite(amountCents) || amountCents < 50) {
      return res.status(400).json({ message: 'Invalid listing price' });
    }

    await cancelOpenRequestsForProduct(supabase, productId);
    const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();
    const pendingId = `square:pending:${crypto.randomUUID()}`;

    const insert = {
      product_id: product.id,
      seller_id: product.user_id,
      payment_intent_id: pendingId,
      amount_cents: amountCents,
      status: 'awaiting_payment',
      expires_at: expiresAt,
      provider: 'square',
    };
    if (!isSeller) {
      insert.buyer_id = req.user.id;
    }

    const { data: requestRow, error: insertError } = await supabase
      .from('payment_requests')
      .insert(insert)
      .select('id, status, amount_cents, expires_at, created_at')
      .single();
    if (insertError) throw insertError;

    if (isSeller) {
      return res.status(201).json({
        paymentRequest: requestRow,
        productTitle: product.title,
        amount: product.price,
        amountCents,
        provider: 'square',
        mode: 'tap_to_pay',
        accessToken: square.platformAccessToken(),
        locationId: square.platformLocationId(),
        applicationId: process.env.SQUARE_APPLICATION_ID,
        environment: square.squareEnvironment(),
      });
    }

    res.status(201).json({
      paymentRequest: requestRow,
      productTitle: product.title,
      amount: product.price,
      amountCents,
      provider: 'square',
      mode: 'apple_pay',
      locationId: square.platformLocationId(),
      applicationId: process.env.SQUARE_APPLICATION_ID,
      environment: square.squareEnvironment(),
    });
  } catch (error) {
    console.error('Create meetup payment request error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.get('/meetup/active/:productId', protectSupabase, async (req, res) => {
  try {
    const { productId } = req.params;
    const supabase = getSupabaseAdmin();
    const product = await fetchProduct(supabase, productId);
    if (!product) {
      return res.status(404).json({ message: 'Listing not found' });
    }

    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, seller_id, buyer_id, status, amount_cents, expires_at, created_at, provider')
      .eq('product_id', productId)
      .eq('status', 'awaiting_payment')
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    if (!requestRow) {
      return res.json({ active: false });
    }

    const isSeller = req.user.id === requestRow.seller_id;
    res.json({
      active: true,
      paymentRequestId: requestRow.id,
      status: requestRow.status,
      amountCents: requestRow.amount_cents,
      expiresAt: requestRow.expires_at,
      role: isSeller ? 'seller' : 'buyer',
      canPay: !isSeller && !product.is_sold,
      provider: 'square',
    });
  } catch (error) {
    console.error('Get active meetup payment error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Buyer pays on their phone (Apple Pay / card) via Square nonce.
router.get('/meetup/:requestId/checkout', protectSupabase, requireSquarePayments, async (req, res) => {
  try {
    const { requestId } = req.params;
    const supabase = getSupabaseAdmin();
    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, product_id, seller_id, amount_cents, status, expires_at')
      .eq('id', requestId)
      .maybeSingle();
    if (error) throw error;
    if (!requestRow) {
      return res.status(404).json({ message: 'Payment request not found' });
    }
    if (requestRow.seller_id === req.user.id) {
      return res.status(403).json({ message: 'Seller cannot pay for their own listing' });
    }
    if (requestRow.status !== 'awaiting_payment') {
      return res.status(400).json({ message: 'This payment request is no longer active' });
    }
    if (new Date(requestRow.expires_at) <= new Date()) {
      return res.status(400).json({ message: 'This payment request expired' });
    }

    const product = await fetchProduct(supabase, requestRow.product_id);
    if (!product || product.is_sold) {
      return res.status(400).json({ message: 'This item is no longer available' });
    }

    await supabase
      .from('payment_requests')
      .update({ buyer_id: req.user.id, updated_at: new Date().toISOString() })
      .eq('id', requestRow.id);

    res.json({
      paymentRequestId: requestRow.id,
      applicationId: process.env.SQUARE_APPLICATION_ID,
      locationId: square.platformLocationId(),
      amountCents: requestRow.amount_cents,
      productTitle: product.title,
      merchantDisplayName: 'popup',
      countryCode: 'US',
      currencyCode: 'USD',
    });
  } catch (error) {
    console.error('Meetup checkout error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/meetup/:requestId/cancel', protectSupabase, async (req, res) => {
  try {
    const { requestId } = req.params;
    const supabase = getSupabaseAdmin();
    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, seller_id, status')
      .eq('id', requestId)
      .maybeSingle();
    if (error) throw error;
    if (!requestRow) {
      return res.status(404).json({ message: 'Payment request not found' });
    }
    if (requestRow.seller_id !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }
    if (requestRow.status !== 'awaiting_payment') {
      return res.status(400).json({ message: 'Payment request is not open' });
    }

    await supabase
      .from('payment_requests')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('id', requestId);
    res.json({ message: 'Payment request cancelled' });
  } catch (error) {
    console.error('Meetup cancel error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/meetup/:requestId/confirm', protectSupabase, requireSquarePayments, async (req, res) => {
  try {
    const { requestId } = req.params;
    const nonce = req.body?.nonce || req.body?.sourceId;
    const squarePaymentId = req.body?.squarePaymentId;
    const supabase = getSupabaseAdmin();

    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, product_id, seller_id, buyer_id, square_payment_id, status, provider, amount_cents')
      .eq('id', requestId)
      .maybeSingle();
    if (error) throw error;
    if (!requestRow) {
      return res.status(404).json({ message: 'Payment request not found' });
    }

    const isSeller = requestRow.seller_id === req.user.id;
    const isBuyer = requestRow.buyer_id && requestRow.buyer_id === req.user.id;
    if (requestRow.buyer_id && !isSeller && !isBuyer) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    let payment;
    if (nonce) {
      if (isSeller) {
        return res.status(403).json({ message: 'Seller cannot pay for their own listing' });
      }
      payment = await square.createPlatformPayment({
        sourceId: nonce,
        amountCents: requestRow.amount_cents,
        referenceId: requestRow.id,
        note: 'popup meetup',
        idempotencyKey: `${requestRow.id}:nonce`,
      });
    } else {
      const paymentId = squarePaymentId || requestRow.square_payment_id;
      if (!paymentId) {
        return res.status(409).json({ message: 'Payment is not complete yet' });
      }
      payment = await square.retrievePlatformPayment(paymentId);
    }

    if (payment.status !== 'COMPLETED') {
      return res.status(409).json({
        message: 'Payment is not complete yet',
        status: payment.status,
      });
    }

    await fulfillMeetupPayment({
      requestRow,
      productId: requestRow.product_id,
      sellerId: requestRow.seller_id,
      buyerId: isBuyer || nonce ? req.user.id : requestRow.buyer_id,
      paymentId: payment.id,
    });
    res.json({ message: 'Payment confirmed', status: 'paid', provider: 'square' });
  } catch (error) {
    console.error('Meetup confirm error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;
