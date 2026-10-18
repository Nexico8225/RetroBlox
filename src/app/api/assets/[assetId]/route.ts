import { NextRequest, NextResponse } from 'next/server'
import { resolveAsset, PLATFORM_CORS } from '@/lib/platform'

/**
 * ASSET SERVICE — GET /api/assets/{assetId}
 * Resolves asset IDs (body_01, head_03, hat_15 ...) into what a game
 * actually renders: a color for body/shirt/pants defaults, an image
 * for faces / hats / gear / UGC. This is the "CDN" the Unity SDK
 * downloads from — heavily cacheable, CORS-open.
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ assetId: string }> }) {
  const { assetId } = await params
  const asset = await resolveAsset(assetId)
  if (!asset) return NextResponse.json({ error: 'Asset not found' }, { status: 404 })

  return NextResponse.json(
    { asset },
    {
      headers: {
        ...PLATFORM_CORS,
        // UGC images are immutable (deleting publishes a new assetId) — cache hard
        'Cache-Control': 'public, max-age=86400, stale-while-revalidate=604800',
      },
    }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
