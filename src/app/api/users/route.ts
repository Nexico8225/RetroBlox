import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { publicUser } from '@/lib/auth'

// GET /api/users?limit=9 — PUBLIC: the most recently active blockheads
// (used by the home page "Meet the Blockheads" strip for guests) + how many are online right now
export async function GET(req: NextRequest) {
  const url = new URL(req.url)
  const limit = Math.min(Math.max(Number(url.searchParams.get('limit')) || 9, 1), 30)

  const [users, onlineCount] = await Promise.all([
    db.user.findMany({
      orderBy: { lastSeen: 'desc' },
      take: limit,
    }),
    db.user.count({ where: { lastSeen: { gte: new Date(Date.now() - 3 * 60 * 1000) } } }),
  ])

  return NextResponse.json({ users: users.map(publicUser), onlineCount })
}
