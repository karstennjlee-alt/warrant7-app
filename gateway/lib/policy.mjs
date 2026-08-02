/**
 * The deterministic policy. Plain code, no model involved.
 *
 * This is the whole safety argument: the decision does not depend on what the agent said, what
 * the customer wrote, or how persuasive either was. It depends on an integer.
 */
export const POLICY = {
  version: 14,
  resource: 'refund.create',
  currency: 'USD',
  auto_limit_minor: 50_000,      // $500.00
  block_limit_minor: 500_000,    // $5,000.00
  expiry_seconds: 120,
  readable_rule:
    'Automatically allow refunds up to $500. Ask me between $500 and $5,000. Always block refunds over $5,000.',
  updated_at: new Date(Date.now() - 86_400_000).toISOString()
};

export const ALLOW = 'ALLOW';
export const REVIEW = 'REVIEW';
export const BLOCK = 'BLOCK';

export function evaluate(amountMinor, policy = POLICY) {
  if (amountMinor <= policy.auto_limit_minor) return ALLOW;
  if (amountMinor <= policy.block_limit_minor) return REVIEW;
  return BLOCK;
}

export function money(minor, currency = 'USD') {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(minor / 100);
}

export function policyPayload(policy = POLICY) {
  return { ...policy, updated_at: policy.updated_at };
}
