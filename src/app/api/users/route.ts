import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser, isOnline } from '@/lib/auth'

/**
 * GET /api/users?q=wizard&limit=20 — PEOPLE SEARCH (site-wide).
 * Matches usernames (case-insensitive contains) and bios; returns the
 * classic card shape + online + seqId. Powers the Friends page search box.
 */
export async function GET(req: NextRequest) {
  const url = new URL(req.url)
  const q = (url.searchParams.get('q') || '').trim()
  const limit = Math.min(40, Math.max(1, Number(url.searchParams.get('limit')) || 20))
  const viewer = await getUserFromReq(req)

  if (!q) {
    // no query: the freshest faces (newest accounts first)
    const rows = await db.user.findMany({
      orderBy: { createdAt: 'desc' },
      take: limit,
    })
    return NextResponse.json({
      users: rows.map((u) => ({ ...publicUser(u), friendState: 'none' as const })),
      query: '',
    })
  }

  const rows = await db.user.findMany({
    where: {
      OR: [
        { username: { contains: q } },
        { usernameLower: { contains: q.toLowerCase() } },
        { bio: { contains: q } },
      ],
    },
    orderBy: { lastSeen: 'desc' },
    take: limit,
  })

  // friendship state between the viewer and every hit (for Add Friend buttons)
  let viewerFriendRows: { requesterId: string; addresseeId: string; status: string }[] = []
  if (viewer && rows.length > 0) {
    const ids = rows.map((r) => r.id)
    const [sent, recv] = await Promise.all([
      db.friendship.findMany({ where: { requesterId: viewer.id, addresseeId: { in: ids } } }),
      db.friendship.findMany({ where: { addresseeId: viewer.id, requesterId: { in: ids } } }),
    ])
    viewerFriendRows = [...sent, ...recv]
  }

  const users = rows
    .map((u) => {
      const base = publicUser(u)
      let friendState: 'none' | 'friends' | 'request_sent' | 'request_received' = 'none'
      if (viewer && u.id !== viewer.id) {
        const a = viewerFriendRows.find((f) => f.requesterId === viewer.id && f.addresseeId === u.id)
        const b = viewerFriendRows.find((f) => f.requesterId === u.id && f.addresseeId === viewer.id)
        if (a) friendState = a.status === 'accepted' ? 'friends' : 'request_sent'
        else if (b) friendState = b.status === 'accepted' ? 'friends' : 'request_received'
      }
      return { ...base, friendState, online: isOnline(u.lastSeen) }
    })
    // the searcher themselves never appears in their own results
    .filter((u) => u.id !== viewer?.id)

  return NextResponse.json({ users, query: q })
}
