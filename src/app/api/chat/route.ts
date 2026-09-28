import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

// GET /api/chat — conversation list: friends, people you've messaged
// before, and pending friend-request partners (so you can nudge them to
// accept!) — each with last message + unread count.
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  // every friendship row involving me: accepted = chat partner,
  // pending = still nudgable ("accept my request!")
  const rels = await db.friendship.findMany({
    where: { OR: [{ requesterId: me.id }, { addresseeId: me.id }] },
  })
  const partnerIds = new Set<string>()
  const pendingIds = new Set<string>()
  const pendingFriendshipIds = new Map<string, string>() // partnerId -> friendship row (for the Nudge button)
  for (const r of rels) {
    const other = r.requesterId === me.id ? r.addresseeId : r.requesterId
    if (r.status === 'accepted') partnerIds.add(other)
    else {
      pendingIds.add(other)
      pendingFriendshipIds.set(other, r.id)
    }
  }

  // anyone with message history, even non-friends
  const [sentTo, gotFrom] = await Promise.all([
    db.chatMessage.findMany({ where: { senderId: me.id }, select: { recipientId: true }, distinct: ['recipientId'] }),
    db.chatMessage.findMany({ where: { recipientId: me.id }, select: { senderId: true }, distinct: ['senderId'] }),
  ])
  sentTo.forEach((m) => partnerIds.add(m.recipientId))
  gotFrom.forEach((m) => partnerIds.add(m.senderId))
  pendingIds.forEach((id) => partnerIds.add(id))

  if (partnerIds.size === 0) return NextResponse.json({ conversations: [] })

  const ids = [...partnerIds].slice(0, 150)
  const partners = await db.user.findMany({ where: { id: { in: ids } } })

  const conversations = await Promise.all(
    partners.map(async (f) => {
      const last = await db.chatMessage.findFirst({
        where: { OR: [{ senderId: me.id, recipientId: f.id }, { senderId: f.id, recipientId: me.id }] },
        orderBy: { createdAt: 'desc' },
      })
      const unread = await db.chatMessage.count({
        where: { senderId: f.id, recipientId: me.id, readAt: null },
      })
      return {
        friend: publicUser(f),
        pending: pendingIds.has(f.id),
        friendshipId: pendingFriendshipIds.get(f.id) || null,
        lastMessage: last
          ? {
              text: last.text,
              fileId: last.fileId,
              fileType: last.fileType,
              fromMe: last.senderId === me.id,
              createdAt: last.createdAt,
            }
          : null,
        unread,
      }
    })
  )

  // freshest messages float to the top, pending requests after that
  conversations.sort((a, b) => {
    const ta = a.lastMessage ? new Date(a.lastMessage.createdAt).getTime() : 0
    const tb = b.lastMessage ? new Date(b.lastMessage.createdAt).getTime() : 0
    return tb - ta || Number(b.pending) - Number(a.pending)
  })

  return NextResponse.json({ conversations })
}
