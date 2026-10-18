import { NextRequest, NextResponse } from 'next/server'
import { randomUUID } from 'crypto'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { getStripe } from '@/lib/stripe'
import { ensurePackages, grantRbx } from '@/lib/rbx'

/**
 * POST /api/stripe/create-checkout-session
 * Body: { packageId } — and NOTHING else. The price and RBX amount are read
 * from the server's package row; whatever else the browser sends is ignored.
 * Returns only the Checkout URL. The secret key never leaves the server.
 */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = (await req.json().catch(() => ({}))) as { packageId?: unknown }
  const packageId = typeof body.packageId === 'string' ? body.packageId.trim() : ''
  if (!packageId) {
    return NextResponse.json({ error: 'Pick a Tix package first.' }, { status: 400 })
  }

  await ensurePackages()
  const pkg = await db.rbxPackage.findFirst({
    where: { OR: [{ id: packageId }, { code: packageId }], active: true },
  })
  if (!pkg) {
    return NextResponse.json({ error: 'That Tix package does not exist (or is not for sale right now).' }, { status: 400 })
  }

  let stripe
  try {
    stripe = getStripe()
  } catch (e) {
    // --------------------------------------------------------------
    // TEST BANK — no Stripe keys are configured, so the purchase
    // completes INSTANTLY with pretend money. Same ledger rules as the
    // real webhook: one Payment row, one idempotent grantRbx (the
    // unique stripeEventId means a double-click can never credit twice),
    // and the success page watches the balance land exactly like after
    // a real Stripe payment.
    // --------------------------------------------------------------
    console.warn('[stripe] not configured — completing purchase via the Test Bank')
    const sessionId = `testbank_${randomUUID()}`
    try {
      await db.payment.create({
        data: {
          userId: user.id,
          stripeCheckoutSessionId: sessionId,
          packageId: pkg.id,
          amountPaid: pkg.priceCents,
          currency: pkg.currency,
          status: 'succeeded',
        },
      })
      await grantRbx({
        userId: user.id,
        amount: pkg.rbxAmount,
        type: 'purchase',
        packageId: pkg.id,
        stripeEventId: `testbank_evt_${sessionId}`,
        stripePaymentIntentId: sessionId,
        note: `Test Bank — ${pkg.name}`,
      })
    } catch (grantErr) {
      console.error('[testbank] grant failed:', grantErr)
      return NextResponse.json({ error: 'The Test Bank could not credit your wallet. Try again.' }, { status: 500 })
    }
    return NextResponse.json({ url: `/purchase/success?session_id=${sessionId}`, testbank: true })
  }

  try {
    const origin = new URL(req.url).origin
    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: ['card'],
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: pkg.currency,
            unit_amount: pkg.priceCents,
            product_data: {
              name: `RetroBlox ${pkg.name}`,
              description: `${pkg.rbxAmount.toLocaleString('en-US')} Tix for ${user.username}`,
            },
          },
        },
      ],
      metadata: {
        userId: user.id,
        packageId: pkg.id,
        packageCode: pkg.code,
      },
      success_url: `${origin}/purchase/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${origin}/purchase/cancel`,
    })
    if (!session.url) {
      return NextResponse.json({ error: 'Stripe did not return a checkout URL.' }, { status: 502 })
    }

    // remember the attempt so the admin panel can show pending/abandoned checkouts
    await db.payment.upsert({
      where: { stripeCheckoutSessionId: session.id },
      update: { status: 'pending' },
      create: {
        userId: user.id,
        stripeCheckoutSessionId: session.id,
        packageId: pkg.id,
        amountPaid: pkg.priceCents,
        currency: pkg.currency,
        status: 'pending',
      },
    })

    return NextResponse.json({ url: session.url, sessionId: session.id })
  } catch (e) {
    console.error('[stripe] checkout session failed:', e)
    return NextResponse.json({ error: 'Could not start the Stripe checkout. Try again in a moment.' }, { status: 502 })
  }
}
