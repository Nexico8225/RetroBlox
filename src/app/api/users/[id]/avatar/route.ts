import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getAvatarConfig, avatarPayload, enrichAvatarPayload, PLATFORM_CORS } from '@/lib/platform'

/**
 * PUBLIC PLATFORM API — GET /api/users/{userId}/avatar
 * The one endpoint every RetroBlox game uses to spawn a player with
 * their account-wide avatar. Public on purpose (like classic Roblox
 * avatar pages) — it only ever returns asset IDs, never credentials.
 * The enriched payload also carries the worn BUNDLE (body replacement),
 * the active ANIMATION PACK (realtime idle/walk/jump/climb override)
 * and the account's EMOTES so games can play them on demand.
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await db.user.findUnique({
    where: { id },
    select: { id: true, username: true },
  })
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  const cfg = await getAvatarConfig(user.id)
  const rigged = await enrichAvatarPayload(user.id, cfg)
  return NextResponse.json(
    { ...avatarPayload(user.id, user.username, cfg), ...rigged },
    {
      headers: {
        ...PLATFORM_CORS,
        // avatars change rarely — let the SDK/CDN cache for a minute
        'Cache-Control': 'public, max-age=60',
      },
    }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
