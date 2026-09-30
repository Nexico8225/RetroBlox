import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { paymentsMode } from '@/lib/stripe'

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

/** POST /api/rbx/balance — RETIRED. Robux has left the economy: Tix is the
 *  only money on RetroBlox, so the currency exchange desk is closed for good.
 *  The route answers 410 Gone so old clients get a clear story. */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  return NextResponse.json(
    { error: 'The exchange desk is closed — RetroBlox runs on Tix now.' },
    { status: 410 }
  )
}
