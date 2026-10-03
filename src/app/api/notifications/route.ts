import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * GET  /api/notifications — my bell: newest 40 + the unread count
 * POST /api/notifications — { action: 'read' | 'read_all', id? }
 */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const [rows, unread] = await Promise.all([
    db.notification.findMany({ where: { userId: user.id }, orderBy: { createdAt: 'desc' }, take: 40 }),
    db.notification.count({ where: { userId: user.id, readAt: null } }),
  ])

  return NextResponse.json({
    unread,
    notifications: rows.map((n) => ({
      id: n.id,
      type: n.type,
      data: JSON.parse(n.dataJson || '{}'),
      read: n.readAt != null,
      createdAt: n.createdAt,
    })),
  })
}

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as { action?: string; id?: string }

  if (body.action === 'read_all') {
    await db.notification.updateMany({ where: { userId: user.id, readAt: null }, data: { readAt: new Date() } })
    return NextResponse.json({ ok: true })
  }
  if (body.action === 'read' && body.id) {
    await db.notification.updateMany({ where: { id: body.id, userId: user.id }, data: { readAt: new Date() } })
    return NextResponse.json({ ok: true })
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
