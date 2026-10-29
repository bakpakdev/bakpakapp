const crypto = require('crypto');
const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');
const { fulfillMeetupPayment, fetchProduct } = require('../lib/meetupFulfill');
const stripe = require('../lib/stripe');
const { buyerTotal, feeLabel } = require('../lib/platformFee');
const { acceptedOfferCents, offerBuyersForListing } = require('../lib/acceptedOffer');

const router = express.Router();
const ACTIVE_STATUSES = ['awaiting_payment'];
const SESSION_TTL_MS = 20 * 60 * 1000;

function requireStripePayments(_req, res, next) {
  if (!stripe.isStripeConfigured()) {
    return res.status(503).json({
      message: 'Stripe payments are not configured. Add STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY.',
    });
  }
  next();
}

// PaymentIntent states where the buyer can still (re)try paying.
const REUSABLE_INTENT_STATUSES = ['requires_payment_method', 'requires_confirmation', 'requires_action'];

/** Best effort: stop a buyer's half-open checkout from charging after the seller closed Receive. */
async function cancelIntentIfOpen(paymentIntentId) {
  if (!String(paymentIntentId || '').startsWith('pi_') || !stripe.isStripeConfigured()) return;
  try {
    const intent = await stripe.getStripe().paymentIntents.retrieve(paymentIntentId);
    if (REUSABLE_INTENT_STATUSES.includes(intent.status)) {
      await stripe.getStripe().paymentIntents.cancel(paymentIntentId);
    }
  } catch (err) {
    console.warn('Could not cancel PaymentIntent', paymentIntentId, err.message);
  }
}

async function cancelOpenRequestsForProduct(supabase, productId) {
  const { data: openRows, error } = await supabase
    .from('payment_requests')
    .select('id, payment_intent_id')
    .eq('product_id', productId)
    .in('status', ACTIVE_STATUSES);
  if (error) throw error;
  if (openRows?.length) {
    await Promise.all(openRows.map((row) => cancelIntentIfOpen(row.payment_intent_id)));
    await supabase
      .from('payment_requests')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('product_id', productId)
      .in('status', ACTIVE_STATUSES);
  }
}

async function expireStaleSessions(supabase) {
  const now = new Date().toISOString();
  await supabase
    .from('payment_sessions')
    .update({ status: 'expired', updated_at: now })
    .eq('status', 'waiting')
    .lt('expires_at', now);
}

async function cancelWaitingSessionsForProduct(supabase, productId) {
  const now = new Date().toISOString();
  await expireStaleSessions(supabase);
  await supabase
    .from('payment_sessions')
    .update({ status: 'cancelled', updated_at: now })
    .eq('product_id', productId)
    .eq('status', 'waiting');
}

async function fetchWaitingSession(supabase, productId) {
  await expireStaleSessions(supabase);
  const { data, error } = await supabase
    .from('payment_sessions')
    .select(SESSION_COLUMNS)
    .eq('product_id', productId)
    .eq('status', 'waiting')
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data;
}

const SESSION_COLUMNS =
  'id, product_id, meetup_id, payment_request_id, seller_id, buyer_id, amount_cents, service_fee_cents, total_cents, product_title, status, expires_at, created_at';

/** Latest paid session for a listing, so a poll after payment sees "paid" instead of "no session". */
async function fetchPaidSession(supabase, productId, userId) {
  const { data, error } = await supabase
    .from('payment_sessions')
    .select(SESSION_COLUMNS)
    .eq('product_id', productId)
    .eq('status', 'paid')
    .or(`seller_id.eq.${userId},buyer_id.eq.${userId}`)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data;
}

function isUniqueViolation(error) {
  return error?.code === '23505';
}

function serializeSession(session) {
  if (!session) return null;
  return {
    id: session.id,
    product_id: session.product_id,
    meetup_id: session.meetup_id,
    payment_request_id: session.payment_request_id,
    seller_id: session.seller_id,
    buyer_id: session.buyer_id,
    amount_cents: session.amount_cents,
    service_fee_cents: session.service_fee_cents ?? null,
    total_cents: session.total_cents ?? null,
    product_title: session.product_title,
    status: session.status,
    expires_at: session.expires_at,
    created_at: session.created_at,
  };
}

