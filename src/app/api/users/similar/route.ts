import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser, isOnline } from '@/lib/auth'

/* ------------------------------------------------------------------
   NAME-SIMILAR PLAYERS — "send a request to RetroBlox and RetroBloxian
   shows up, closest name on top."

   GET /api/users/similar?name=<typed>&exclude=<justRequestedId?>
   Ranks every eligible member by how close their username is to what
   you typed: prefix matches beat contains matches beat edit-distance
   matches; ties break by recency. Already friends / pending / the
   player you just requested are excluded. If barely anything matches,
   the newest members pad the strip so it is never empty.
------------------------------------------------------------------ */

/** classic edit-distance DP (usernames are <= 20 chars, cheap) */
function levenshtein(a: string, b: string): number {
  if (a === b) return 0
  if (!a.length) return b.length
  if (!b.length) return a.length
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i)
  for (let i = 1; i <= a.length; i++) {
    const cur = [i]
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(
        prev[j] + 1, // delete
        cur[j - 1] + 1, // insert
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1) // substitute
      )
    }
    prev = cur
  }
  return prev[b.length]
}

function sharedPrefixLen(a: string, b: string): number {
  let n = 0
  while (n < a.length && n < b.length && a[n] === b[n]) n++
  return n
}

export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const { searchParams } = new URL(req.url)
  const raw = (searchParams.get('name') || '').trim()
  const excludeId = searchParams.get('exclude') || ''
  if (raw.length < 2) return NextResponse.json({ similar: [] })

  const q = raw.toLowerCase()

  // nobody I already have a friendship row with (friends or pending,
  // either direction), plus me and the player just requested
  const rels = await db.friendship.findMany({
    where: { OR: [{ requesterId: me.id }, { addresseeId: me.id }] },
  })
  const excluded = new Set<string>([me.id])
  if (excludeId) excluded.add(excludeId)
  rels.forEach((r) => {
    excluded.add(r.requesterId)
    excluded.add(r.addresseeId)
  })

  const candidates = await db.user.findMany({
    where: { id: { notIn: [...excluded] } },
    orderBy: { lastSeen: 'desc' },
    take: 300,
  })

  const scored = candidates
    .map((u) => {
      const n = u.username.toLowerCase()
      let score = 0
      if (n === q) score = 1000
      else if (n.startsWith(q)) score = 500 - Math.max(0, n.length - q.length) * 3
      else if (q.startsWith(n)) score = 400 - Math.max(0, q.length - n.length) * 3
      else if (n.includes(q)) score = 300 - Math.abs(n.length - q.length)
      else if (q.includes(n)) score = 250
      else {
        const dist = levenshtein(q, n)
        const allow = Math.max(2, Math.floor(q.length / 3))
        if (dist <= allow) score = 200 - dist * 30
      }
      if (score > 0) score += Math.min(8, sharedPrefixLen(q, n)) * 2
      return { u, score }
    })
    .filter((s) => s.score > 0)
    .sort((a, b) => b.score - a.score || Number(isOnline(b.u.lastSeen)) - Number(isOnline(a.u.lastSeen)))

  const similar = scored
    .slice(0, 9)
    .map(({ u }) => ({
      ...publicUser(u),
      reason: `Name like "${raw}"`,
      mutuals: 0,
    }))

  // strip never looks broken — pad with the newest members
  if (similar.length < 3) {
    const have = new Set(similar.map((s) => s.id))
    const pad = candidates
      .filter((c) => !have.has(c.id))
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
      .slice(0, 9 - similar.length)
      .map((u) => ({ ...publicUser(u), reason: 'New to RetroBlox', mutuals: 0 }))
    return NextResponse.json({ similar: [...similar, ...pad] })
  }

  return NextResponse.json({ similar })
}
