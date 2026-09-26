import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/** GET /api/rbx/transactions — this user's RBX ledger history (newest first). */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const transactions = await db.rbxTransaction.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: 'desc' },
    take: 100,
  })
  return NextResponse.json({ transactions, balance: user.rbxBalance })
}
