import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'
import { notifyUser, ensureNotificationSchema } from '@/lib/notifications'

// GET: friends list, incoming requests, outgoing requests
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const sent = await db.friendship.findMany({
    where: { requesterId: me.id },
    include: { addressee: true },
  })
  const received = await db.friendship.findMany({
    where: { addresseeId: me.id },
    include: { requester: true },
  })

  const friends = [
    ...sent.filter((f) => f.status === 'accepted').map((f) => ({ ...publicUser(f.addressee), friendshipId: f.id })),
    ...received.filter((f) => f.status === 'accepted').map((f) => ({ ...publicUser(f.requester), friendshipId: f.id })),
  ]

  const incoming = received
    .filter((f) => f.status === 'pending')
    .map((f) => ({ id: f.id, user: publicUser(f.requester), createdAt: f.createdAt }))

  const outgoingRows = sent.filter((f) => f.status === 'pending')

  // when did I last nudge each pending request? (UI uses it to show
  // "Nudged ✓" / cooldown state instead of a button that might 429)
  const nudgeMap: Record<string, string> = {}
  if (outgoingRows.length > 0) {
    await ensureNotificationSchema()
    const nudges = await db.notification.findMany({
      where: { type: 'nudge', actorId: me.id, userId: { in: outgoingRows.map((f) => f.addresseeId) } },
      orderBy: { createdAt: 'desc' },
      select: { userId: true, createdAt: true },
    })
    for (const n of nudges) {
      if (!nudgeMap[n.userId]) nudgeMap[n.userId] = n.createdAt.toISOString()
    }
  }

  const outgoing = outgoingRows.map((f) => ({
    id: f.id,
    user: publicUser(f.addressee),
    createdAt: f.createdAt,
    lastNudgeAt: nudgeMap[f.addresseeId] || null,
  }))

  return NextResponse.json({ friends, incoming, outgoing })
}

// POST: send a friend request by username
export async function POST(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = await req.json()
  const username = String(body.username || '').trim()
  if (!username) return NextResponse.json({ error: 'Type a username!' }, { status: 400 })

  // Case-insensitive lookup: "retroblox" finds "RetroBlox" (and the
  // usernameLower index catches legacy users with a null usernameLower).
  const target =
    (await db.user.findUnique({ where: { username } })) ??
    (await db.user.findUnique({ where: { usernameLower: username.toLowerCase() } }))
  if (!target) return NextResponse.json({ error: `No user named "${username}" found.` }, { status: 404 })
  if (target.id === me.id) return NextResponse.json({ error: "You can't friend yourself!" }, { status: 400 })

  const existing = await db.friendship.findUnique({
    where: { requesterId_addresseeId: { requesterId: me.id, addresseeId: target.id } },
  })
  if (existing) {
    return NextResponse.json({
      error: existing.status === 'accepted' ? 'Already friends!' : 'Request already sent.',
    }, { status: 409 })
  }

  const reverse = await db.friendship.findUnique({
    where: { requesterId_addresseeId: { requesterId: target.id, addresseeId: me.id } },
  })
  if (reverse) {
    if (reverse.status === 'accepted') {
      return NextResponse.json({ error: 'Already friends!' }, { status: 409 })
    }
    // they already asked us -> auto accept
    await db.friendship.update({ where: { id: reverse.id }, data: { status: 'accepted' } })
    await notifyUser(target.id, {
      type: 'friend_accepted',
      title: `${me.username} is now your friend!`,
      body: 'You can chat with each other now.',
      linkUrl: `/chat/${me.id}`,
      actorId: me.id,
    })
    return NextResponse.json({ ok: true, autoAccepted: true, user: publicUser(target) })
  }

  await db.friendship.create({
    data: { requesterId: me.id, addresseeId: target.id, status: 'pending' },
  })
  await notifyUser(target.id, {
    type: 'friend_request',
    title: `${me.username} sent you a friend request!`,
    body: 'Open Friends to accept or decline it.',
    linkUrl: '/friends',
    actorId: me.id,
  })
  return NextResponse.json({ ok: true, user: publicUser(target) })
}
