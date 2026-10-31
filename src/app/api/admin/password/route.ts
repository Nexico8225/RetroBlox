import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, hashPassword, resolveUserIdParam, isUserAdmin } from '@/lib/auth'

async function requireAdmin(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return { error: NextResponse.json({ error: 'Login required' }, { status: 401 }) }
  if (!isUserAdmin(user)) return { error: NextResponse.json({ error: 'Admins only.' }, { status: 403 }) }
  return { user }
}

/**
 * ADMIN PASSWORD RESET — POST /api/admin/password
 * The owner's master key: admins can set any account's password (their own
 * included). Built because the admin account's password was set by the
 * create_admin script and the owner got locked out of their own game
 * client — now the Admin Panel can always fix a password in one field.
 * Body: { username?, newPassword } — the username resolves like every
 * /users/... route (exact id, exact name, or case-insensitive name).
 */
export async function POST(req: NextRequest) {
  const { error } = await requireAdmin(req)
  if (error) return error

  const body = (await req.json().catch(() => null)) as
    | { username?: string; newPassword?: string }
    | null
  const who = (body?.username || '').trim()
  const newPassword = body?.newPassword || ''
  if (!who) {
    return NextResponse.json({ error: 'Type the username to reset.' }, { status: 400 })
  }
  if (newPassword.length < 3) {
    return NextResponse.json(
      { error: 'New password must be at least 3 characters.' },
      { status: 400 }
    )
  }

  const targetId = await resolveUserIdParam(who)
  if (!targetId) {
    return NextResponse.json(
      { error: `No account named "${who}" exists here.` },
      { status: 404 }
    )
  }

  const target = await db.user.findUnique({ where: { id: targetId } })
  if (!target) {
    return NextResponse.json({ error: 'Account not found.' }, { status: 404 })
  }

  await db.user.update({
    where: { id: target.id },
    data: { passwordHash: hashPassword(newPassword) },
  })

  // every old session for this user dies — the new password is the only key
  await db.session.deleteMany({ where: { userId: target.id } }).catch(() => {})

  return NextResponse.json({
    ok: true,
    target: target.username,
    message: `Password for "${target.username}" is set. Log in with the new one everywhere (the game client included).`,
  })
}
