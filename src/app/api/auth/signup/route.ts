import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { hashPassword, makeToken, publicUser, setSessionCookie } from '@/lib/auth'
import { notifyEveryone } from '@/lib/notifications'

export async function POST(req: NextRequest) {
  try {
    const form = await req.formData()
    const username = String(form.get('username') || '').trim()
    const password = String(form.get('password') || '')
    const genderRaw = String(form.get('gender') || '')
    const gender = genderRaw === 'male' || genderRaw === 'female' ? genderRaw : null
    const birthday = form.get('birthday') ? String(form.get('birthday')) : null
    const bio = String(form.get('bio') || '').trim().slice(0, 300)

    // spaces are legal in usernames — "John Doe" is a perfectly good blockhead
    if (!/^[A-Za-z0-9_ ]{3,20}$/.test(username)) {
      return NextResponse.json(
        { error: 'Username must be 3-20 characters (letters, numbers, spaces, underscore).' },
        { status: 400 }
      )
    }
    if (password.length < 3) {
      return NextResponse.json({ error: 'Password must be at least 3 characters.' }, { status: 400 })
    }

    // a profile picture is OPTIONAL at signup — skip it and a letter avatar
    // stands in until you add one (no profile needed to sign up)
    const avatar = form.get('avatar')
    let avatarUrl: string | null = null
    if (avatar instanceof File && avatar.size > 0) {
      if (!avatar.type.startsWith('image/')) {
        return NextResponse.json({ error: 'Profile picture must be an image (PNG, JPG, GIF...).' }, { status: 400 })
      }
      if (avatar.size > 2 * 1024 * 1024) {
        return NextResponse.json({ error: 'Profile picture too large (max 2MB).' }, { status: 400 })
      }
      const buf = Buffer.from(await avatar.arrayBuffer())
      avatarUrl = `data:${avatar.type};base64,${buf.toString('base64')}`
    }

    // people can't have the same username — checked case-insensitively too
    const existing = await db.user.findUnique({ where: { username } })
    if (existing) {
      return NextResponse.json({ error: 'That username is already taken!' }, { status: 409 })
    }
    const lower = username.toLowerCase()
    const existingLower = await db.user.findUnique({ where: { usernameLower: lower } })
    if (existingLower) {
      return NextResponse.json({ error: 'That username is already taken (even with different capitals)!' }, { status: 409 })
    }

    // fresh, still-empty database? the first human to sign up becomes
    // the owner-admin (this is what happens right after you deploy to
    // a brand-new Turso cloud database — register FIRST, before sharing!)
    const userCount = await db.user.count()

    const user = await db.user.create({
      data: {
        username,
        usernameLower: lower,
        passwordHash: hashPassword(password),
        gender,
        birthday,
        bio,
        avatarUrl,
        role: userCount === 0 ? 'admin' : 'user',
        lastSeen: new Date(),
      },
    })
      .catch((e: unknown) => {
        // two people clicked Sign Up at the same moment with the same name —
        // Prisma unique violation P2002 -> friendly answer, not a 500
        if (
          e &&
          typeof e === 'object' &&
          'code' in e &&
          (e as { code?: string }).code === 'P2002'
        ) {
          return null
        }
        throw e
      })
    if (!user) {
      return NextResponse.json(
        { error: 'That username was just taken — pick another one!' },
        { status: 409 }
      )
    }

    // signed stateless token + best-effort session row (read-only
    // serverless filesystems skip the row — the token still works)
    const token = makeToken(user.id)
    await db.session.create({ data: { token, userId: user.id } }).catch(() => {})

    // tell the whole town a new blockhead walked in (bell feed for every
    // member; never blocks the signup itself)
    await notifyEveryone(
      {
        type: 'new_player',
        title: 'New player joined RetroBlox!',
        body: `${user.username} just joined — say hi and send them a friend request!`,
        linkUrl: `/users/${user.id}`,
        actorId: user.id,
      },
      user.id
    )

    const res = NextResponse.json({ user: publicUser(user), token })
    setSessionCookie(res, req, token)
    return res
  } catch (e) {
    console.error('signup error', e)
    return NextResponse.json({ error: 'Sign up failed. Try again.' }, { status: 500 })
  }
}
