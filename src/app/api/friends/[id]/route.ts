import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { notifyUser, ensureNotificationSchema } from '@/lib/notifications'

const NUDGE_COOLDOWN_MS = 10 * 60 * 1000 // one nudge per 10 minutes per request

// POST { action: "accept" | "decline" | "remove" | "cancel" | "nudge" }
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const friendship = await db.friendship.findUnique({ where: { id } })
  if (!friendship) return NextResponse.json({ error: 'Friendship not found' }, { status: 404 })
  if (friendship.requesterId !== me.id && friendship.addresseeId !== me.id) {
    return NextResponse.json({ error: 'Not your friendship' }, { status: 403 })
  }

  const body = await req.json()
  const action = String(body.action || '')

  if (action === 'accept') {
    if (friendship.addresseeId !== me.id) {
      return NextResponse.json({ error: 'Only the recipient can accept' }, { status: 403 })
    }
    await db.friendship.update({ where: { id }, data: { status: 'accepted' } })
    await notifyUser(friendship.requesterId, {
      type: 'friend_accepted',
      title: `${me.username} accepted your friend request!`,
      body: 'You can chat with each other now.',
      linkUrl: `/chat/${me.id}`,
      actorId: me.id,
    })
    return NextResponse.json({ ok: true })
  }

  if (action === 'decline' || action === 'remove' || action === 'cancel') {
    await db.friendship.delete({ where: { id } })
    return NextResponse.json({ ok: true })
  }

  // NUDGE — the sender of a still-pending request taps the other player
  // on the shoulder ("accept my request!"). Rate-limited so it stays a
  // friendly poke, not spam: one nudge per 10 minutes per friendship.
  if (action === 'nudge') {
    if (friendship.requesterId !== me.id) {
      return NextResponse.json({ error: 'Only the sender can nudge a request.' }, { status: 403 })
    }
    if (friendship.status !== 'pending') {
      return NextResponse.json({ error: 'That request is not pending anymore.' }, { status: 400 })
    }
    await ensureNotificationSchema()
    const last = await db.notification.findFirst({
      where: { type: 'nudge', actorId: me.id, userId: friendship.addresseeId },
      orderBy: { createdAt: 'desc' },
    })
    if (last) {
      const waited = Date.now() - new Date(last.createdAt).getTime()
      if (waited < NUDGE_COOLDOWN_MS) {
        const mins = Math.max(1, Math.ceil((NUDGE_COOLDOWN_MS - waited) / 60000))
        return NextResponse.json(
          { error: `You already nudged them — try again in ${mins} minute${mins === 1 ? '' : 's'}.` },
          { status: 429 },
        )
      }
    }
    await notifyUser(friendship.addresseeId, {
      type: 'nudge',
      title: `${me.username} is waiting for your reply!`,
      body: 'They sent you a friend request. Open Friends to accept or decline it.',
      linkUrl: '/friends',
      actorId: me.id,
    })
    return NextResponse.json({ ok: true, nudged: true })
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
