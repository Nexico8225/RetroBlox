import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { hashPassword, makeToken } from '@/lib/auth'
import { PLATFORM_CORS } from '@/lib/platform'

/**
 * PLATFORM SIGNUP — POST /api/platform/signup
 * Lets players create a RetroBlox account from INSIDE games (the Godot
 * player's Sign Up screen) with the same rules as the website: 3-20
 * characters (letters/numbers/spaces/underscore), password 3+ chars.
 * Returns a session token, so the game can immediately load the fresh
 * account's avatar via GET /api/platform/me — no website visit needed.
 */
export async function POST(req: NextRequest) {
  const body = (await req.json().catch(() => null)) as
    | { username?: string; password?: string; birthday?: string; gender?: string }
    | null
  const username = (body?.username || '').trim()
  const password = body?.password || ''

  // spaces are legal in usernames — same rule as the website form
  if (!/^[A-Za-z0-9_ ]{3,20}$/.test(username)) {
    return NextResponse.json(
      { error: 'Username must be 3-20 characters (letters, numbers, spaces, underscore).' },
      { status: 400, headers: PLATFORM_CORS }
    )
  }
  if (password.length < 3) {
    return NextResponse.json(
      { error: 'Password must be at least 3 characters.' },
      { status: 400, headers: PLATFORM_CORS }
    )
  }

  const existing = await db.user.findUnique({ where: { username } })
  if (existing) {
    return NextResponse.json(
      { error: 'That username is already taken!' },
      { status: 409, headers: PLATFORM_CORS }
    )
  }
  const lower = username.toLowerCase()
  const existingLower = await db.user.findUnique({ where: { usernameLower: lower } })
  if (existingLower) {
    return NextResponse.json(
      { error: 'That username is already taken (even with different capitals)!' },
      { status: 409, headers: PLATFORM_CORS }
    )
  }

  const gender = body?.gender === 'male' || body?.gender === 'female' ? body.gender : null
  const birthday = body?.birthday ? String(body.birthday).slice(0, 10) : null

  try {
    // short public player number — join order, same as the website signup
    const topNo = await db.user.aggregate({ _max: { playerNo: true } })
    const playerNo = (topNo._max.playerNo ?? 0) + 1

    const user = await db.user.create({
      data: {
        username,
        usernameLower: lower,
        playerNo,
        passwordHash: hashPassword(password),
        gender,
        birthday,
        lastSeen: new Date(),
      },
    })

    // signed stateless token + best-effort session row (read-only
    // serverless filesystems skip the row — the token still works)
    const token = makeToken(user.id)
    await db.session.create({ data: { token, userId: user.id } }).catch(() => {})

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
  } catch {
    // two players clicked Sign Up at the same moment with the same name
    return NextResponse.json(
      { error: 'That username was just taken — pick another one!' },
      { status: 409, headers: PLATFORM_CORS }
    )
  }
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
