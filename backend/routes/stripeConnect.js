const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { requirePayoutMfa } = require('../middleware/payoutMfa');
const { notifyPayoutMethodChanged } = require('../lib/email');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');
const { fulfillMeetupPayment } = require('../lib/meetupFulfill');
const {
  getOrCreateSellerBalance,
  reserveForPayout,
  releasePayout,
  serializeBalance,
} = require('../lib/sellerBalance');
const stripe = require('../lib/stripe');

const router = express.Router();

// Smallest cash out we'll send. Stripe has no hard floor, but cents-sized
// transfers aren't worth the per-payout fee.
const MIN_CASHOUT_CENTS = 100;

function requireStripe(_req, res, next) {
  if (!stripe.isStripeConfigured()) {
    return res.status(503).json({
      message: 'Stripe is not configured. Add STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY.',
    });
  }
  next();
}

async function loadSellerProfile(supabase, userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, email, first_name, last_name, stripe_account_id')
    .eq('id', userId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function retrieveAccount(accountId) {
  if (!accountId) return null;
  try {
    return await stripe.getStripe().accounts.retrieve(accountId);
  } catch (err) {
    // Account deleted in the Stripe dashboard or created with other keys (test vs live).
    if (err?.code === 'account_invalid' || err?.statusCode === 404 || err?.type === 'StripePermissionError') {
      console.warn('Stripe account not reachable:', accountId, err.message);
      return null;
    }
    throw err;
  }
}

async function ensureAccount(supabase, user) {
  const profile = await loadSellerProfile(supabase, user.id);
  const existing = await retrieveAccount(profile?.stripe_account_id);
  if (existing) return existing;

  const account = await stripe.createExpressAccount({
    userId: user.id,
    email: profile?.email || user.email || null,
    firstName: profile?.first_name || null,
    lastName: profile?.last_name || null,
  });
  const { error } = await supabase
    .from('profiles')
    .update({ stripe_account_id: account.id, updated_at: new Date().toISOString() })
    .eq('id', user.id);
  if (error) throw error;
  notifyPayoutMethodChanged(user.id, 'connected');
  return account;
}

function statusPayload(account, balance) {
  return {
    configured: stripe.isStripeConfigured(),
    environment: stripe.stripeEnvironment(),
    ...stripe.summarizeAccount(account),
    ...serializeBalance(balance),
  };
}

router.get('/status', protectSupabase, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const balance = await getOrCreateSellerBalance(supabase, req.user.id);
    if (!stripe.isStripeConfigured()) {
      return res.json(statusPayload(null, balance));
    }
    const profile = await loadSellerProfile(supabase, req.user.id);
    const account = await retrieveAccount(profile?.stripe_account_id);
    res.json(statusPayload(account, balance));
  } catch (error) {
    console.error('Stripe status error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

/** Creates the seller's Express account if needed and returns a Stripe-hosted signup link. */
router.post('/onboarding', protectSupabase, requirePayoutMfa, requireStripe, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const account = await ensureAccount(supabase, req.user);
    const link = await stripe.createOnboardingLink(account.id);
    res.json({ url: link.url, expiresAt: link.expires_at, accountId: account.id });
  } catch (error) {
    console.error('Stripe onboarding error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Stripe needs https return/refresh URLs; these bounce back into the app.
router.get('/onboarding/return', (_req, res) => {
  res.redirect('popup://stripe-connect?done=1');
});

router.get('/onboarding/refresh', (_req, res) => {
  res.redirect('popup://stripe-connect?refresh=1');
});

/** Stripe Express dashboard: change bank/debit card, see payouts. */
router.post('/dashboard', protectSupabase, requirePayoutMfa, requireStripe, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const profile = await loadSellerProfile(supabase, req.user.id);
    const account = await retrieveAccount(profile?.stripe_account_id);
    if (!account?.details_submitted) {
      const ensured = account || await ensureAccount(supabase, req.user);
      const link = await stripe.createOnboardingLink(ensured.id);
      return res.json({ url: link.url, requiresOnboarding: true });
    }
    const login = await stripe.getStripe().accounts.createLoginLink(account.id);
    res.json({ url: login.url, requiresOnboarding: false });
  } catch (error) {
    console.error('Stripe dashboard error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/cashout', protectSupabase, requirePayoutMfa, requireStripe, async (req, res) => {
  const supabase = getSupabaseAdmin();
  let payoutRow = null;
  let reservedCents = 0;
  try {
    const profile = await loadSellerProfile(supabase, req.user.id);
    const account = await retrieveAccount(profile?.stripe_account_id);
    const balance = await getOrCreateSellerBalance(supabase, req.user.id);
    const summary = stripe.summarizeAccount(account);

    if (!summary.onboardingComplete) {
      const ensured = account || await ensureAccount(supabase, req.user);
      const link = await stripe.createOnboardingLink(ensured.id);
      return res.json({
        requiresOnboarding: true,
        url: link.url,
        message: 'Finish your Stripe payout setup to cash out. Your sales stay in your popup balance until then.',
        status: statusPayload(ensured, balance),
      });
    }

    const available = balance.available_cents || 0;
    const requested = Number(req.body?.amountCents);
    const amountCents = Number.isFinite(requested) && requested > 0
      ? Math.min(Math.round(requested), available)
      : available;
    if (amountCents < MIN_CASHOUT_CENTS) {
      return res.status(400).json({ message: 'You need at least $1.00 to cash out.' });
    }

    const reserved = await reserveForPayout(supabase, balance, amountCents);
    if (!reserved) {
      return res.status(409).json({ message: 'Your balance just changed. Pull to refresh and try again.' });
    }
    reservedCents = amountCents;

    const { data: inserted, error: insertError } = await supabase
      .from('seller_payouts')
      .insert({ seller_id: req.user.id, amount_cents: amountCents, status: 'pending' })
      .select('id')
      .single();
    if (insertError) throw insertError;
    payoutRow = inserted;

    const transfer = await stripe.getStripe().transfers.create(
      {
        amount: amountCents,
        currency: 'usd',
        destination: account.id,
        description: 'popup cash out',
        metadata: { popup_payout_id: payoutRow.id, popup_seller_id: req.user.id },
      },
      { idempotencyKey: `popup-payout-${payoutRow.id}` }
    );

    // The transfer lands in the seller's Stripe balance right away; Stripe then
    // pays it to their bank or debit card on its normal schedule.
    await supabase
      .from('seller_payouts')
      .update({ status: 'paid', stripe_transfer_id: transfer.id, updated_at: new Date().toISOString() })
      .eq('id', payoutRow.id);

    res.json({
      requiresOnboarding: false,
      amountCents,
      transferId: transfer.id,
      message: `$${(amountCents / 100).toFixed(2)} is on its way. It usually reaches your bank in 1–2 business days.`,
      status: statusPayload(account, reserved),
    });
  } catch (error) {
    console.error('Stripe cashout error:', error);
    if (reservedCents > 0) {
      try {
        await releasePayout(supabase, req.user.id, reservedCents);
        if (payoutRow) {
          await supabase
            .from('seller_payouts')
            .update({
              status: 'failed',
              failure_reason: String(error.message || 'Transfer failed').slice(0, 500),
              updated_at: new Date().toISOString(),
            })
            .eq('id', payoutRow.id);
        }
      } catch (releaseError) {
        console.error('Stripe cashout release error (balance needs manual fix):', releaseError);
      }
    }
    if (error?.code === 'balance_insufficient') {
      return res.status(409).json({
        code: 'FUNDS_CLEARING',
        message: 'Your recent sales are still clearing with the bank. Try cashing out again in a couple of days.',
      });
    }
    res.status(500).json({ message: 'Cash out failed. Your balance was not charged.', error: error.message });
  }
});

/** Recent cash outs for the seller's history list. */
router.get('/payouts', protectSupabase, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from('seller_payouts')
      .select('id, amount_cents, status, failure_reason, created_at')
      .eq('seller_id', req.user.id)
      .order('created_at', { ascending: false })
      .limit(50);
    if (error) throw error;
    res.json({ payouts: data || [] });
  } catch (error) {
    console.error('Stripe payouts list error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// MARK: - Webhook

async function fulfillFromPaymentIntent(intent) {
  const requestId = intent.metadata?.popup_payment_request_id;
  if (!requestId) return;
  const supabase = getSupabaseAdmin();
  const { data: requestRow, error } = await supabase
    .from('payment_requests')
    .select('id, product_id, seller_id, buyer_id, amount_cents, status, provider')
    .eq('id', requestId)
    .maybeSingle();
  if (error) throw error;
  if (!requestRow) {
    console.warn('Stripe PaymentIntent with no payment_request', intent.id, requestId);
    return;
  }
  await fulfillMeetupPayment({
    requestRow: { ...requestRow, amount_cents: intent.amount_received || intent.amount },
    productId: requestRow.product_id,
    sellerId: requestRow.seller_id,
    buyerId: intent.metadata?.popup_buyer_id || requestRow.buyer_id,
    paymentId: intent.id,
  });
}

async function handleTransferReversed(transfer) {
  const payoutId = transfer.metadata?.popup_payout_id;
  const sellerId = transfer.metadata?.popup_seller_id;
  if (!payoutId || !sellerId) return;
  const supabase = getSupabaseAdmin();
  const { data: payout, error } = await supabase
    .from('seller_payouts')
    .update({ status: 'failed', failure_reason: 'Transfer reversed', updated_at: new Date().toISOString() })
    .eq('id', payoutId)
    .eq('status', 'paid')
    .select('id, amount_cents')
    .maybeSingle();
  if (error) throw error;
  // Only a full reversal goes back to the popup balance; partial ones need a human look.
  if (payout && transfer.amount_reversed >= transfer.amount) {
    await releasePayout(supabase, sellerId, payout.amount_cents);
  }
}

async function stripeWebhookHandler(req, res) {
  let event;
  try {
    event = stripe.constructWebhookEvent(req.body, req.headers['stripe-signature']);
  } catch (err) {
    console.warn('Stripe webhook signature failed:', err.message);
    return res.status(400).json({ error: 'Invalid Stripe webhook signature' });
  }

  try {
    switch (event.type) {
      case 'payment_intent.succeeded':
        await fulfillFromPaymentIntent(event.data.object);
        break;
      case 'payment_intent.payment_failed':
        console.warn('Stripe payment failed:', event.data.object.id, event.data.object.last_payment_error?.message);
        break;
      case 'transfer.reversed':
        await handleTransferReversed(event.data.object);
        break;
      case 'charge.refunded':
      case 'charge.dispute.created':
        // Refunds and disputes are handled by hand in the Stripe dashboard for now.
        console.warn(`Stripe ${event.type}:`, event.data.object.id, event.data.object.payment_intent);
        break;
      default:
        break;
    }
  } catch (err) {
    console.error('Stripe webhook handler error:', err);
    return res.status(500).json({ error: 'Webhook handler failed' });
  }

  res.json({ received: true });
}

module.exports = router;
module.exports.stripeWebhookHandler = stripeWebhookHandler;
