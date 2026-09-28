import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { publicUser } from '@/lib/auth'

/**
 * GET /api/users — the People directory: everyone who joined RetroBlox.
 *
 * Query params:
 *   q     — search usernames (case-insensitive contains)
 *   sort  — newest (default) | online | name | tix
 *   limit — max rows (default 60, cap 200)
 *
 * Public like profile pages: guests can browse the community too.
 * Each row carries the player's Tix balance (rbxBalance) + games count.
 */
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const q = (searchParams.get('q') || '').trim()
  const sort = searchParams.get('sort') || 'newest'
  const limit = Math.min(Math.max(Number(searchParams.get('limit')) || 60, 1), 200)

  const where = q ? { usernameLower: { contains: q.toLowerCase() } } : {}

  const orderBy =
    sort === 'online'
      ? [{ lastSeen: 'desc' as const }]
      : sort === 'name'
        ? [{ usernameLower: 'asc' as const }]
        : sort === 'tix'
          ? [{ rbxBalance: 'desc' as const }]
          : [{ createdAt: 'desc' as const }]

  const users = await db.user.findMany({
    where,
    orderBy,
    take: limit,
    include: {
      _count: { select: { games: true } },
      // their 3 newest games so the directory can show what they built
      games: { orderBy: { createdAt: 'desc' }, take: 3, select: { id: true, name: true, iconUrl: true } },
    },
  })

  return NextResponse.json({
    people: users.map((u) => ({
      ...publicUser(u),
      gamesCount: u._count.games,
      topGames: u.games.map((g) => ({ id: g.id, name: g.name, iconUrl: g.iconUrl })),
    })),
    total: users.length,
  })
}
