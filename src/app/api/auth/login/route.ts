import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { verifyPassword, makeToken, publicUser, setSessionCookie } from '@/lib/auth'
import { ensureTables, diagnoseDb } from '@/lib/dbdiag'

export async function POST(req: NextRequest) {
  // paramedic first: if the cloud database is reachable but EMPTY, this
  // creates all tables on the spot (idempotent, only touches empty DBs)
  await ensureTables()
  try {
    const body = await req.json()
    const username = String(body.username || '').trim()
    const password = String(body.password || '')

    // usernames log in case-insensitively (exact match first, then lower)
    // NOTE: "no such account" and "wrong password" are deliberately DIFFERENT
    // messages — when the owner tries to log in on a freshly deployed site,
    // "no account named X here" instantly tells them the cloud database is
    // empty (the signup never landed there), instead of a useless generic
    // "login failed" that could mean anything.
    let user = await db.user.findUnique({ where: { username } })
    if (!user) {
      user = await db.user.findUnique({ where: { usernameLower: username.toLowerCase() } })
    }
    if (!user) {
      return NextResponse.json(
        { error: `No account named "${username}" exists here yet — create one below!`, code: 'no_user' },
        { status: 401 }
      )
    }
    if (!verifyPassword(password, user.passwordHash)) {
      return NextResponse.json(
        { error: `Wrong password for "${user.username}" — try again.`, code: 'bad_password' },
        { status: 401 }
      )
    }

    // best-effort writes — on serverless hosts (Netlify) the filesystem is
    // read-only, so these can fail WITHOUT invalidating the login itself.
    // The token is self-contained and validates without either row.
    const lastSeen = new Date()
    await db.user
      .update({ where: { id: user.id }, data: { lastSeen } })
      .catch(() => {})

    const token = makeToken(user.id)
    await db.session
      .create({ data: { token, userId: user.id } })
      .catch(() => {})

    const res = NextResponse.json({ user: publicUser({ ...user, lastSeen }), token })
    setSessionCookie(res, req, token)
    return res
  } catch (e) {
    console.error('login error', e)
    // 99% of the time this is the database being unreachable (bad DATABASE_URL,
    // missing token, tables never created). Name the exact cause in the banner.
    const reason = await diagnoseDb()
    return NextResponse.json(
      {
        error: `The server could not reach the database. ${reason} (Full check: open /api/health.)`,
        code: 'server',
      },
      { status: 500 }
    )
  }
}
