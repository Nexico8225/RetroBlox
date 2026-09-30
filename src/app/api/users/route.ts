import { NextRequest, NextResponse } from 'next/server'
import { Prisma } from '@prisma/client'
import { db } from '@/lib/db'

/**
 * GET /api/users?q=<name|number> — find players by name (case-insensitive
 * "contains") or by their short numeric ID (typing "1" finds player #1).
 * Short, public fields only: exactly what the Friends page search and the
 * Players directory need to link you through to a profile (where the Trade
 * button lives).
 */
export async function GET(req: NextRequest) {
  const q = (new URL(req.url).searchParams.get('q') || '').trim().slice(0, 40)
  if (!q) {
    // no query: suggest the newest members instead of an empty wall
    const newest = await db.user.findMany({
      orderBy: { createdAt: 'desc' },
      take: 12,
      select: { id: true, username: true, playerNo: true, avatarUrl: true, bio: true, createdAt: true, lastSeen: true },
    })
    return NextResponse.json({ users: newest })
  }
  // "#12" / "#12" / "12" — a bare number (or #number) also matches player IDs
  const numberQuery = q.replace(/^#/, '')
  const asNumber = /^\d{1,9}$/.test(numberQuery) ? Number(numberQuery) : null
  const users = await db.user.findMany({
    where: {
      OR: [
        { username: { contains: q } },
        { usernameLower: { contains: q.toLowerCase() } },
        ...(asNumber != null
          ? [{ playerNo: asNumber } as Prisma.UserWhereInput]
          : []),
      ],
    },
    orderBy: { createdAt: 'asc' },
    take: 20,
    select: { id: true, username: true, playerNo: true, avatarUrl: true, bio: true, createdAt: true, lastSeen: true },
  })
  return NextResponse.json({ users })
}
