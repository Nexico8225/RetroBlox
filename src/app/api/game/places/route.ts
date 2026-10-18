import { NextRequest, NextResponse } from 'next/server'
import { PLATFORM_CORS } from '@/lib/platform'
import { ensureBaseplate, activePresenceCounts, lazyGameGC } from '@/lib/places'

/**
 * PUBLIC GAME LIST — GET /api/game/places
 * The desktop player calls this right after login: the games the WEBSITE
 * hosts, with a live player count for each. Seeded with the classic
 * Baseplate on first call. No auth needed (like the old games page).
 */
export async function GET(_req: NextRequest) {
  try {
    const baseplate = await ensureBaseplate()
    // lazy GC on read paths keeps the tables clean with zero cron jobs
    lazyGameGC().catch(() => {})

    const counts = await activePresenceCounts()
    const places = [
      {
        slug: baseplate.slug,
        name: baseplate.name,
        description: baseplate.description,
        players: counts.get(baseplate.id) ?? 0,
        maxPlayers: baseplate.maxPlayers,
        active: baseplate.active,
        updatedAt: baseplate.updatedAt,
      },
    ]

    return NextResponse.json({ places }, { headers: PLATFORM_CORS })
  } catch (err) {
    console.error('[game/places] failed:', err)
    return NextResponse.json(
      { error: 'Could not load the game list' },
      { status: 500, headers: PLATFORM_CORS }
    )
  }
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
