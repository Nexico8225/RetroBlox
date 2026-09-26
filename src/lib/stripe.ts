import Stripe from 'stripe'

/* ------------------------------------------------------------------
   STRIPE — SERVER-ONLY. Never import this from a client component.
   The secret key lives in .env.local (STRIPE_SECRET_KEY for test,
   STRIPE_LIVE_SECRET_KEY for live) and never leaves the server.
------------------------------------------------------------------ */

export type PaymentsMode = 'test' | 'live'

export function paymentsMode(): PaymentsMode {
  return (process.env.PAYMENTS_MODE || 'test').toLowerCase() === 'live' ? 'live' : 'test'
}

let client: Stripe | null = null
let clientKey = ''

/** Stripe client for the configured mode. Throws a human-readable error when unset. */
export function getStripe(): Stripe {
  const mode = paymentsMode()
  const key = mode === 'live' ? process.env.STRIPE_LIVE_SECRET_KEY : process.env.STRIPE_SECRET_KEY
  if (!key) {
    throw new Error(`Payments are not configured: PAYMENTS_MODE=${mode} but the ${mode} secret key is missing.`)
  }
  if (!client || clientKey !== key) {
    client = new Stripe(key)
    clientKey = key
  }
  return client
}

/** Webhook signing secret for the configured mode (test and live never mix). */
export function webhookSecret(): string {
  const mode = paymentsMode()
  const secret =
    mode === 'live' ? process.env.STRIPE_LIVE_WEBHOOK_SECRET : process.env.STRIPE_WEBHOOK_SECRET
  if (!secret) {
    throw new Error(`Webhooks are not configured: PAYMENTS_MODE=${mode} but the ${mode} webhook secret is missing.`)
  }
  return secret
}

export function formatUsd(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`
}
