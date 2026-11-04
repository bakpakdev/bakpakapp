const Stripe = require('stripe');

// Once a seller has finished Stripe Express onboarding, buyers pay with a
// destination charge: the listing price goes straight to the seller's Express
// account and popup only keeps its service fee (application_fee_amount).
// Sellers who haven't onboarded yet fall back to a plain charge on popup's
// account that credits their popup balance; that balance is swept to Stripe as
// soon as they finish onboarding (or they cash it out by hand).

let client = null;

function secretKey() {
  return (process.env.STRIPE_SECRET_KEY || '').trim();
}

function publishableKey() {
  return (process.env.STRIPE_PUBLISHABLE_KEY || '').trim();
}

function webhookSecret() {
  return (process.env.STRIPE_WEBHOOK_SECRET || '').trim();
}

function connectWebhookSecret() {
  return (process.env.STRIPE_CONNECT_WEBHOOK_SECRET || '').trim();
}

function isStripeConfigured() {
  return Boolean(secretKey()) && Boolean(publishableKey());
}

function stripeEnvironment() {
  return secretKey().startsWith('sk_live_') ? 'production' : 'test';
}

function getStripe() {
  if (!secretKey()) {
    throw new Error('STRIPE_SECRET_KEY is not set');
  }
  if (!client) {
    client = Stripe(secretKey(), { appInfo: { name: 'popup' } });
  }
  return client;
}

function publicBaseUrl() {
  return (process.env.PUBLIC_BASE_URL || 'http://localhost:5001').replace(/\/$/, '');
}

function onboardingReturnUrl() {
  return `${publicBaseUrl()}/api/payments/stripe/onboarding/return`;
}

function onboardingRefreshUrl() {
  return `${publicBaseUrl()}/api/payments/stripe/onboarding/refresh`;
}

/** Shape the app reads for payout state. */
function summarizeAccount(account) {
  if (!account) {
    return {
      connected: false,
      accountId: null,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      onboardingComplete: false,
      requiresAction: true,
      requirementsDue: [],
      disabledReason: null,
    };
  }
  const due = [
    ...(account.requirements?.currently_due || []),
    ...(account.requirements?.past_due || []),
  ];
  const transfersActive = account.capabilities?.transfers === 'active';
  const onboardingComplete = Boolean(account.details_submitted && account.payouts_enabled && transfersActive);
  return {
    connected: true,
    accountId: account.id,
    chargesEnabled: Boolean(account.charges_enabled),
    payoutsEnabled: Boolean(account.payouts_enabled),
    detailsSubmitted: Boolean(account.details_submitted),
    onboardingComplete,
    requiresAction: !onboardingComplete || due.length > 0,
    requirementsDue: [...new Set(due)],
    disabledReason: account.requirements?.disabled_reason || null,
  };
}

/**
 * Creates the seller's connected account. Sellers sign up inside popup with Stripe's
 * embedded onboarding; popup pays the Stripe fees and carries loss liability, and
 * Stripe collects and verifies identity and bank details. Uses controller properties,
 * not the legacy `type: 'express'`, which Stripe refuses when the platform is the
 * losses collector. Stripe requires a seller dashboard when it collects requirements
 * and popup is liable, so sellers get the light Express one (`none` is rejected).
 */
async function createSellerAccount({ email, firstName, lastName, userId }) {
  const individual = {};
  if (firstName) individual.first_name = firstName;
  if (lastName) individual.last_name = lastName;
  if (email) individual.email = email;

  return getStripe().accounts.create({
    controller: {
      fees: { payer: 'application' },
      losses: { payments: 'application' },
      requirement_collection: 'stripe',
      stripe_dashboard: { type: 'express' },
    },
    country: 'US',
    email: email || undefined,
    business_type: 'individual',
    individual: Object.keys(individual).length ? individual : undefined,
    // The charge is on popup's account (destination charges), but Stripe only lets a
    // US account request transfers on its own with special approval, so request
    // card_payments alongside it. Sellers still never take card payments themselves.
    capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
    // Sales collect in the seller's balance (shown as their popup balance) until they
    // tap Cash out, instead of Stripe sweeping them to the bank on its own schedule.
    settings: { payouts: { schedule: { interval: 'manual' } } },
    business_profile: {
      // 5931 = used merchandise and secondhand stores.
      mcc: '5931',
      product_description: 'Selling secondhand items to other students at in-person campus meetups on popup.',
    },
    metadata: { popup_user_id: userId },
  });
}

/** USD available (cash-out-able) and pending (still clearing) in a connected account. */
async function connectedBalance(accountId) {
  const balance = await getStripe().balance.retrieve({}, { stripeAccount: accountId });
  const usd = (list) => (list || []).filter((b) => b.currency === 'usd').reduce((sum, b) => sum + b.amount, 0);
  return { availableCents: usd(balance.available), pendingCents: usd(balance.pending) };
}

