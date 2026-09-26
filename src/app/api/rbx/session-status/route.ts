import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * GET /api/rbx/session-status?session_id=...
 * Tells the success page whether THIS checkout already granted its Tix.
 * Works for both flows because both write the same Payment row:
 *  - the Stripe webhook marks the row succeeded after real payment
 *  - the Test Bank marks it succeeded instantly (no keys configured)
 * Without this, a page that mounts AFTER the grant (balance already
 * refreshed by the header) would poll forever waiting for an increase.
 */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const sessionId = req.nextUrl.searchParams.get('session_id')?.trim() || ''
  if (!sessionId) {
    return NextResponse.json({ error: 'Missing session_id' }, { status: 400 })
  }

  const payment = await db.payment.findFirst({
    where: {
      OR: [{ stripeCheckoutSessionId: sessionId }, { stripePaymentIntentId: sessionId }],
      userId: user.id,
    },
    select: {
      status: true,
      amountPaid: true,
      currency: true,
      package: { select: { name: true, rbxAmount: true } },
    },
  })

  if (!payment) {
    return NextResponse.json({ found: false, status: 'unknown' })
  }

  return NextResponse.json({
    found: true,
    status: payment.status,
    granted: payment.status === 'succeeded',
    packageName: payment.package?.name ?? null,
    tixAmount: payment.package?.rbxAmount ?? null,
  })
}
