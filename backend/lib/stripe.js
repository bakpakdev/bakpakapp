const Stripe = require('stripe');

// Buyers pay popup's Stripe account (separate charges). Sales credit the seller's
// popup balance, and cash out sends a Transfer to the seller's Express account,
// which Stripe then pays out to their bank or debit card.

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

async function createExpressAccount({ email, firstName, lastName, userId }) {
  const individual = {};
  if (firstName) individual.first_name = firstName;
  if (lastName) individual.last_name = lastName;
  if (email) individual.email = email;

  return getStripe().accounts.create({
    type: 'express',
    country: 'US',
    email: email || undefined,
    business_type: 'individual',
    individual: Object.keys(individual).length ? individual : undefined,
    // Separate charges + transfers: sellers only receive transfers, they never charge cards.
    capabilities: { transfers: { requested: true } },
    business_profile: {
      // 5931 = used merchandise and secondhand stores.
      mcc: '5931',
      product_description: 'Selling secondhand items to other students at in-person campus meetups on popup.',
    },
    metadata: { popup_user_id: userId },
  });
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

function constructWebhookEvent(rawBody, signature) {
  return getStripe().webhooks.constructEvent(rawBody, signature, webhookSecret());
}

module.exports = {
  getStripe,
  isStripeConfigured,
  publishableKey,
  webhookSecret,
  stripeEnvironment,
  summarizeAccount,
  createExpressAccount,
  createOnboardingLink,
  constructWebhookEvent,
};
