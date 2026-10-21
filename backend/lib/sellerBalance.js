const BALANCE_COLUMNS = 'seller_id, available_cents, pending_cents, lifetime_earned_cents, lifetime_paid_out_cents';

/**
 * Compare-and-set on every counter we write, so a sale, a direct sale and a cash
 * out landing at once can't overwrite each other. Returns null if the row moved.
 */
async function updateIfUnchanged(supabase, balance, patch) {
  const { data, error } = await supabase
    .from('seller_balances')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('seller_id', balance.seller_id)
    .eq('available_cents', balance.available_cents || 0)
    .eq('lifetime_earned_cents', balance.lifetime_earned_cents || 0)
    .eq('lifetime_paid_out_cents', balance.lifetime_paid_out_cents || 0)
    .select(BALANCE_COLUMNS)
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function getOrCreateSellerBalance(supabase, sellerId) {
  const { data: existing, error } = await supabase
    .from('seller_balances')
    .select(BALANCE_COLUMNS)
    .eq('seller_id', sellerId)
    .maybeSingle();
  if (error) throw error;
  if (existing) return existing;

  const { data: created, error: insertError } = await supabase
    .from('seller_balances')
    .insert({ seller_id: sellerId })
    .select(BALANCE_COLUMNS)
    .single();
  if (insertError) throw insertError;
  return created;
}

async function creditSellerSale(supabase, sellerId, amountCents) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const balance = await getOrCreateSellerBalance(supabase, sellerId);
    const data = await updateIfUnchanged(supabase, balance, {
      available_cents: (balance.available_cents || 0) + amountCents,
      lifetime_earned_cents: (balance.lifetime_earned_cents || 0) + amountCents,
    });
    if (data) return data;
  }
  throw new Error(`Could not credit ${amountCents} cents to seller ${sellerId}`);
}

/**
 * A sale that was charged straight to the seller's Stripe account: it never
 * touches the popup balance, so it counts as earned and already paid out.
 */
async function recordDirectSale(supabase, sellerId, amountCents) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const balance = await getOrCreateSellerBalance(supabase, sellerId);
    const data = await updateIfUnchanged(supabase, balance, {
      lifetime_earned_cents: (balance.lifetime_earned_cents || 0) + amountCents,
      lifetime_paid_out_cents: (balance.lifetime_paid_out_cents || 0) + amountCents,
    });
    if (data) return data;
  }
  throw new Error(`Could not record direct sale of ${amountCents} cents for seller ${sellerId}`);
}

/**
 * Reserves `amountCents` of the seller's available balance for a cash out. Only
 * succeeds if the balance hasn't changed since it was read, so two taps can't
 * spend the same money twice. Returns null when the balance moved underneath us.
 */
async function reserveForPayout(supabase, balance, amountCents) {
  return updateIfUnchanged(supabase, balance, {
    available_cents: (balance.available_cents || 0) - amountCents,
    lifetime_paid_out_cents: (balance.lifetime_paid_out_cents || 0) + amountCents,
  });
}

/** Puts money back after a transfer failed or was reversed. */
async function releasePayout(supabase, sellerId, amountCents) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const balance = await getOrCreateSellerBalance(supabase, sellerId);
    const data = await updateIfUnchanged(supabase, balance, {
      available_cents: (balance.available_cents || 0) + amountCents,
      lifetime_paid_out_cents: Math.max(0, (balance.lifetime_paid_out_cents || 0) - amountCents),
    });
    if (data) return data;
  }
  throw new Error(`Could not release ${amountCents} cents back to seller ${sellerId}`);
}

function serializeBalance(balance = null) {
  return {
    availableCents: balance?.available_cents ?? 0,
    pendingCents: balance?.pending_cents ?? 0,
    lifetimeEarnedCents: balance?.lifetime_earned_cents ?? 0,
    lifetimePaidOutCents: balance?.lifetime_paid_out_cents ?? 0,
  };
}

module.exports = {
  getOrCreateSellerBalance,
  creditSellerSale,
  recordDirectSale,
  reserveForPayout,
  releasePayout,
  serializeBalance,
};
