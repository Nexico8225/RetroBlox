import { NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { levelForXp, BADGES } from '@/lib/badges'

/**
 * PLAYTIME LEADERBOARDS — GET /api/playtime/leaderboard
 * Steam-style "most played" boards for the community:
 *   ?window=week (last 7 days) | all (all time, default)
 * Returns top players by playtime + top games by playtime.
 */
export async function GET(req: Request) {
  const url = new URL(req.url)
  const window = url.searchParams.get('window') === 'week' ? 'week' : 'all'
  const since = new Date(Date.now() - 7 * 86400000)

  if (window === 'week') {
    const topPlayers = await db.playSession.groupBy({
      by: ['userId'],
      where: { lastBeatAt: { gte: since } },
      _sum: { seconds: true },
      orderBy: { _sum: { seconds: 'desc' } },
      take: 10,
    })
    const topGames = await db.playSession.groupBy({
      by: ['gameId'],
      where: { lastBeatAt: { gte: since } },
      _sum: { seconds: true },
      orderBy: { _sum: { seconds: 'desc' } },
      take: 10,
    })
    return NextResponse.json(await decorate(topPlayers, topGames))
  }

  const topPlayers = await db.gamePlay.groupBy({
    by: ['userId'],
    _sum: { seconds: true },
    orderBy: { _sum: { seconds: 'desc' } },
    take: 10,
  })
  const topGames = await db.gamePlay.groupBy({
    by: ['gameId'],
    _sum: { seconds: true },
    orderBy: { _sum: { seconds: 'desc' } },
    take: 10,
  })
  return NextResponse.json(await decorate(topPlayers, topGames))
}

async function decorate(
  topPlayers: { userId: string; _sum: { seconds: number | null } }[],
  topGames: { gameId: string; _sum: { seconds: number | null } }[]
) {
  const [users, games, badgeRows] = await Promise.all([
    db.user.findMany({
      where: { id: { in: topPlayers.map((p) => p.userId) } },
      select: { id: true, username: true, avatarUrl: true, role: true },
    }),
    db.game.findMany({
      where: { id: { in: topGames.map((g) => g.gameId) } },
      select: { id: true, name: true, iconUrl: true, thumbnailUrl: true, genre: true, creator: { select: { username: true } } },
    }),
    db.playerBadge.findMany({ select: { userId: true, badgeId: true } }),
  ])

  const userMap = new Map(users.map((u) => [u.id, u]))
  const gameMap = new Map(games.map((g) => [g.id, g]))
  const badgeXpMap = Object.fromEntries(BADGES.map((b) => [b.id, b.xp]))
  const badgeCount = new Map<string, number>()
  for (const row of badgeRows) badgeCount.set(row.userId, (badgeCount.get(row.userId) || 0) + 1)

  const players = topPlayers
    .filter((p) => userMap.has(p.userId))
    .map((p) => {
      const u = userMap.get(p.userId)!
      const xp = Math.floor((p._sum.seconds || 0) / 60) + badgeRows.filter((b) => b.userId === p.userId).reduce((s, b) => s + (badgeXpMap[b.badgeId] || 0), 0)
      return {
        userId: p.userId,
        username: u.username,
        avatarUrl: u.avatarUrl,
        role: u.role,
        seconds: p._sum.seconds || 0,
        badgeCount: badgeCount.get(p.userId) || 0,
        level: levelForXp(xp).level,
      }
    })

  const gameList = topGames
    .filter((g) => gameMap.has(g.gameId))
    .map((g) => {
      const meta = gameMap.get(g.gameId)!
      return {
        gameId: g.gameId,
        name: meta.name,
        iconUrl: meta.iconUrl,
        thumbnailUrl: meta.thumbnailUrl,
        genre: meta.genre,
        creator: meta.creator.username,
        seconds: g._sum.seconds || 0,
      }
    })

  return { window, players, games }
}
