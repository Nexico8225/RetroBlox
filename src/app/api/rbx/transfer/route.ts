import { NextRequest, NextResponse } from 'next/server'
import { getUserFromReq } from '@/lib/auth'
import { transferRbx, RbxError } from '@/lib/rbx'

/**
 * POST /api/rbx/transfer — send Tix to another player.
 * Body: { to: string (username), amount: number, note?: string }
 * Both wallets move inside one atomic transaction with ledger rows on
 * both sides. The sender can never go below zero or send to themselves.
 */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = (await req.json().catch(() => ({}))) as {
    to?: unknown
    amount?: unknown
    note?: unknown
  }
  const to = typeof body.to === 'string' ? body.to.trim() : ''
  const amount = typeof body.amount === 'number' ? Math.floor(body.amount) : NaN
  const note = typeof body.note === 'string' ? body.note : undefined

  if (!to) return NextResponse.json({ error: 'Type who should get the Tix.' }, { status: 400 })
  if (!Number.isFinite(amount) || amount < 1) {
    return NextResponse.json({ error: 'Send at least 1 Tix (whole numbers only).' }, { status: 400 })
  }

  try {
    const res = await transferRbx({ fromUserId: user.id, toUsername: to, amount, note })
    return NextResponse.json({
      ok: true,
      balanceAfter: res.balanceAfter,
      recipient: res.recipient,
    })
  } catch (e) {
    if (e instanceof RbxError) {
      return NextResponse.json({ error: e.message }, { status: 400 })
    }
    console.error('[rbx/transfer] failed:', e)
    return NextResponse.json({ error: 'The transfer failed — try again in a moment.' }, { status: 500 })
  }
}
