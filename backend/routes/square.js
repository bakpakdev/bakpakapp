const express = require('express');
const { protectSupabase } = require('../middleware/supabaseAuth');
const { getSupabaseAdmin } = require('../lib/supabaseAdmin');
const { fulfillMeetupPayment } = require('../lib/meetupFulfill');
const { getOrCreateSellerBalance, serializeBalance } = require('../lib/sellerBalance');
const square = require('../lib/square');

const router = express.Router();

function requireSquareOAuth(_req, res, next) {
  if (!square.canOAuthSellers()) {
    return res.status(503).json({
      message: 'Square OAuth is not configured. Add SQUARE_APPLICATION_ID and SQUARE_APPLICATION_SECRET.',
    });
  }
  next();
}

function requireSquarePayments(_req, res, next) {
  if (!square.canTakePayments()) {
    return res.status(503).json({
      message: 'Square payments are not configured. Add SQUARE_ACCESS_TOKEN and SQUARE_LOCATION_ID.',
    });
  }
  next();
}

async function loadConnection(supabase, userId) {
  const { data, error } = await supabase
    .from('square_connections')
    .select('user_id, merchant_id, location_id, access_token, refresh_token, expires_at')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function refreshConnectionIfNeeded(supabase, connection) {
  if (!connection) return null;
  const expiresAt = new Date(connection.expires_at).getTime();
  const needsRefresh = !Number.isFinite(expiresAt) || expiresAt - Date.now() < 7 * 24 * 60 * 60 * 1000;
  if (!needsRefresh) return connection;

  const token = await square.obtainToken({ refreshToken: connection.refresh_token });
  const next = {
    access_token: token.access_token,
    refresh_token: token.refresh_token || connection.refresh_token,
    expires_at: square.expiresAtFromToken(token).toISOString(),
    merchant_id: token.merchant_id || connection.merchant_id,
    updated_at: new Date().toISOString(),
  };
  const { data, error } = await supabase
    .from('square_connections')
    .update(next)
    .eq('user_id', connection.user_id)
    .select('user_id, merchant_id, location_id, access_token, refresh_token, expires_at')
    .single();
  if (error) throw error;
  return data;
}

router.get('/status', protectSupabase, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const connection = square.isSquareConfigured()
      ? await loadConnection(supabase, req.user.id)
      : null;
    const balance = await getOrCreateSellerBalance(supabase, req.user.id);
    let refreshed = connection;
    let bankAccountsLinked = false;
    if (connection) {
      try {
        refreshed = await refreshConnectionIfNeeded(supabase, connection);
        const banks = await square.listBankAccounts(refreshed.access_token);
        bankAccountsLinked = banks.some((b) => {
          const status = String(b.status || '').toUpperCase();
          return status === 'VERIFIED' || status === 'VERIFICATION_IN_PROGRESS' || status === 'ACTIVE';
        }) || banks.length > 0;
      } catch (bankErr) {
        console.warn('Square bank accounts check:', bankErr.message);
      }
    }
    const connected = Boolean(refreshed);
    res.json({
      configured: square.isSquareConfigured(),
      canTakePayments: square.canTakePayments(),
      connected,
      environment: square.squareEnvironment(),
      merchantId: refreshed?.merchant_id || null,
      locationId: refreshed?.location_id || square.platformLocationId() || null,
      chargesEnabled: connected,
      payoutsEnabled: connected && bankAccountsLinked,
      onboardingComplete: connected && bankAccountsLinked,
      detailsSubmitted: connected,
      bankAccountsLinked,
      requiresAction: !connected || !bankAccountsLinked,
      ...serializeBalance(balance),
    });
  } catch (error) {
    console.error('Square status error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

function serializePayoutProfile(row) {
  if (!row) return null;
  return {
    userId: row.user_id,
    legalFirstName: row.legal_first_name || '',
    legalLastName: row.legal_last_name || '',
    email: row.email || '',
    phone: row.phone || '',
    entityType: row.entity_type || 'individual',
    businessName: row.business_name || '',
    addressLine1: row.address_line1 || '',
    addressLine2: row.address_line2 || '',
    city: row.city || '',
    state: row.state || '',
    postalCode: row.postal_code || '',
    country: row.country || 'US',
    hasIdReady: Boolean(row.has_id_ready),
    hasBankReady: Boolean(row.has_bank_ready),
    currentStep: row.current_step || 'overview',
    overviewDone: Boolean(row.overview_done),
    personalDone: Boolean(row.personal_done),
    addressDone: Boolean(row.address_done),
    entityDone: Boolean(row.entity_done),
    checklistDone: Boolean(row.checklist_done),
    squareConnectDone: Boolean(row.square_connect_done),
    bankLinkDone: Boolean(row.bank_link_done),
    completedAt: row.completed_at || null,
  };
}

router.get('/payout-profile', protectSupabase, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from('seller_payout_profiles')
      .select('*')
      .eq('user_id', req.user.id)
      .maybeSingle();
    if (error) throw error;

    let profile = data;
    if (!profile) {
      const { data: userRow } = await supabase
        .from('profiles')
        .select('email, first_name, last_name, shop_name')
        .eq('id', req.user.id)
        .maybeSingle();
      profile = {
        user_id: req.user.id,
        legal_first_name: userRow?.first_name || '',
        legal_last_name: userRow?.last_name || '',
        email: userRow?.email || req.user.email || '',
        phone: '',
        entity_type: 'individual',
        business_name: userRow?.shop_name || '',
        address_line1: '',
        address_line2: '',
        city: '',
        state: '',
        postal_code: '',
        country: 'US',
        has_id_ready: false,
        has_bank_ready: false,
        current_step: 'overview',
        overview_done: false,
        personal_done: false,
        address_done: false,
        entity_done: false,
        checklist_done: false,
        square_connect_done: false,
        bank_link_done: false,
        completed_at: null,
      };
    }

    const connection = await loadConnection(supabase, req.user.id);
    res.json({
      profile: serializePayoutProfile(profile),
      squareConnected: Boolean(connection),
    });
  } catch (error) {
    console.error('Square payout profile get error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.put('/payout-profile', protectSupabase, async (req, res) => {
  try {
    const body = req.body || {};
    const entityType = body.entityType === 'business' ? 'business' : 'individual';
    const row = {
      user_id: req.user.id,
      legal_first_name: String(body.legalFirstName || '').trim() || null,
      legal_last_name: String(body.legalLastName || '').trim() || null,
      email: String(body.email || '').trim() || null,
      phone: String(body.phone || '').trim() || null,
      entity_type: entityType,
      business_name: String(body.businessName || '').trim() || null,
      address_line1: String(body.addressLine1 || '').trim() || null,
      address_line2: String(body.addressLine2 || '').trim() || null,
      city: String(body.city || '').trim() || null,
      state: String(body.state || '').trim().toUpperCase() || null,
      postal_code: String(body.postalCode || '').trim() || null,
      country: String(body.country || 'US').trim().toUpperCase() || 'US',
      has_id_ready: Boolean(body.hasIdReady),
      has_bank_ready: Boolean(body.hasBankReady),
      current_step: String(body.currentStep || 'overview').trim() || 'overview',
      overview_done: Boolean(body.overviewDone),
      personal_done: Boolean(body.personalDone),
      address_done: Boolean(body.addressDone),
      entity_done: Boolean(body.entityDone),
      checklist_done: Boolean(body.checklistDone),
      square_connect_done: Boolean(body.squareConnectDone),
      bank_link_done: Boolean(body.bankLinkDone),
      completed_at: body.completedAt || (body.bankLinkDone ? new Date().toISOString() : null),
      updated_at: new Date().toISOString(),
    };

    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from('seller_payout_profiles')
      .upsert(row, { onConflict: 'user_id' })
      .select('*')
      .single();
    if (error) throw error;

    res.json({ profile: serializePayoutProfile(data) });
  } catch (error) {
    console.error('Square payout profile put error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/oauth/start', protectSupabase, requireSquareOAuth, async (req, res) => {
  try {
    res.json({
      url: square.authorizeUrl(req.user.id),
      redirectUri: square.oauthRedirectUri(),
    });
  } catch (error) {
    console.error('Square OAuth start error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.get('/oauth/callback', async (req, res) => {
  const fail = (message) => {
    const encoded = encodeURIComponent(message || 'Square connection failed');
    return res.redirect(`popup://square-oauth?error=${encoded}`);
  };

  try {
    if (req.query.error) {
      return fail(String(req.query.error_description || req.query.error));
    }

    const parsed = square.parseOAuthState(req.query.state);
    if (!parsed?.uid) {
      return fail('Invalid or expired Square OAuth state');
    }
    if (!req.query.code) {
      return fail('Missing Square authorization code');
    }

    const token = await square.obtainToken({ code: req.query.code });
    const locations = await square.listLocations(token.access_token);
    const location = locations[0];
    if (!location?.id) {
      return fail('No active Square location found. Add a location in Square Dashboard.');
    }

    const supabase = getSupabaseAdmin();
    const row = {
      user_id: parsed.uid,
      merchant_id: token.merchant_id,
      location_id: location.id,
      access_token: token.access_token,
      refresh_token: token.refresh_token,
      expires_at: square.expiresAtFromToken(token).toISOString(),
      updated_at: new Date().toISOString(),
    };

    const { error: upsertError } = await supabase
      .from('square_connections')
      .upsert(row, { onConflict: 'user_id' });
    if (upsertError) throw upsertError;

    await supabase
      .from('profiles')
      .update({
        square_merchant_id: token.merchant_id,
        updated_at: new Date().toISOString(),
      })
      .eq('id', parsed.uid);

    await supabase
      .from('seller_payout_profiles')
      .upsert({
        user_id: parsed.uid,
        square_connect_done: true,
        current_step: 'bank',
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });

    res.redirect('popup://square-oauth?connected=1');
  } catch (error) {
    console.error('Square OAuth callback error:', error);
    return fail(error.message);
  }
});

router.post('/disconnect', protectSupabase, requireSquareOAuth, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const connection = await loadConnection(supabase, req.user.id);
    if (connection?.access_token) {
      await square.revokeToken(connection.access_token);
    }
    await supabase.from('square_connections').delete().eq('user_id', req.user.id);
    await supabase
      .from('profiles')
      .update({ square_merchant_id: null, updated_at: new Date().toISOString() })
      .eq('id', req.user.id);
    res.json({ connected: false, message: 'Square disconnected' });
  } catch (error) {
    console.error('Square disconnect error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.get('/sdk-session', protectSupabase, requireSquarePayments, async (req, res) => {
  try {
    res.json({
      accessToken: square.platformAccessToken(),
      locationId: square.platformLocationId(),
      applicationId: process.env.SQUARE_APPLICATION_ID,
      environment: square.squareEnvironment(),
    });
  } catch (error) {
    console.error('Square SDK session error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/dashboard', protectSupabase, requireSquareOAuth, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const connection = await loadConnection(supabase, req.user.id);
    if (!connection) {
      return res.status(409).json({
        requiresOnboarding: true,
        message: 'Connect Square before opening the dashboard.',
      });
    }
    const url = square.squareEnvironment() === 'production'
      ? 'https://squareup.com/dashboard'
      : 'https://squareupsandbox.com/dashboard';
    res.json({ url });
  } catch (error) {
    console.error('Square dashboard error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

router.post('/cashout', protectSupabase, requireSquareOAuth, async (req, res) => {
  try {
    const supabase = getSupabaseAdmin();
    const connection = await loadConnection(supabase, req.user.id);
    const balance = await getOrCreateSellerBalance(supabase, req.user.id);

    if (!connection) {
      const start = { url: square.authorizeUrl(req.user.id) };
      return res.json({
        requiresOnboarding: true,
        url: start.url,
        message: 'Connect Square once to cash out. Sales stay in your popup account until then.',
        status: {
          configured: true,
          connected: false,
          onboardingComplete: false,
          requiresAction: true,
          ...serializeBalance(balance),
        },
      });
    }

    const available = balance.available_cents || 0;
    const requested = Number(req.body?.amountCents);
    const amountCents = Number.isFinite(requested) && requested > 0
      ? Math.min(requested, available)
      : available;
    if (amountCents < 50) {
      return res.status(400).json({ message: 'Nothing to cash out yet.' });
    }

    const { data: payoutRow, error: payoutInsertError } = await supabase
      .from('seller_payouts')
      .insert({
        seller_id: req.user.id,
        amount_cents: amountCents,
        status: 'pending',
      })
      .select('id')
      .single();
    if (payoutInsertError) throw payoutInsertError;

    const { data: updatedBalance, error: balanceError } = await supabase
      .from('seller_balances')
      .update({
        available_cents: available - amountCents,
        lifetime_paid_out_cents: (balance.lifetime_paid_out_cents || 0) + amountCents,
        updated_at: new Date().toISOString(),
      })
      .eq('seller_id', req.user.id)
      .select('seller_id, available_cents, pending_cents, lifetime_earned_cents, lifetime_paid_out_cents')
      .single();
    if (balanceError) throw balanceError;

    await supabase
      .from('seller_payouts')
      .update({
        status: 'paid',
        stripe_transfer_id: `square:${payoutRow.id}`,
        updated_at: new Date().toISOString(),
      })
      .eq('id', payoutRow.id);

    res.json({
      requiresOnboarding: false,
      amountCents,
      message: 'Cash out sent. Funds usually arrive in 1–2 business days.',
      status: {
        configured: true,
        connected: true,
        onboardingComplete: true,
        payoutsEnabled: true,
        chargesEnabled: true,
        detailsSubmitted: true,
        requiresAction: false,
        merchantId: connection.merchant_id,
        ...serializeBalance(updatedBalance),
      },
    });
  } catch (error) {
    console.error('Square cashout error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

async function squareWebhookHandler(req, res) {
  const rawBody = Buffer.isBuffer(req.body) ? req.body.toString('utf8') : JSON.stringify(req.body || {});
  const signature = req.headers['x-square-hmacsha256-signature'];
  const base = (process.env.PUBLIC_BASE_URL || 'http://localhost:5001').replace(/\/$/, '');
  const notificationUrl = process.env.SQUARE_WEBHOOK_NOTIFICATION_URL
    || `${base}/api/payments/square/webhook`;

  if (!square.verifyWebhookSignature(rawBody, signature, notificationUrl)) {
    return res.status(400).json({ error: 'Invalid Square webhook signature' });
  }

  let event;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return res.status(400).json({ error: 'Invalid JSON' });
  }

  try {
    const type = event.type || '';
    if (type === 'payment.updated' || type === 'payment.created') {
      const payment = event.data?.object?.payment || event.data?.object || {};
      if (payment.status === 'COMPLETED' && payment.id) {
        await fulfillSquarePayment(payment);
      }
    }
  } catch (err) {
    console.error('Square webhook handler error:', err);
    return res.status(500).json({ error: 'Webhook handler failed' });
  }

  res.json({ received: true });
}

async function fulfillSquarePayment(payment) {
  const supabase = getSupabaseAdmin();
  const paymentId = payment.id;
  const referenceId = payment.reference_id || payment.referenceId || null;

  let { data: requestRow, error } = referenceId
    ? await supabase
        .from('payment_requests')
        .select('id, product_id, seller_id, buyer_id, amount_cents, status, square_payment_id, provider')
        .eq('id', referenceId)
        .maybeSingle()
    : { data: null, error: null };

  if (error) throw error;

  if (!requestRow) {
    const byPayment = await supabase
      .from('payment_requests')
      .select('id, product_id, seller_id, buyer_id, amount_cents, status, square_payment_id, provider')
      .eq('square_payment_id', paymentId)
      .maybeSingle();
    if (byPayment.error) throw byPayment.error;
    requestRow = byPayment.data;
  }

  if (!requestRow) {
    console.warn('Square payment with no payment_request', paymentId);
    return;
  }

  await fulfillMeetupPayment({
    requestRow,
    productId: requestRow.product_id,
    sellerId: requestRow.seller_id,
    buyerId: requestRow.buyer_id,
    paymentId,
  });
}

module.exports = router;
module.exports.squareWebhookHandler = squareWebhookHandler;
