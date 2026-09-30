import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { BADGES, BADGE_MAP, evaluateBadges, levelForXp } from '@/lib/badges'

/**
 * STEAM-STYLE PLAYER STATS — GET /api/users/{userId}/stats   (public)
 *
 * Everything the profile showcase needs in one shot:
 *   totalSeconds / weekSeconds   playtime totals (all time / last 2 weeks)
 *   recentlyPlayed               last-2-weeks per-game hours (Steam row)
 *   topPlayed                    all-time most played games
 *   badges                       every badge: unlocked state + rarity %
 *   xp / level / progress        account level driven by playtime + badges
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await db.user.findUnique({ where: { id }, select: { id: true, username: true, createdAt: true } })
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  // badges catch-up: cheap, guarantees the showcase is fresh even if a
  // milestone happened outside a playtime heartbeat
  await evaluateBadges(user.id)

  const twoWeeksAgo = new Date(Date.now() - 14 * 86400000)

  const [totals, weekAgg, gameAgg, badgeRows, userCount, favGame, distinctGames] = await Promise.all([
    db.gamePlay.aggregate({ where: { userId: id }, _sum: { seconds: true } }),
    db.playSession.aggregate({ where: { userId: id, lastBeatAt: { gte: twoWeeksAgo } }, _sum: { seconds: true } }),
    db.gamePlay.findMany({
      where: { userId: id },
      orderBy: [{ seconds: 'desc' }, { lastPlayedAt: 'desc' }],
      take: 12,
      include: { game: { select: { id: true, name: true, iconUrl: true, thumbnailUrl: true, genre: true } } },
    }),
    db.playerBadge.findMany({ where: { userId: id }, select: { badgeId: true, unlockedAt: true } }),
    db.user.count(),
    db.gamePlay.findFirst({
      where: { userId: id },
      orderBy: { lastPlayedAt: 'desc' },
      select: { game: { select: { id: true, name: true, iconUrl: true } } },
    }),
    db.gamePlay.count({ where: { userId: id } }),
  ])

  // no groupBy+orderBy(_sum) here either — that combo crashes on the libSQL
  // adapter in production; aggregate this player's week rows in JS instead
  const weekRows = await db.playSession.findMany({
    where: { userId: id, lastBeatAt: { gte: twoWeeksAgo } },
    select: { gameId: true, seconds: true },
  })
  const weekSecondsMap = new Map<string, number>()
  for (const r of weekRows) weekSecondsMap.set(r.gameId, (weekSecondsMap.get(r.gameId) || 0) + r.seconds)
  const weekGameRows = [...weekSecondsMap.entries()]
    .map(([gameId, seconds]) => ({ gameId, _sum: { seconds } }))
    .sort((a, b) => b._sum.seconds - a._sum.seconds)
    .slice(0, 10)

  const totalSecondsByGame = new Map(gameAgg.map((r) => [r.game.id, r.seconds]))
  const weekIds = weekGameRows.map((r) => r.gameId).filter((gid) => !totalSecondsByGame.has(gid))
  const extraWeekGames = weekIds.length
    ? await db.game.findMany({ where: { id: { in: weekIds } }, select: { id: true, name: true, iconUrl: true, thumbnailUrl: true, genre: true } })
    : []
  const metaById = new Map<string, { id: string; name: string; iconUrl: string | null; thumbnailUrl: string | null; genre: string }>()
  for (const r of gameAgg) metaById.set(r.game.id, r.game)
  for (const g of extraWeekGames) metaById.set(g.id, g)

  const weekSecondsByGame = new Map(weekGameRows.map((r) => [r.gameId, r._sum.seconds || 0]))

  const recentlyPlayed = weekGameRows.map((r) => {
    const meta = metaById.get(r.gameId)
    return {
      gameId: r.gameId,
      name: meta?.name || 'Unknown',
      iconUrl: meta?.iconUrl || null,
      thumbnailUrl: meta?.thumbnailUrl || null,
      genre: meta?.genre || '',
      weekSeconds: r._sum.seconds || 0,
      totalSeconds: totalSecondsByGame.get(r.gameId) || r._sum.seconds || 0,
    }
  })

  const topPlayed = gameAgg.slice(0, 6).map((r) => ({
    gameId: r.game.id,
    name: r.game.name,
    iconUrl: r.game.iconUrl,
    thumbnailUrl: r.game.thumbnailUrl,
    totalSeconds: r.seconds,
    playCount: r.playCount,
    firstPlayedAt: r.firstPlayedAt,
    lastPlayedAt: r.lastPlayedAt,
  }))

  // badge rarity = % of all accounts that own it
  const ownedMap = new Map(badgeRows.map((b) => [b.badgeId, b.unlockedAt]))
  const rarityRows = await db.playerBadge.groupBy({ by: ['badgeId'], _count: true })
  const rarityMap = new Map(rarityRows.map((r) => [r.badgeId, userCount > 0 ? Math.round(((r._count || 0) / userCount) * 100) : 0]))

  const badges = BADGES.map((def) => ({
    id: def.id,
    name: def.name,
    desc: def.desc,
    color: def.color,
    icon: def.icon,
    xp: def.xp,
    unlocked: ownedMap.has(def.id),
    unlockedAt: ownedMap.get(def.id) || null,
    rarityPct: rarityMap.get(def.id) || 0, // % of players who own it
  }))

  const badgeXp = badgeRows.reduce((sum, b) => sum + (BADGE_MAP[b.badgeId]?.xp || 0), 0)
  const totalSeconds = totals._sum.seconds || 0
  const xp = Math.floor(totalSeconds / 60) + badgeXp
  const level = levelForXp(xp)

  return NextResponse.json({
    username: user.username,
    totalSeconds,
    weekSeconds: weekAgg._sum.seconds || 0,
    gamesPlayed: distinctGames,
    recentlyPlayed,
    topPlayed,
    badges,
    xp,
    level: level.level,
    xpIntoLevel: level.xpIntoLevel,
    xpForNextLevel: level.xpForNextLevel,
    progressPct: level.progressPct,
    memberSince: user.createdAt,
    favoriteGame: favGame ? { id: favGame.game.id, name: favGame.game.name, iconUrl: favGame.game.iconUrl } : null,
  })
}
