import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { ensureNotificationSchema } from '@/lib/notifications'

/**
 * GET /api/notifications — my bell feed (latest 50) + unread count.
 * POST /api/notifications — { action: "read-all" } or { action: "read", id }
 */
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  await ensureNotificationSchema()

  const [rows, unread] = await Promise.all([
    db.notification.findMany({
      where: { userId: me.id },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: { actor: { select: { id: true, username: true, avatarUrl: true, createdAt: true, lastSeen: true } } },
    }),
    db.notification.count({ where: { userId: me.id, readAt: null } }),
  ])

  return NextResponse.json({
    notifications: rows.map((n) => ({
      id: n.id,
      type: n.type,
      title: n.title,
      body: n.body,
      linkUrl: n.linkUrl,
      createdAt: n.createdAt,
      read: !!n.readAt,
      actor: n.actor
        ? { id: n.actor.id, username: n.actor.username, avatarUrl: n.actor.avatarUrl }
        : null,
    })),
    unread,
  })
}

export async function POST(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  await ensureNotificationSchema()

  const body = (await req.json().catch(() => ({}))) as { action?: string; id?: string }
  if (body.action === 'read-all') {
    await db.notification.updateMany({
      where: { userId: me.id, readAt: null },
      data: { readAt: new Date() },
    })
    return NextResponse.json({ ok: true, unread: 0 })
  }
  if (body.action === 'read' && body.id) {
    await db.notification.updateMany({
      where: { id: body.id, userId: me.id, readAt: null },
      data: { readAt: new Date() },
    })
    const unread = await db.notification.count({ where: { userId: me.id, readAt: null } })
    return NextResponse.json({ ok: true, unread })
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
