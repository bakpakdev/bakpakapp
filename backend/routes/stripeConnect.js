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

const retrieveAccount = stripe.retrieveAccount;

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

/**
 * Moves `amountCents` of the seller's popup balance to their Express account with
 * a Transfer, recorded in seller_payouts. Returns null if the balance changed
 * underneath us; on a Stripe error the balance is put back and the error rethrown.
 */
async function sendBalanceToStripe(supabase, balance, accountId, amountCents, description) {
  const sellerId = balance.seller_id;
  const reserved = await reserveForPayout(supabase, balance, amountCents);
  if (!reserved) return null;

  let payoutRow = null;
  try {
    const { data: inserted, error: insertError } = await supabase
      .from('seller_payouts')
      .insert({ seller_id: sellerId, amount_cents: amountCents, status: 'pending' })
      .select('id')
      .single();
    if (insertError) throw insertError;
    payoutRow = inserted;

    const transfer = await stripe.getStripe().transfers.create(
      {
        amount: amountCents,
        currency: 'usd',
        destination: accountId,
        description,
        metadata: { popup_payout_id: payoutRow.id, popup_seller_id: sellerId },
      },
      { idempotencyKey: `popup-payout-${payoutRow.id}` }
    );

    // The transfer lands in the seller's Stripe balance right away; Stripe then
    // pays it to their bank or debit card on its normal schedule.
    await supabase
      .from('seller_payouts')
      .update({ status: 'paid', stripe_transfer_id: transfer.id, updated_at: new Date().toISOString() })
      .eq('id', payoutRow.id);
    return { transfer, balance: reserved };
  } catch (error) {
    try {
      await releasePayout(supabase, sellerId, amountCents);
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
      console.error('Stripe payout release error (balance needs manual fix):', releaseError);
    }
    throw error;
  }
}

/**
 * Once a seller is onboarded, new sales go straight to Stripe, so anything left in
 * their popup balance (sales from before onboarding) is sent over too. Best effort:
 * if popup's own Stripe funds are still clearing it stays put and we try again on
 * the next status check or account update. Returns the new balance, or null.
 */
async function sweepBalanceToStripe(supabase, sellerId, account) {
  if (!stripe.summarizeAccount(account).onboardingComplete) return null;
  try {
    const balance = await getOrCreateSellerBalance(supabase, sellerId);
    const amountCents = balance.available_cents || 0;
    if (amountCents <= 0) return null;
    // Skip quietly while popup's funds are still pending, rather than logging a
    // failed payout in the seller's history on every status check.
    const platform = await stripe.getStripe().balance.retrieve();
    const availableUsd = (platform.available || []).find((b) => b.currency === 'usd')?.amount || 0;
    if (availableUsd < amountCents) return null;
    const sent = await sendBalanceToStripe(supabase, balance, account.id, amountCents, 'popup balance moved to Stripe');
    if (sent) console.log(`Swept ${amountCents} cents of popup balance to ${account.id} for seller ${sellerId}`);
    return sent?.balance || null;
  } catch (err) {
    console.warn('Balance sweep to Stripe deferred:', sellerId, err.code || '', err.message);
    return null;
  }
}

/**
 * Once a seller is onboarded their sales sit in their Stripe balance, so that's what
 * the app shows as their popup balance: available (can cash out now) plus anything
 * left in the popup ledger, and pending (still clearing, usually ~2 business days).
 */
function statusPayload(account, balance, stripeBalance = null) {
  const base = serializeBalance(balance);
  if (stripeBalance) {
    base.availableCents += stripeBalance.availableCents;
    base.pendingCents += stripeBalance.pendingCents;
  }
  return {
    configured: stripe.isStripeConfigured(),
    environment: stripe.stripeEnvironment(),
    ...stripe.summarizeAccount(account),
    ...base,
  };
}

async function stripeBalanceIfOnboarded(account) {
  if (!stripe.summarizeAccount(account).onboardingComplete) return null;
  try {
    return await stripe.connectedBalance(account.id);
  } catch (err) {
    console.warn('Connected balance unavailable:', account.id, err.message);
    return null;
  }
}

