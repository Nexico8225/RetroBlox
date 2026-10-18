import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function POST(req: NextRequest) {
  // kill the session via cookie OR Bearer token (iframe-safe logout)
  let token = req.cookies.get('rb_session')?.value || ''
  if (!token) {
    const auth = req.headers.get('authorization') || ''
    if (auth.startsWith('Bearer ')) token = auth.slice(7)
  }
  if (token) {
    await db.session.deleteMany({ where: { token } })
  }
  const res = NextResponse.json({ ok: true })
  res.cookies.set('rb_session', '', { path: '/', maxAge: 0 })
  return res
}
