import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

/**
 * GET /api/friends/suggested
 * "People You May Know" — similar players are ranked by:
 *   1. shared genre interests (games either of you published / liked / favorited)
 *   2. mutual friends
 *   3. same gender
 *   4. recent activity / newest members
 * Users already friends with or pending with are excluded.
 */
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  // genres I care about: my published games + anything I liked or favorited
  const genreWeight: Record<string, number> = {}
  const bump = (genre: string, by: number) => {
    if (genre) genreWeight[genre] = (genreWeight[genre] || 0) + by
  }
  const [myGames, myLikes, myFavs] = await Promise.all([
    db.game.findMany({ where: { creatorId: me.id }, select: { genre: true } }),
    db.gameLike.findMany({ where: { userId: me.id, value: 1 }, include: { game: { select: { genre: true } } } }),
    db.favorite.findMany({ where: { userId: me.id }, include: { game: { select: { genre: true } } } }),
  ])
  myGames.forEach((g) => bump(g.genre, 3))
  myLikes.forEach((l) => bump(l.game.genre, 2))
  myFavs.forEach((f) => bump(f.game.genre, 2))

  // all accepted friendships -> adjacency for mutual counting + exclusion set
  const allFriendships = await db.friendship.findMany({ where: { status: 'accepted' } })
  const adj = new Map<string, Set<string>>()
  const ensure = (id: string) => {
    if (!adj.has(id)) adj.set(id, new Set())
    return adj.get(id)!
  }
  for (const f of allFriendships) {
    ensure(f.requesterId).add(f.addresseeId)
    ensure(f.addresseeId).add(f.requesterId)
  }
  const myFriends = adj.get(me.id) || new Set<string>()

  // exclude me + anyone I already have a relationship with (either direction, any status)
  const rels = await db.friendship.findMany({
    where: { OR: [{ requesterId: me.id }, { addresseeId: me.id }] },
  })
  const excluded = new Set<string>([me.id])
  rels.forEach((r) => {
    excluded.add(r.requesterId)
    excluded.add(r.addresseeId)
  })

  const candidates = await db.user.findMany({
    where: { id: { notIn: [...excluded] }, role: { not: 'admin' } },
    include: { games: { select: { genre: true } } },
    orderBy: { lastSeen: 'desc' },
    take: 200,
  })

  const now = Date.now()
  const scored = candidates.map((u) => {
    const mutuals = [...(adj.get(u.id) || [])].filter((id) => myFriends.has(id))
    const sharedGenres = new Set<string>()
    let genreScore = 0
    for (const g of u.games) {
      const w = genreWeight[g.genre]
      if (w) {
        genreScore += w
        sharedGenres.add(g.genre)
      }
    }
    const daysOld = (now - new Date(u.createdAt).getTime()) / 86400000
    let score = mutuals.length * 10 + genreScore * 1.5
    if (u.gender && me.gender && u.gender === me.gender) score += 2
    if (daysOld < 2) score += 3 // fresh members are interesting
    score += (u.games.length || 0) * 0.5

    let reason: string
    if (sharedGenres.size > 0) {
      const top = [...sharedGenres][0]
      reason = u.games.length > 0 ? `Also into ${top} games` : `Likes ${top} games`
    } else if (mutuals.length > 0) {
      reason = `${mutuals.length} mutual friend${mutuals.length > 1 ? 's' : ''}`
    } else if (daysOld < 2) {
      reason = 'New to RetroBlox'
    } else {
      reason = 'Plays on RetroBlox'
    }

    return {
      ...publicUser(u),
      reason,
      mutuals: mutuals.length,
      score,
    }
  })

  scored.sort(
    (a, b) => b.score - a.score || new Date(b.lastSeen).getTime() - new Date(a.lastSeen).getTime()
  )

  return NextResponse.json({ suggested: scored.slice(0, 12) })
}
