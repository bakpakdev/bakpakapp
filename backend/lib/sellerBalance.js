async function getOrCreateSellerBalance(supabase, sellerId) {
  const { data: existing, error } = await supabase
    .from('seller_balances')
    .select('seller_id, available_cents, pending_cents, lifetime_earned_cents, lifetime_paid_out_cents')
    .eq('seller_id', sellerId)
    .maybeSingle();
  if (error) throw error;
  if (existing) return existing;

  const { data: created, error: insertError } = await supabase
    .from('seller_balances')
    .insert({ seller_id: sellerId })
    .select('seller_id, available_cents, pending_cents, lifetime_earned_cents, lifetime_paid_out_cents')
    .single();
  if (insertError) throw insertError;
  return created;
}

async function creditSellerSale(supabase, sellerId, amountCents) {
  // Compare-and-set so two sales landing at once don't overwrite each other.
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const balance = await getOrCreateSellerBalance(supabase, sellerId);
    const { data, error } = await supabase
      .from('seller_balances')
      .update({
        available_cents: (balance.available_cents || 0) + amountCents,
        lifetime_earned_cents: (balance.lifetime_earned_cents || 0) + amountCents,
        updated_at: new Date().toISOString(),
      })
      .eq('seller_id', sellerId)
      .eq('available_cents', balance.available_cents || 0)
      .select('seller_id, available_cents, pending_cents, lifetime_earned_cents, lifetime_paid_out_cents')
      .maybeSingle();
    if (error) throw error;
    if (data) return data;
  }
  throw new Error(`Could not credit ${amountCents} cents to seller ${sellerId}`);
}

const BALANCE_COLUMNS = 'seller_id, available_cents, pending_cents, lifetime_earned_cents, lifetime_paid_out_cents';

/**
 * Reserves `amountCents` of the seller's available balance for a cash out. Only
 * succeeds if the balance hasn't changed since it was read, so two taps can't
 * spend the same money twice. Returns null when the balance moved underneath us.
 */
async function reserveForPayout(supabase, balance, amountCents) {
  const { data, error } = await supabase
    .from('seller_balances')
    .update({
      available_cents: (balance.available_cents || 0) - amountCents,
      lifetime_paid_out_cents: (balance.lifetime_paid_out_cents || 0) + amountCents,
      updated_at: new Date().toISOString(),
    })
    .eq('seller_id', balance.seller_id)
    .eq('available_cents', balance.available_cents || 0)
    .select(BALANCE_COLUMNS)
    .maybeSingle();
  if (error) throw error;
  return data;
}

/** Puts money back after a transfer failed or was reversed. */
async function releasePayout(supabase, sellerId, amountCents) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const balance = await getOrCreateSellerBalance(supabase, sellerId);
    const { data, error } = await supabase
      .from('seller_balances')
      .update({
        available_cents: (balance.available_cents || 0) + amountCents,
        lifetime_paid_out_cents: Math.max(0, (balance.lifetime_paid_out_cents || 0) - amountCents),
        updated_at: new Date().toISOString(),
      })
      .eq('seller_id', sellerId)
      .eq('available_cents', balance.available_cents || 0)
      .select(BALANCE_COLUMNS)
      .maybeSingle();
    if (error) throw error;
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
  reserveForPayout,
  releasePayout,
  serializeBalance,
};
