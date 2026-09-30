import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { paymentsMode } from '@/lib/stripe'
import { MarketError, exchangeCurrency } from '@/lib/market'

/** GET /api/rbx/balance — the server-side wallet balances for the logged-in user. */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  return NextResponse.json({
    balance: user.rbxBalance,
    robux: user.robuxBalance,
    mode: paymentsMode(),
  })
}

/** POST /api/rbx/balance — the currency exchange desk.
 *  { direction: "tix_to_robux" | "robux_to_tix", amount } — the old-school
 *  10:1 desk (and 9:1 back). One transaction, both ledger rows, no house
 *  edge games beyond the spread. */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
  const direction = String(body.direction || '')
  const amount = Math.floor(Number(body.amount) || 0)

  if (direction !== 'tix_to_robux' && direction !== 'robux_to_tix') {
    return NextResponse.json({ error: 'Pick a direction at the exchange desk.' }, { status: 400 })
  }
  if (amount < 1) {
    return NextResponse.json({ error: 'Enter an amount of at least 1.' }, { status: 400 })
  }
  if (amount > 1_000_000_000) {
    return NextResponse.json({ error: 'That is beyond what the desk will count in one day.' }, { status: 400 })
  }

  try {
    const result = await db.$transaction(async (tx) => exchangeCurrency(tx, user.id, direction, amount))
    return NextResponse.json({
      ok: true,
      message: direction === 'tix_to_robux'
        ? `Exchanged T$ ${result.tix.toLocaleString('en-US')} → R$ ${result.robux.toLocaleString('en-US')}.`
        : `Exchanged R$ ${result.robux.toLocaleString('en-US')} → T$ ${result.tix.toLocaleString('en-US')}.`,
      balanceAfter: result.tixChange,
      robuxAfter: result.robuxAfter,
    })
  } catch (e) {
    if (e instanceof MarketError) return NextResponse.json({ error: e.message }, { status: 400 })
    throw e
  }
}