router.get('/health', (_req, res) => {
  const missing = ['STRIPE_SECRET_KEY', 'STRIPE_PUBLISHABLE_KEY', 'STRIPE_WEBHOOK_SECRET', 'PUBLIC_BASE_URL']
    .filter((key) => !(process.env[key] || '').trim());

  res.json({
    stripeConfigured: stripe.isStripeConfigured(),
    stripeEnvironment: stripe.stripeEnvironment(),
    supabaseUrl: !!process.env.SUPABASE_URL,
    supabaseServiceRole: !!process.env.SUPABASE_SERVICE_ROLE_KEY,
    publicBaseUrl: process.env.PUBLIC_BASE_URL || null,
    missingStripeEnv: missing,
  });
});

/**
 * Seller opens Receive: creates a waiting payment_session + payment_request.
 * Buyer Apple Pay is gated on this session being active.
 */
/** Seller: people who made or got an offer on this listing in chat, so Receive can pick the buyer. */
router.get('/meetup/offers/:productId', protectSupabase, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const product = await fetchProduct(supabase, req.params.productId);
    if (!product) return res.status(404).json({ message: 'Listing not found' });
    if (product.user_id !== req.user.id) {
      return res.status(403).json({ message: 'Only the seller can see offers' });
    }
    const buyers = await offerBuyersForListing(supabase, { productId: product.id, sellerId: product.user_id });
    const ids = buyers.map((b) => b.buyerId);
    let profiles = [];
    if (ids.length) {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, username, first_name, last_name, avatar_url')
        .in('id', ids);
      if (error) throw error;
      profiles = data || [];
    }
    const byId = new Map(profiles.map((p) => [p.id, p]));
    res.json({
      offers: buyers.map((b) => {
        const p = byId.get(b.buyerId) || {};
        return {
          buyerId: b.buyerId,
          conversationId: b.conversationId,
          username: p.username || '',
          name: [p.first_name, p.last_name].filter(Boolean).join(' '),
          avatarUrl: p.avatar_url || null,
          amountCents: b.offerCents,
          accepted: b.accepted,
        };
      }),
      listingCents: Math.round(Number(product.price) * 100),
    });
  } catch (error) {
    console.error('List listing offers error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/meetup/receive', protectSupabase, requireStripePayments, async (req, res) => {
  try {
    const { productId, meetupId, buyerId } = req.body || {};
    if (!productId) {
      return res.status(400).json({ message: 'productId is required' });
    }

    const supabase = getSupabaseAdmin();
    const product = await fetchProduct(supabase, productId);
    if (!product) {
      return res.status(404).json({ message: 'Listing not found' });
    }
    if (product.user_id !== req.user.id) {
      return res.status(403).json({ message: 'Only the seller can open Receive' });
    }
    if (product.is_sold) {
      return res.status(400).json({ message: 'This item is already sold' });
    }

    const listingCents = Math.round(Number(product.price) * 100);
    if (!Number.isFinite(listingCents) || listingCents < 50) {
      return res.status(400).json({ message: 'Invalid listing price' });
    }

    let resolvedBuyerId = typeof buyerId === 'string' && buyerId.trim() ? buyerId.trim() : null;
    if (meetupId) {
      const { data: meetup, error: meetupError } = await supabase
        .from('meetups')
        .select('id, product_id, proposer_id, recipient_id, status')
        .eq('id', meetupId)
        .maybeSingle();
      if (meetupError) throw meetupError;
      if (!meetup || meetup.product_id !== product.id) {
        return res.status(400).json({ message: 'Meetup does not match this listing' });
      }
      const participants = [meetup.proposer_id, meetup.recipient_id];
      if (!participants.includes(req.user.id)) {
        return res.status(403).json({ message: 'Not a participant on this meetup' });
      }
      resolvedBuyerId = participants.find((id) => id && id !== req.user.id) || resolvedBuyerId;
    }

    // An offer the seller and this buyer agreed on in chat sets the price; otherwise the listing price.
    const offerCents = await acceptedOfferCents(supabase, {
      productId: product.id,
      sellerId: product.user_id,
      buyerId: resolvedBuyerId,
    });
    const amountCents = offerCents || listingCents;

    await cancelWaitingSessionsForProduct(supabase, productId);
    await cancelOpenRequestsForProduct(supabase, productId);

    const expiresAt = new Date(Date.now() + SESSION_TTL_MS).toISOString();
    const pendingId = `stripe:pending:${crypto.randomUUID()}`;
    const { serviceFeeCents, totalCents } = buyerTotal(amountCents);

    const { data: requestRow, error: insertError } = await supabase
      .from('payment_requests')
      .insert({
        product_id: product.id,
        seller_id: product.user_id,
        buyer_id: resolvedBuyerId,
        payment_intent_id: pendingId,
        amount_cents: amountCents,
        platform_fee_cents: serviceFeeCents,
        total_cents: totalCents,
        status: 'awaiting_payment',
        expires_at: expiresAt,
        provider: 'stripe',
      })
      .select('id, status, amount_cents, expires_at, created_at')
      .single();
    if (insertError) {
      // Two Receive taps (or two of the seller's devices) at once: the other call
      // already opened the session, so hand that one back instead of a 500.
      if (isUniqueViolation(insertError)) {
        const existing = await fetchWaitingSession(supabase, productId);
        if (existing) return res.status(200).json(receivePayload(existing, product));
      }
      throw insertError;
    }

    const { data: session, error: sessionError } = await supabase
      .from('payment_sessions')
      .insert({
        product_id: product.id,
        meetup_id: meetupId || null,
        payment_request_id: requestRow.id,
        seller_id: product.user_id,
        buyer_id: resolvedBuyerId,
        amount_cents: amountCents,
        service_fee_cents: serviceFeeCents,
        total_cents: totalCents,
        product_title: product.title || '',
        status: 'waiting',
        expires_at: expiresAt,
      })
      .select(
        'id, product_id, meetup_id, payment_request_id, seller_id, buyer_id, amount_cents, service_fee_cents, total_cents, product_title, status, expires_at, created_at'
      )
      .single();
    if (sessionError) {
      await supabase
        .from('payment_requests')
        .update({ status: 'cancelled', updated_at: new Date().toISOString() })
        .eq('id', requestRow.id);
      if (isUniqueViolation(sessionError)) {
        const existing = await fetchWaitingSession(supabase, productId);
        if (existing) return res.status(200).json(receivePayload(existing, product));
      }
      throw sessionError;
    }

    res.status(201).json(receivePayload(session, product, requestRow));
  } catch (error) {
    console.error('Create receive session error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

function receivePayload(session, product, requestRow = null) {
  return {
    session: serializeSession(session),
    paymentRequest: requestRow || {
      id: session.payment_request_id,
      status: 'awaiting_payment',
      amount_cents: session.amount_cents,
      expires_at: session.expires_at,
      created_at: session.created_at,
    },
    productTitle: product.title,
    amount: session.amount_cents / 100,
    amountCents: session.amount_cents,
    serviceFeeCents: session.service_fee_cents,
    totalCents: session.total_cents,
    feeLabel: feeLabel(),
    provider: 'stripe',
    mode: 'receive_session',
  };
}

/** Buyer/seller: is there an active waiting receive session for this listing? */
router.get('/meetup/session/:productId', protectSupabase, async (req, res) => {
  try {
    const { productId } = req.params;
    const supabase = getSupabaseAdmin();
    const product = await fetchProduct(supabase, productId);
    if (!product) {
      return res.status(404).json({ message: 'Listing not found' });
    }

    const session = await fetchWaitingSession(supabase, productId);
    if (!session) {
      const paid = product.is_sold ? await fetchPaidSession(supabase, productId, req.user.id) : null;
      if (paid) {
        return res.json({
          active: false,
          canPay: false,
          session: serializeSession(paid),
          paymentRequestId: paid.payment_request_id,
          status: 'paid',
          amountCents: paid.amount_cents,
          productTitle: paid.product_title,
          role: req.user.id === paid.seller_id ? 'seller' : 'buyer',
          message: null,
        });
      }
      return res.json({
        active: false,
        canPay: false,
        message: 'Ask the seller to open Receive first.',
      });
    }

    const isSeller = req.user.id === session.seller_id;
    const isBuyer = session.buyer_id ? req.user.id === session.buyer_id : !isSeller;
    const canPay = !isSeller && isBuyer && !product.is_sold;

    res.json({
      active: true,
      canPay,
      session: serializeSession(session),
      paymentRequestId: session.payment_request_id,
      status: session.status,
      amountCents: session.amount_cents,
      productTitle: session.product_title,
      expiresAt: session.expires_at,
      role: isSeller ? 'seller' : 'buyer',
      message: canPay ? null : (isSeller ? null : 'Ask the seller to open Receive first.'),
    });
  } catch (error) {
    console.error('Get payment session error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/meetup/session/:sessionId/cancel', protectSupabase, async (req, res) => {
  try {
    const { sessionId } = req.params;
    const supabase = getSupabaseAdmin();
    const { data: session, error } = await supabase
      .from('payment_sessions')
      .select('id, seller_id, payment_request_id, status')
      .eq('id', sessionId)
      .maybeSingle();
    if (error) throw error;
    if (!session) {
      return res.status(404).json({ message: 'Receive session not found' });
    }
    if (session.seller_id !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }
    if (session.status !== 'waiting') {
      return res.json({ message: 'Session already closed', status: session.status });
    }

    const now = new Date().toISOString();
    await supabase
      .from('payment_sessions')
      .update({ status: 'cancelled', updated_at: now })
      .eq('id', sessionId);
    const { data: cancelledRequest } = await supabase
      .from('payment_requests')
      .update({ status: 'cancelled', updated_at: now })
      .eq('id', session.payment_request_id)
      .eq('status', 'awaiting_payment')
      .select('payment_intent_id')
      .maybeSingle();
    await cancelIntentIfOpen(cancelledRequest?.payment_intent_id);

    res.json({ message: 'Receive session cancelled', status: 'cancelled' });
  } catch (error) {
    console.error('Cancel payment session error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Legacy: buyer-only Apple Pay request creation (still gated by an active receive session).
router.post('/meetup/request', protectSupabase, requireStripePayments, async (req, res) => {
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
    if (isSeller) {
      return res.status(400).json({
        message: 'Use /payments/meetup/receive to open a receive session',
      });
    }

    const session = await fetchWaitingSession(supabase, productId);
    if (!session) {
      return res.status(409).json({
        message: 'Ask the seller to open Receive first.',
        code: 'RECEIVE_SESSION_REQUIRED',
      });
    }
    if (session.buyer_id && session.buyer_id !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized for this receive session' });
    }

    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, status, amount_cents, expires_at, created_at')
      .eq('id', session.payment_request_id)
      .maybeSingle();
    if (error) throw error;
    if (!requestRow || requestRow.status !== 'awaiting_payment') {
      return res.status(409).json({ message: 'Ask the seller to open Receive first.' });
    }

    await supabase
      .from('payment_requests')
      .update({ buyer_id: req.user.id, updated_at: new Date().toISOString() })
      .eq('id', requestRow.id);
    if (!session.buyer_id) {
      await supabase
        .from('payment_sessions')
        .update({ buyer_id: req.user.id, updated_at: new Date().toISOString() })
        .eq('id', session.id);
    }

    res.status(201).json({
      paymentRequest: requestRow,
      session: serializeSession({ ...session, buyer_id: session.buyer_id || req.user.id }),
      productTitle: product.title,
      amount: requestRow.amount_cents / 100,
      amountCents: requestRow.amount_cents,
      provider: 'stripe',
      mode: 'apple_pay',
      publishableKey: stripe.publishableKey(),
      environment: stripe.stripeEnvironment(),
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

    const session = await fetchWaitingSession(supabase, productId);
    if (!session) {
      return res.json({
        active: false,
        canPay: false,
        message: 'Ask the seller to open Receive first.',
      });
    }

    const isSeller = req.user.id === session.seller_id;
    res.json({
      active: true,
      paymentRequestId: session.payment_request_id,
      sessionId: session.id,
      status: session.status,
      amountCents: session.amount_cents,
      expiresAt: session.expires_at,
      role: isSeller ? 'seller' : 'buyer',
      canPay: !isSeller && !product.is_sold,
      provider: 'stripe',
    });
  } catch (error) {
    console.error('Get active meetup payment error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Buyer pays on their phone (Apple Pay / card) with Stripe PaymentSheet — requires active receive session.
router.get('/meetup/:requestId/checkout', protectSupabase, requireStripePayments, async (req, res) => {
  try {
    const { requestId } = req.params;
    const supabase = getSupabaseAdmin();
    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, product_id, seller_id, amount_cents, status, expires_at, payment_intent_id')
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

    const session = await fetchWaitingSession(supabase, requestRow.product_id);
    if (!session || session.payment_request_id !== requestRow.id) {
      return res.status(409).json({
        message: 'Ask the seller to open Receive first.',
        code: 'RECEIVE_SESSION_REQUIRED',
      });
    }
    if (session.buyer_id && session.buyer_id !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized for this receive session' });
    }

    const product = await fetchProduct(supabase, requestRow.product_id);
    if (!product || product.is_sold) {
      return res.status(400).json({ message: 'This item is no longer available' });
    }

    // Never trust client amount: charge the listing price, or the offer this buyer
    // and the seller accepted in chat.
    const listingCents = Math.round(Number(product.price) * 100);
    if (!Number.isFinite(listingCents) || listingCents < 50) {
      return res.status(400).json({ message: 'Invalid listing price' });
    }
    const offerCents = await acceptedOfferCents(supabase, {
      productId: product.id,
      sellerId: requestRow.seller_id,
      buyerId: req.user.id,
    });
    const amountCents = offerCents || listingCents;
    if (amountCents !== requestRow.amount_cents) {
      const split = buyerTotal(amountCents);
      await supabase
        .from('payment_requests')
        .update({
          amount_cents: amountCents,
          platform_fee_cents: split.serviceFeeCents,
          total_cents: split.totalCents,
          updated_at: new Date().toISOString(),
        })
        .eq('id', requestRow.id);
      await supabase
        .from('payment_sessions')
        .update({
          amount_cents: amountCents,
          service_fee_cents: split.serviceFeeCents,
          total_cents: split.totalCents,
          updated_at: new Date().toISOString(),
        })
        .eq('id', session.id);
    }

    await supabase
      .from('payment_requests')
      .update({ buyer_id: req.user.id, updated_at: new Date().toISOString() })
      .eq('id', requestRow.id);
    if (!session.buyer_id) {
      await supabase
        .from('payment_sessions')
        .update({ buyer_id: req.user.id, updated_at: new Date().toISOString() })
        .eq('id', session.id);
    }

    // The buyer pays the listing price plus popup's service fee.
    const { serviceFeeCents, totalCents } = buyerTotal(amountCents);
    const intent = await findOrCreatePaymentIntent({
      requestRow,
      totalCents,
      priceCents: amountCents,
      serviceFeeCents,
      buyerId: req.user.id,
      productTitle: product.title,
    });

    res.json({
      paymentRequestId: requestRow.id,
      sessionId: session.id,
      paymentIntentId: intent.id,
      clientSecret: intent.client_secret,
      publishableKey: stripe.publishableKey(),
      amountCents: totalCents,
      priceCents: amountCents,
      serviceFeeCents,
      feeLabel: feeLabel(),
      productTitle: product.title,
      merchantDisplayName: 'popup',
      countryCode: 'US',
      currencyCode: 'USD',
    });
  } catch (error) {
    console.error('Meetup checkout error:', error);
    if (error.status === 409) {
      return res.status(409).json({ message: error.message });
    }
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

/**
 * One PaymentIntent per payment request. If the buyer backs out of the sheet and
 * taps Pay again we reuse it, so a retry can never create a second charge.
 *
 * Sellers who finished Stripe onboarding get a destination charge: the price goes
 * straight to their Express account and popup keeps only its service fee. Everyone
 * else gets a plain charge on popup's account that credits their popup balance.
 */
async function findOrCreatePaymentIntent({ requestRow, totalCents, priceCents, serviceFeeCents, buyerId, productTitle }) {
  const client = stripe.getStripe();
  const supabase = getSupabaseAdmin();
  const destination = await stripe.directPayoutAccountId(supabase, requestRow.seller_id);
  const existingId = String(requestRow.payment_intent_id || '');
  if (existingId.startsWith('pi_')) {
    const existing = await client.paymentIntents.retrieve(existingId);
    if (existing.status === 'succeeded' || existing.status === 'processing') {
      const error = new Error('This item has already been paid for.');
      error.status = 409;
      throw error;
    }
    const existingDestination = existing.transfer_data?.destination || null;
    if (REUSABLE_INTENT_STATUSES.includes(existing.status)) {
      if (existingDestination === destination) {
        if (existing.amount === totalCents) return existing;
        return client.paymentIntents.update(existing.id, {
          amount: totalCents,
          ...(destination ? { application_fee_amount: serviceFeeCents } : {}),
          metadata: { popup_price_cents: String(priceCents), popup_service_fee_cents: String(serviceFeeCents) },
        });
      }
      // The seller finished (or lost) Stripe onboarding since this intent was made:
      // swap it for one that routes the money the right way.
      await client.paymentIntents.cancel(existing.id);
    }
  }

  const intent = await client.paymentIntents.create(
    {
      amount: totalCents,
      currency: 'usd',
      // Cards + Apple Pay only: nothing that redirects away or settles days later.
      automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
      description: `popup meetup: ${String(productTitle || 'item').slice(0, 200)}`,
      statement_descriptor_suffix: 'POPUP',
      transfer_group: `popup-request-${requestRow.id}`,
      ...(destination
        ? { transfer_data: { destination }, application_fee_amount: serviceFeeCents }
        : {}),
      metadata: {
        popup_payment_request_id: requestRow.id,
        popup_product_id: requestRow.product_id,
        popup_seller_id: requestRow.seller_id,
        popup_buyer_id: buyerId,
        popup_price_cents: String(priceCents),
        popup_service_fee_cents: String(serviceFeeCents),
        popup_settlement: destination ? 'destination' : 'popup_balance',
      },
    },
    { idempotencyKey: `popup-pi-${requestRow.id}-${totalCents}-${destination || 'platform'}` }
  );

  await supabase
    .from('payment_requests')
    .update({ payment_intent_id: intent.id, updated_at: new Date().toISOString() })
    .eq('id', requestRow.id);
  return intent;
}

router.post('/meetup/:requestId/cancel', protectSupabase, async (req, res) => {
  try {
    const { requestId } = req.params;
    const supabase = getSupabaseAdmin();
    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, seller_id, product_id, status, payment_intent_id')
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

    const now = new Date().toISOString();
    await supabase
      .from('payment_requests')
      .update({ status: 'cancelled', updated_at: now })
      .eq('id', requestId);
    await supabase
      .from('payment_sessions')
      .update({ status: 'cancelled', updated_at: now })
      .eq('payment_request_id', requestId)
      .eq('status', 'waiting');
    await cancelIntentIfOpen(requestRow.payment_intent_id);

    res.json({ message: 'Payment request cancelled' });
  } catch (error) {
    console.error('Meetup cancel error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/meetup/:requestId/confirm', protectSupabase, requireStripePayments, async (req, res) => {
  try {
    const { requestId } = req.params;
    const supabase = getSupabaseAdmin();

    const { data: requestRow, error } = await supabase
      .from('payment_requests')
      .select('id, product_id, seller_id, buyer_id, payment_intent_id, status, provider, amount_cents')
      .eq('id', requestId)
      .maybeSingle();
    if (error) throw error;
    if (!requestRow) {
      return res.status(404).json({ message: 'Payment request not found' });
    }

    if (requestRow.status === 'paid') {
      return res.json({ message: 'Payment already confirmed', status: 'paid', provider: 'stripe' });
    }

    const isSeller = requestRow.seller_id === req.user.id;
    const isBuyer = requestRow.buyer_id && requestRow.buyer_id === req.user.id;
    if (!isSeller && !isBuyer) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    const intentId = String(req.body?.paymentIntentId || requestRow.payment_intent_id || '');
    if (!intentId.startsWith('pi_')) {
      return res.status(409).json({ message: 'Payment is not complete yet' });
    }

    // Never trust the app's word that it paid: ask Stripe, and make sure the
    // PaymentIntent belongs to this request.
    const intent = await stripe.getStripe().paymentIntents.retrieve(intentId);
    if (intent.metadata?.popup_payment_request_id !== requestRow.id) {
      return res.status(400).json({ message: 'Payment does not match this request' });
    }
    if (intent.status === 'processing') {
      return res.status(202).json({ message: 'Payment is processing', status: 'processing', provider: 'stripe' });
    }
    if (intent.status !== 'succeeded') {
      return res.status(409).json({ message: 'Payment is not complete yet', status: intent.status });
    }

    await fulfillMeetupPayment({
      requestRow,
      chargedCents: intent.amount_received || intent.amount,
      productId: requestRow.product_id,
      sellerId: requestRow.seller_id,
      buyerId: intent.metadata?.popup_buyer_id || requestRow.buyer_id,
      paymentId: intent.id,
      paidToAccountId: intent.transfer_data?.destination || null,
    });
    res.json({ message: 'Payment confirmed', status: 'paid', provider: 'stripe' });
  } catch (error) {
    console.error('Meetup confirm error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;
