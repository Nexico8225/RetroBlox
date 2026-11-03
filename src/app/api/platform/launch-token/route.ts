import { NextRequest, NextResponse } from 'next/server'
import { getUserFromReq, makeSignedToken } from '@/lib/auth'
import { PLATFORM_CORS } from '@/lib/platform'

/**
 * GET /api/platform/launch-token
 *
 * Generates a signed v2 Bearer token for the authenticated player.
 * Since the browser's `rb_session` cookie is httpOnly, the client
 * calls this endpoint right before triggering the `retroblox://play?...`
 * protocol URI so the desktop launcher receives a verified bearer token
 * to talk to the platform API (avatar, inventory, game passes).
 */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json(
      { ok: false, error: 'Unauthorized: log in to generate a launch token' },
      { status: 401, headers: PLATFORM_CORS }
    )
  }

  const token = makeSignedToken(user.id)
  return NextResponse.json(
    {
      ok: true,
      token,
      username: user.username,
      userId: user.id,
    },
    { headers: PLATFORM_CORS }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
