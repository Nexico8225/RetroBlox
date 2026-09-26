import { NextRequest, NextResponse } from 'next/server'
import type Stripe from 'stripe'
import { db } from '@/lib/db'
import { getStripe, webhookSecret } from '@/lib/stripe'
import { grantRbx, debitRbx } from '@/lib/rbx'

/**
 * POST /api/stripe/webhook — THE authority for granting RBX.
 * - reads the RAW body
 * - verifies the Stripe signature (STRIPE_WEBHOOK_SECRET) and rejects fakes
 * - is fully idempotent: a retried event can never credit twice
 *   (unique stripeEventId on the ledger + per-payment credited counters)
 * - handles: checkout.session.completed / .expired, refunds (full + partial),
 *   failed payment intents
 * The success page NEVER grants RBX — only this endpoint moves wallet balances
 * for purchases.
 */
export async function POST(req: NextRequest) {
  let stripe: Stripe
  let secret: string
  try {
    stripe = getStripe()
    secret = webhookSecret()
  } catch (e) {
    console.error('[stripe-webhook] not configured:', e)
    return NextResponse.json({ error: 'Webhooks are not configured.' }, { status: 500 })
  }

  const sig = req.headers.get('stripe-signature') || ''
  const raw = await req.text()

  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(raw, sig, secret)
  } catch {
    return NextResponse.json({ error: 'Invalid webhook signature.' }, { status: 400 })
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutCompleted(stripe, event)
        break
      case 'checkout.session.expired':
        await markSessionStatus(event.data.object.id, 'expired', event.id)
        break
      case 'payment_intent.payment_failed': {
        const intent = event.data.object
        const payment = await db.payment.findFirst({ where: { stripePaymentIntentId: intent.id } })
        if (payment && payment.status !== 'succeeded') {
          await db.payment.update({
            where: { id: payment.id },
            data: { status: 'failed', stripeEventId: event.id },
          })
        }
        break
      }
      case 'charge.refunded':
        await handleRefund(event)
        break
      default:
        // unhandled event types are acknowledged so Stripe stops retrying them
        break
    }
  } catch (e) {
    // only real failures return non-200 so Stripe retries us
    console.error(`[stripe-webhook] handler failed for ${event.type} (${event.id}):`, e)
    return NextResponse.json({ error: 'Handler error.' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}

/* ---------------- checkout completed ---------------- */

async function handleCheckoutCompleted(stripe: Stripe, event: Stripe.Event) {
  const session = event.data.object as Stripe.Checkout.Session
  const metadata = session.metadata || {}
  const userId = metadata.userId || ''
  const packageId = metadata.packageId || ''
  const intentId =
    typeof session.payment_intent === 'string'
      ? session.payment_intent
      : session.payment_intent?.id || null

  // resolve the package FIRST — an unknown/legacy packageId must never hit
  // the Payment.packageId foreign key, and it means "record money, grant none"
  const pkg = packageId ? await db.rbxPackage.findUnique({ where: { id: packageId } }) : null
  const safePackageId = pkg?.id || null

  let payment = await db.payment.findUnique({ where: { stripeCheckoutSessionId: session.id } })
  if (!payment) {
    payment = await db.payment.create({
      data: {
        userId: userId || null,
        stripeCheckoutSessionId: session.id,
        stripePaymentIntentId: intentId,
        packageId: safePackageId,
        amountPaid: session.amount_total ?? 0,
        currency: session.currency || 'usd',
        status: 'pending',
      },
    })
  }

  // asynchronous payment methods can complete as "unpaid" — wait for the paid state
  if (session.payment_status !== 'paid') {
    await db.payment.update({ where: { id: payment.id }, data: { stripeEventId: event.id } })
    return
  }

  // idempotency guard #1: this exact event already finished this payment
  if (payment.stripeEventId === event.id && payment.rbxCredited > 0) return
  // guard #2: a different event already credited this session
  if (payment.rbxCredited > 0 && payment.status === 'succeeded') {
    await db.payment.update({ where: { id: payment.id }, data: { stripeEventId: event.id } })
    return
  }

  const amountPaid = session.amount_total ?? pkg?.priceCents ?? payment.amountPaid

  await db.payment.update({
    where: { id: payment.id },
    data: {
      status: 'succeeded',
      stripePaymentIntentId: intentId,
      amountPaid,
      currency: session.currency || 'usd',
      stripeEventId: event.id,
    },
  })

  if (!userId || !pkg) {
    console.error(`[stripe-webhook] ${event.id}: paid session ${session.id} has no usable metadata — payment recorded, NO Tix granted`)
    return
  }

  // THE grant — idempotent by ledger stripeEventId (unique). Retries land in
  // the duplicate branch and change nothing.
  const res = await grantRbx({
    userId,
    amount: pkg.rbxAmount,
    type: 'purchase',
    note: `Bought ${pkg.name} ($${((session.amount_total ?? pkg.priceCents) / 100).toFixed(2)})`,
    packageId: pkg.id,
    stripeEventId: event.id,
    stripePaymentIntentId: intentId || undefined,
  })
  if (res.duplicate) return
  await db.payment.update({ where: { id: payment.id }, data: { rbxCredited: pkg.rbxAmount } })
}

/* ---------------- refunds (full + partial, replay-safe) ---------------- */

async function handleRefund(event: Stripe.Event) {
  const charge = event.data.object as Stripe.Charge
  const intentId =
    typeof charge.payment_intent === 'string' ? charge.payment_intent : charge.payment_intent?.id || null
  if (!intentId) {
    console.warn(`[stripe-webhook] ${event.id}: refund without a payment_intent — ignored`)
    return
  }
  const payment = await db.payment.findFirst({
    where: { stripePaymentIntentId: intentId },
    include: { package: true },
  })
  if (!payment) {
    console.warn(`[stripe-webhook] ${event.id}: refund for unknown payment ${intentId} — no local record to reverse`)
    return
  }

  // charge.amount_refunded is CUMULATIVE — only reverse what we haven't yet
  const refundedTotal = charge.amount_refunded ?? 0
  const deltaCents = Math.max(0, refundedTotal - payment.refundedCents)
  if (deltaCents === 0) return // replay of an already-processed refund state

  const totalPaid = charge.amount || payment.amountPaid || 0
  const reversibleRbx = Math.max(0, payment.rbxCredited - payment.rbxReversed)
  // partial refunds reverse their proportional slice; the moment the payment
  // is FULLY refunded we hand back everything that is still reversible
  // (proportional flooring would otherwise strand a few RBX forever)
  let rbxToReverse =
    totalPaid > 0 && refundedTotal >= totalPaid
      ? reversibleRbx
      : totalPaid > 0
        ? Math.floor((reversibleRbx * deltaCents) / totalPaid)
        : reversibleRbx
  rbxToReverse = Math.max(0, Math.min(rbxToReverse, reversibleRbx))

  let applied = 0
  if (rbxToReverse > 0 && payment.userId) {
    const res = await debitRbx({
      userId: payment.userId,
      amount: rbxToReverse,
      type: 'refund',
      note: `Refund $${(deltaCents / 100).toFixed(2)} on ${payment.package?.name || 'Tix purchase'}`,
      packageId: payment.packageId || undefined,
      stripeEventId: event.id,
      stripePaymentIntentId: intentId,
      clampToBalance: true, // never push a wallet negative — shortfall noted on the ledger
    })
    applied = res.applied
  }

  const status =
    totalPaid > 0 && refundedTotal >= totalPaid ? 'refunded' : 'partially_refunded'
  await db.payment.update({
    where: { id: payment.id },
    data: {
      refundedCents: refundedTotal,
      rbxReversed: payment.rbxReversed + applied,
      status,
      stripeEventId: event.id,
    },
  })
}

async function markSessionStatus(sessionId: string, status: string, eventId: string) {
  const payment = await db.payment.findUnique({ where: { stripeCheckoutSessionId: sessionId } })
  if (!payment) return
  if (payment.status === 'succeeded') return // never downgrade a paid session
  await db.payment.update({ where: { id: payment.id }, data: { status, stripeEventId: eventId } })
}
