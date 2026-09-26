import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { verifyPassword, makeToken } from '@/lib/auth'
import { PLATFORM_CORS } from '@/lib/platform'

/**
 * PLATFORM AUTH — POST /api/platform/login
 * How games (the Unity RetroBlox SDK) sign a player in WITHOUT ever
 * seeing the database: exchange username + password for a session
 * token, then call the avatar / game-data APIs with `Authorization:
 * Bearer <token>`. The API validates everything; Unity gets JSON.
 */
export async function POST(req: NextRequest) {
  const body = (await req.json().catch(() => null)) as
    | { username?: string; password?: string }
    | null
  const username = (body?.username || '').trim()
  const password = body?.password || ''
  if (!username || !password) {
    return NextResponse.json({ error: 'Username and password required' }, { status: 400 })
  }

  const user = await db.user.findFirst({
    where: { OR: [{ username }, { usernameLower: username.toLowerCase() }] },
  })
  // same generic message for unknown user + wrong password
  if (!user || !verifyPassword(password, user.passwordHash)) {
    return NextResponse.json({ error: 'Incorrect username or password' }, { status: 401 })
  }

  // Best-effort session row: on serverless hosts the filesystem is
  // read-only, so this write may fail — the token below is signed and
  // self-contained, so the login is still 100% valid without it.
  const token = makeToken(user.id)
  await db.session
    .create({ data: { token, userId: user.id } })
    .catch(() => {})

  return NextResponse.json(
    {
      ok: true,
      token,
      userId: user.id,
      username: user.username,
      role: user.role,
    },
    { headers: PLATFORM_CORS }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
