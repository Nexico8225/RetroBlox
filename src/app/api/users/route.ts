import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

/**
 * GET /api/users?q=<name> — find players by name (case-insensitive "contains").
 * Short, public fields only: exactly what the Friends page search needs to
 * link you through to a profile (where the Trade button lives).
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
  const users = await db.user.findMany({
    where: {
      OR: [
        { username: { contains: q } },
        { usernameLower: { contains: q.toLowerCase() } },
      ],
    },
    orderBy: { createdAt: 'asc' },
    take: 20,
    select: { id: true, username: true, playerNo: true, avatarUrl: true, bio: true, createdAt: true, lastSeen: true },
  })
  return NextResponse.json({ users })
}
