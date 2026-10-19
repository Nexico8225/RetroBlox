import { NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { resolveUserIdParam } from '@/lib/auth'
import { PLATFORM_CORS } from '@/lib/platform'

/**
 * PUBLIC PLATFORM API — GET /api/users/{userId}/pfp   (v9.0)
 * The one LIGHWEIGHT call the game client uses to fetch any player's
 * PROFILE PICTURE (the face they set on retro-blox.vercel.app). Public
 * on purpose — it only ever returns the username and the avatarUrl
 * (a data-URL or file URL), never credentials. {userId} accepts the
 * user id, the username (any casing) or "me".
 */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const userId = await resolveUserIdParam(id)
  const user = userId
    ? await db.user.findUnique({
        where: { id: userId },
        select: { id: true, username: true, avatarUrl: true },
      })
    : null
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  return NextResponse.json(
    { userId: user.id, username: user.username, avatarUrl: user.avatarUrl ?? null },
    { headers: PLATFORM_CORS }
  )
}
