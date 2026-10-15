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
    return NextResponse.json(
      { error: 'Username and password required', code: 'missing' },
      { status: 400, headers: PLATFORM_CORS }
    )
  }

  // v12.2: the SAME specific messages the website login gives — "no
  // account" and "wrong password" are DIFFERENT words now, so a mistyped
  // password can never again read as a mystery (the owner demanded this).
  let user = await db.user.findFirst({
    where: { OR: [{ username }, { usernameLower: username.toLowerCase() }] },
  })
  if (!user) {
    return NextResponse.json(
      {
        error: `No account named "${username}" exists here yet — create one on retro-blox.vercel.app!`,
        code: 'no_user',
      },
      { status: 401, headers: PLATFORM_CORS }
    )
  }
  if (!verifyPassword(password, user.passwordHash)) {
    return NextResponse.json(
      { error: `Wrong password for "${user.username}" — try again.`, code: 'bad_password' },
      { status: 401, headers: PLATFORM_CORS }
    )
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
      // short human PLAYER ID (#1, #2 ...) — join order, shown in-game
      seqId: typeof user.seqId === 'number' ? user.seqId : null,
      username: user.username,
      role: user.role,
    },
    { headers: PLATFORM_CORS }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
