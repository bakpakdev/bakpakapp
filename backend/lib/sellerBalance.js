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
  const balance = await getOrCreateSellerBalance(supabase, sellerId);
  const { data, error } = await supabase
    .from('seller_balances')
    .update({
      available_cents: (balance.available_cents || 0) + amountCents,
      lifetime_earned_cents: (balance.lifetime_earned_cents || 0) + amountCents,
      updated_at: new Date().toISOString(),
    })
    .eq('seller_id', sellerId)
    .select('seller_id, available_cents, pending_cents, lifetime_earned_cents, lifetime_paid_out_cents')
    .single();
  if (error) throw error;
  return data;
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
  serializeBalance,
};
