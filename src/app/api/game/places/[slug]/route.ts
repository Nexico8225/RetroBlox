import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { PLATFORM_CORS } from '@/lib/platform'
import { ensureBaseplate, parseMapData, activePresenceCounts } from '@/lib/places'

/**
 * GAME DOWNLOAD — GET /api/game/places/{slug}
 * The full map of one place, in studs. The desktop player builds the world
 * from THIS every launch — edit the place on the web and every player plays
 * the new version within one restart. `slug` is the stable id ("baseplate").
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params
  try {
    if (slug === 'baseplate') await ensureBaseplate()
    const place = await db.place.findUnique({ where: { slug } })
    if (!place || !place.active) {
      return NextResponse.json({ error: 'Game not found' }, { status: 404, headers: PLATFORM_CORS })
    }

    const counts = await activePresenceCounts()
    return NextResponse.json(
      {
        slug: place.slug,
        name: place.name,
        description: place.description,
        maxPlayers: place.maxPlayers,
        players: counts.get(place.id) ?? 0,
        updatedAt: place.updatedAt,
        data: parseMapData(place.dataJson),
      },
      { headers: PLATFORM_CORS }
    )
  } catch (err) {
    console.error('[game/places/slug] failed:', err)
    return NextResponse.json(
      { error: 'Could not load the game' },
      { status: 500, headers: PLATFORM_CORS }
    )
  }
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