/** Accounts made before manual payouts existed: switch them so money waits for Cash out. */
async function ensureManualPayouts(account) {
  if (!account || account.settings?.payouts?.schedule?.interval === 'manual') return account;
  try {
    return await getStripe().accounts.update(account.id, {
      settings: { payouts: { schedule: { interval: 'manual' } } },
    });
  } catch (err) {
    console.warn('Could not switch payouts to manual:', account.id, err.message);
    return account;
  }
}

/** Sends `amountCents` from the seller's Stripe balance to their bank or debit card. */
async function createSellerPayout(accountId, amountCents, idempotencyKey) {
  return getStripe().payouts.create(
    { amount: amountCents, currency: 'usd', description: 'popup cash out' },
    { stripeAccount: accountId, idempotencyKey }
  );
}

async function createOnboardingLink(accountId) {
  return getStripe().accountLinks.create({
    account: accountId,
    type: 'account_onboarding',
    refresh_url: onboardingRefreshUrl(),
    return_url: onboardingReturnUrl(),
    collection_options: { fields: 'currently_due' },
  });
}

/** Accounts created by createSellerAccount have no Stripe dashboard to log in to. */
function hasStripeDashboard(account) {
  const type = account?.controller?.stripe_dashboard?.type;
  return account?.type === 'express' || type === 'express' || type === 'full';
}

/**
 * Short-lived session for Stripe's in-app screens (StripeConnect iOS SDK): onboarding
 * to sign up or answer Stripe's follow-up questions, and payouts to see payouts and
 * change the bank. Cash out stays popup's own button, so sellers can't start payouts
 * or change the schedule from Stripe's screen. popup already asks for an
 * authenticator code before this, so Stripe's extra login step is turned off where
 * the account type allows it.
 */
async function createAccountSession(account) {
  const noDashboard = !hasStripeDashboard(account);
  const auth = noDashboard ? { disable_stripe_user_authentication: true } : {};
  const session = await getStripe().accountSessions.create({
    account: account.id,
    components: {
      account_onboarding: {
        enabled: true,
        features: { external_account_collection: true, ...auth },
      },
      payouts: {
        enabled: true,
        features: {
          external_account_collection: true,
          instant_payouts: false,
          standard_payouts: false,
          edit_payout_schedule: false,
          ...auth,
        },
      },
    },
  });
  return { clientSecret: session.client_secret, expiresAt: session.expires_at };
}

async function retrieveAccount(accountId) {
  if (!accountId) return null;
  try {
    return await getStripe().accounts.retrieve(accountId);
  } catch (err) {
    // Account deleted in the Stripe dashboard or created with other keys (test vs live).
    if (err?.code === 'account_invalid' || err?.statusCode === 404 || err?.type === 'StripePermissionError') {
      console.warn('Stripe account not reachable:', accountId, err.message);
      return null;
    }
    throw err;
  }
}

/**
 * The seller's Express account id if sales can be sent straight to it, else null
 * (not onboarded, restricted, or Stripe unreachable: the sale then goes to the
 * popup balance instead, so a checkout never fails over this).
 */
async function directPayoutAccountId(supabase, sellerId) {
  try {
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('stripe_account_id')
      .eq('id', sellerId)
      .maybeSingle();
    if (error) throw error;
    const account = await retrieveAccount(profile?.stripe_account_id);
    return summarizeAccount(account).onboardingComplete ? account.id : null;
  } catch (err) {
    console.warn('Could not check seller Stripe account, using popup balance:', sellerId, err.message);
    return null;
  }
}

// Platform events (payment_intent.*) and Connect events (account.updated) come from
// separate Dashboard endpoints with their own signing secrets; locally `stripe listen`
// uses one secret for both.
function constructWebhookEvent(rawBody, signature) {
  const secrets = [webhookSecret(), connectWebhookSecret()].filter(Boolean);
  let lastError = null;
  for (const secret of secrets) {
    try {
      return getStripe().webhooks.constructEvent(rawBody, signature, secret);
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError || new Error('STRIPE_WEBHOOK_SECRET is not set');
}

module.exports = {
  connectedBalance,
  ensureManualPayouts,
  createSellerPayout,
  getStripe,
  isStripeConfigured,
  publishableKey,
  webhookSecret,
  stripeEnvironment,
  summarizeAccount,
  createSellerAccount,
  createAccountSession,
  hasStripeDashboard,
  createOnboardingLink,
  retrieveAccount,
  directPayoutAccountId,
  constructWebhookEvent,
};
