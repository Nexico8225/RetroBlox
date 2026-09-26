import { NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { ensurePackages } from '@/lib/rbx'
import { paymentsMode, getStripe } from '@/lib/stripe'

/**
 * GET /api/rbx/packages — the active RBX packages for the store.
 * Only ids/codes/prices leave the server; buying sends a package id back and
 * the server re-reads the price itself.
 */
export async function GET(_req: Request) {
  await ensurePackages()
  const packages = await db.rbxPackage.findMany({
    where: { active: true },
    orderBy: [{ sortOrder: 'asc' }, { priceCents: 'asc' }],
    select: { id: true, code: true, name: true, rbxAmount: true, priceCents: true, currency: true },
  })
  // Is real Stripe configured? When it is not, checkout falls back to the
  // built-in Test Bank (instant, pretend money) — the store labels that.
  const stripeReady = await (async () => {
    try {
      getStripe()
      return true
    } catch {
      return false
    }
  })()
  return NextResponse.json({ packages, mode: paymentsMode(), bank: stripeReady ? 'stripe' : 'testbank' })
}
