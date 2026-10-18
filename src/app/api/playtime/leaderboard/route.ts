import { NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { levelForXp, BADGES } from '@/lib/badges'

/**
 * PLAYTIME LEADERBOARDS — GET /api/playtime/leaderboard
 * Steam-style "most played" boards for the community:
 *   ?window=week (last 7 days) | all (all time, default)
 * Returns top players by playtime + top games by playtime.
 *
 * NOTE: intentionally NO `groupBy` + `orderBy: { _sum }` here — that
 * combination crashes on the libSQL (Turso) adapter in production, so
 * the rows are aggregated in JS instead (the row counts are tiny).
 */
async function topSeconds(
  model: 'gamePlay' | 'playSession',
  where?: Record<string, unknown>
): Promise<{ players: Map<string, number>; games: Map<string, number> }> {
  const rows =
    model === 'gamePlay'
      ? await db.gamePlay.findMany({ where, select: { userId: true, gameId: true, seconds: true } })
      : await db.playSession.findMany({ where, select: { userId: true, gameId: true, seconds: true } })
  const players = new Map<string, number>()
  const games = new Map<string, number>()
  for (const r of rows) {
    players.set(r.userId, (players.get(r.userId) || 0) + r.seconds)
    games.set(r.gameId, (games.get(r.gameId) || 0) + r.seconds)
  }
  return { players, games }
}

/** keep the top 10 entries of an aggregated map */
function top10(m: Map<string, number>): { id: string; seconds: number }[] {
  return [...m.entries()]
    .map(([id, seconds]) => ({ id, seconds }))
    .sort((a, b) => b.seconds - a.seconds)
    .slice(0, 10)
}

export async function GET(req: Request) {
  const url = new URL(req.url)
  const window = url.searchParams.get('window') === 'week' ? 'week' : 'all'
  const since = new Date(Date.now() - 7 * 86400000)

  const { players: playerSeconds, games: gameSeconds } =
    window === 'week'
      ? await topSeconds('playSession', { lastBeatAt: { gte: since } })
      : await topSeconds('gamePlay')

  const topPlayers = top10(playerSeconds).map((p) => ({ userId: p.id, _sum: { seconds: p.seconds } }))
  const topGames = top10(gameSeconds).map((g) => ({ gameId: g.id, _sum: { seconds: g.seconds } }))
  return NextResponse.json(await decorate(topPlayers, topGames, window))
}

async function decorate(
  topPlayers: { userId: string; _sum: { seconds: number | null } }[],
  topGames: { gameId: string; _sum: { seconds: number | null } }[],
  window: string
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
