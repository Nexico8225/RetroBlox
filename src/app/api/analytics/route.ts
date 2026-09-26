import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { parseStatsSeries } from '@/lib/stats'

// Developer dashboard: per-game analytics for every game I published.
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const games = await db.game.findMany({
    where: { creatorId: user.id },
    include: {
      likes: true,
      _count: { select: { comments: true, favorites: true } },
    },
    orderBy: { createdAt: 'desc' },
  })

  const mapped = games.map((g) => {
    const likes = g.likes.filter((l) => l.value === 1).length
    const dislikes = g.likes.filter((l) => l.value === -1).length
    return {
      id: g.id,
      name: g.name,
      iconUrl: g.iconUrl,
      genre: g.genre,
      views: g.views,
      downloads: g.downloads,
      likes,
      dislikes,
      rating: likes + dislikes > 0 ? Math.round((likes / (likes + dislikes)) * 100) : null,
      favorites: g._count.favorites,
      comments: g._count.comments,
      series: parseStatsSeries(g.statsJson, 14),
      createdAt: g.createdAt,
    }
  })

  const totals = mapped.reduce(
    (acc, g) => ({
      games: acc.games + 1,
      views: acc.views + g.views,
      downloads: acc.downloads + g.downloads,
      likes: acc.likes + g.likes,
      dislikes: acc.dislikes + g.dislikes,
      favorites: acc.favorites + g.favorites,
      comments: acc.comments + g.comments,
    }),
    { games: 0, views: 0, downloads: 0, likes: 0, dislikes: 0, favorites: 0, comments: 0 }
  )

  return NextResponse.json({ games: mapped, totals })
}
