import { createHmac, randomBytes, scryptSync, timingSafeEqual } from 'crypto'
import { db } from '@/lib/db'
import { NextRequest, NextResponse } from 'next/server'

/* ------------------------------------------------------------------
   STATELESS SIGNED SESSION TOKENS — the second half of the
   "nobody can log in on Netlify" fix.

   Old tokens were random strings stored in the Session TABLE. On
   serverless hosts every function instance gets its own EPHEMERAL
   copy of the bundled SQLite file, so a session row written by the
   login function may not exist for the /api/me function — instant
   "logged out" even though login returned 200.

   v2 tokens are SELF-CONTAINED: "v2.<base64url payload>.<hmac>".
   Verification = HMAC check + one User READ (works on a read-only
   filesystem, consistent across every instance). Legacy random
   tokens still validate through the Session table so existing
   browser sessions keep working on the real host.
------------------------------------------------------------------ */

const AUTH_SECRET =
  process.env.AUTH_SECRET || 'retroblox-auth-v2-blocky-secret-change-in-env'
const TOKEN_TTL_MS = 1000 * 60 * 60 * 24 * 180 // 180 days, matches the cookie

function signPayload(payload: string): string {
  return createHmac('sha256', AUTH_SECRET).update(payload).digest('base64url')
}

/** Self-contained signed token for a user id. */
export function makeSignedToken(userId: string): string {
  const payload = Buffer.from(
    JSON.stringify({ uid: userId, iat: Date.now() })
  ).toString('base64url')
  return `v2.${payload}.${signPayload(payload)}`
}

/** Verify a v2 token -> userId, or null if tampered/expired. */
function parseSignedToken(token: string): string | null {
  const parts = token.split('.')
  if (parts.length !== 3 || parts[0] !== 'v2' || !parts[1] || !parts[2]) return null
  const [, payload, sig] = parts
  const expected = signPayload(payload)
  const a = Buffer.from(sig)
  const b = Buffer.from(expected)
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as {
      uid?: string
      iat?: number
    }
    if (!data.uid || typeof data.iat !== 'number') return null
    if (Date.now() - data.iat > TOKEN_TTL_MS) return null
    return data.uid
  } catch {
    return null
  }
}

/**
 * Session cookie options that work EVERYWHERE:
 * - public https hosts (the preview panel embeds the site in a cross-site
 *   iframe, where SameSite=Lax cookies are silently dropped -> "not logged in")
 *   -> SameSite=None + Secure
 * - localhost dev -> classic Lax
 */
export function setSessionCookie(res: NextResponse, req: NextRequest, token: string) {
  const host = (req.headers.get('host') || '').toLowerCase()
  const isLocal = /^(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:\d+)?$/.test(host)
  res.cookies.set('rb_session', token, {
    httpOnly: true,
    sameSite: isLocal ? 'lax' : 'none',
    secure: !isLocal,
    path: '/',
    maxAge: 60 * 60 * 24 * 30,
  })
}

export function hashPassword(password: string): string {
  const salt = randomBytes(16).toString('hex')
  const hash = scryptSync(password, salt, 64).toString('hex')
  return `${salt}:${hash}`
}

export function verifyPassword(password: string, stored: string): boolean {
  const [salt, hash] = stored.split(':')
  if (!salt || !hash) return false
  const test = scryptSync(password, salt, 64)
  const orig = Buffer.from(hash, 'hex')
  return test.length === orig.length && timingSafeEqual(test, orig)
}

/**
 * Session token factory. Now takes the userId and returns a signed,
 * stateless token (see the block above for why). The optional Session
 * row is best-effort only — hosts with read-only filesystems skip it.
 */
export function makeToken(userId: string): string {
  return makeSignedToken(userId)
}

export async function getUserFromReq(req: NextRequest) {
  // token via cookie or Authorization header
  let token = req.cookies.get('rb_session')?.value || ''
  if (!token) {
    const auth = req.headers.get('authorization') || ''
    if (auth.startsWith('Bearer ')) token = auth.slice(7)
  }
  if (!token) return null

  // v2 signed tokens verify with ZERO database writes — serverless safe
  const uid = parseSignedToken(token)
  if (uid) {
    const u = await db.user.findUnique({ where: { id: uid } }).catch(() => null)
    return u || null
  }

  // legacy random tokens -> Session table (still works on a real host)
  const session = await db.session
    .findUnique({
      where: { token },
      include: { user: true },
    })
    .catch(() => null)
  return session?.user || null
}

export function isOnline(lastSeen: Date | string): boolean {
  const t = typeof lastSeen === 'string' ? new Date(lastSeen) : lastSeen
  return Date.now() - t.getTime() < 3 * 60 * 1000 // online within last 3 min
}

export function publicUser(u: {
  id: string
  username: string
  avatarUrl: string | null
  role?: string
  gender?: string | null
  bio?: string | null
  createdAt: Date | string
  lastSeen: Date | string
  rbxBalance?: number
  robuxBalance?: number
}) {
  return {
    id: u.id,
    username: u.username,
    avatarUrl: u.avatarUrl,
    role: u.role ?? 'user',
    gender: u.gender ?? null,
    bio: u.bio ?? '',
    createdAt: u.createdAt,
    lastSeen: u.lastSeen,
    online: isOnline(u.lastSeen),
    rbxBalance: typeof u.rbxBalance === 'number' ? u.rbxBalance : 0,
    robuxBalance: typeof u.robuxBalance === 'number' ? u.robuxBalance : 0,
  }
}