router.get('/status', protectSupabase, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const balance = await getOrCreateSellerBalance(supabase, req.user.id);
    if (!stripe.isStripeConfigured()) {
      return res.json(statusPayload(null, balance));
    }
    const profile = await loadSellerProfile(supabase, req.user.id);
    const account = await stripe.ensureManualPayouts(await retrieveAccount(profile?.stripe_account_id));
    // The app checks status right after Stripe onboarding, so that's when sales
    // made before onboarding move out of popup's account.
    const swept = await sweepBalanceToStripe(supabase, req.user.id, account);
    res.json(statusPayload(account, swept || balance, await stripeBalanceIfOnboarded(account)));
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

    // Anything still in the popup ledger (sales before onboarding) moves to Stripe first,
    // then the whole Stripe balance can go to the bank in one payout.
    const ready = await stripe.ensureManualPayouts(account);
    const swept = await sweepBalanceToStripe(supabase, req.user.id, ready);
    const ledger = swept || await getOrCreateSellerBalance(supabase, req.user.id);
    const inStripe = await stripe.connectedBalance(ready.id);

    const requested = Number(req.body?.amountCents);
    const amountCents = Number.isFinite(requested) && requested > 0
      ? Math.min(Math.round(requested), inStripe.availableCents)
      : inStripe.availableCents;
    if (amountCents < MIN_CASHOUT_CENTS) {
      const clearing = inStripe.pendingCents + (ledger.available_cents || 0);
      return res.status(400).json({
        code: clearing > 0 ? 'FUNDS_CLEARING' : 'NOTHING_TO_CASH_OUT',
        message: clearing > 0
          ? `$${(clearing / 100).toFixed(2)} is still clearing from your recent sales. It’s usually ready to cash out in about 2 business days.`
          : 'You need at least $1.00 to cash out.',
        status: statusPayload(ready, ledger, inStripe),
      });
    }

    const { data: payoutRow, error: insertError } = await supabase
      .from('seller_payouts')
      .insert({ seller_id: req.user.id, amount_cents: amountCents, status: 'pending' })
      .select('id')
      .single();
    if (insertError) throw insertError;

    let payout;
    try {
      payout = await stripe.createSellerPayout(ready.id, amountCents, `popup-bank-payout-${payoutRow.id}`);
    } catch (err) {
      await supabase
        .from('seller_payouts')
        .update({ status: 'failed', failure_reason: String(err.message || 'Payout failed').slice(0, 500), updated_at: new Date().toISOString() })
        .eq('id', payoutRow.id);
      throw err;
    }
    await supabase
      .from('seller_payouts')
      .update({ status: 'paid', stripe_transfer_id: payout.id, updated_at: new Date().toISOString() })
      .eq('id', payoutRow.id);

    const after = await stripe.connectedBalance(ready.id).catch(() => null);
    res.json({
      requiresOnboarding: false,
      amountCents,
      transferId: payout.id,
      message: `$${(amountCents / 100).toFixed(2)} is on its way to your bank. It usually arrives in 1–2 business days.`,
      status: statusPayload(ready, ledger, after),
    });
  } catch (error) {
    console.error('Stripe cashout error:', error);
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
    requestRow,
    chargedCents: intent.amount_received || intent.amount,
    productId: requestRow.product_id,
    sellerId: requestRow.seller_id,
    buyerId: intent.metadata?.popup_buyer_id || requestRow.buyer_id,
    paymentId: intent.id,
    paidToAccountId: intent.transfer_data?.destination || null,
  });
}

/** Connect event: a seller finished (or updated) Stripe onboarding. */
async function handleAccountUpdated(account) {
  const supabase = getSupabaseAdmin();
  const { data: profile, error } = await supabase
    .from('profiles')
    .select('id')
    .eq('stripe_account_id', account.id)
    .maybeSingle();
  if (error) throw error;
  if (!profile) return;
  await sweepBalanceToStripe(supabase, profile.id, account);
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
      case 'account.updated':
        await handleAccountUpdated(event.data.object);
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
