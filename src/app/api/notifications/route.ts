import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * GET  /api/notifications — the latest notifications + unread count
 * POST /api/notifications — { action: "read", id } mark one read
 *                           { action: "read_all" } mark everything read
 */
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const [items, unread] = await Promise.all([
    db.notification.findMany({
      where: { userId: me.id },
      orderBy: { createdAt: 'desc' },
      take: 40,
    }),
    db.notification.count({ where: { userId: me.id, readAt: null } }),
  ])
  return NextResponse.json({ items, unread })
}

export async function POST(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
  const action = String(body.action || '')

  if (action === 'read') {
    const id = String(body.id || '')
    await db.notification.updateMany({ where: { id, userId: me.id }, data: { readAt: new Date() } })
    return NextResponse.json({ ok: true })
  }
  if (action === 'read_all') {
    await db.notification.updateMany({ where: { userId: me.id, readAt: null }, data: { readAt: new Date() } })
    return NextResponse.json({ ok: true })
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
