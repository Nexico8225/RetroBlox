import { NextRequest, NextResponse } from 'next/server'
import { getUserFromReq } from '@/lib/auth'
import { getAvatarConfig, avatarPayload, enrichAvatarPayload, PLATFORM_CORS } from '@/lib/platform'

/**
 * CURRENT PLAYER — GET /api/platform/me   (Authorization: Bearer <token>)
 * The SDK calls this right after login: it returns the authenticated
 * RetroBlox user AND their account-wide avatar in one shot, so games
 * can go straight to spawning the local player. Enriched with the worn
 * BUNDLE, the active ANIMATION PACK and the account's EMOTES.
 */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json(
      { error: 'Invalid or expired token' },
      { status: 401, headers: PLATFORM_CORS }
    )
  }
  const cfg = await getAvatarConfig(user.id)
  const rigged = await enrichAvatarPayload(user.id, cfg)
  return NextResponse.json(
    {
      ...avatarPayload(user.id, user.username, cfg),
      ...rigged,
      role: user.role,
    },
    { headers: PLATFORM_CORS }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
