import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

// GET /api/chat — conversation list: every friend with last message + unread count
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const sent = await db.friendship.findMany({ where: { requesterId: me.id, status: 'accepted' } })
  const received = await db.friendship.findMany({ where: { addresseeId: me.id, status: 'accepted' } })
  const friendIds = [...sent.map((f) => f.addresseeId), ...received.map((f) => f.requesterId)]

  if (friendIds.length === 0) return NextResponse.json({ conversations: [] })

  const friends = await db.user.findMany({
    where: { id: { in: friendIds } },
  })

  const conversations = await Promise.all(
    friends.map(async (f) => {
      const last = await db.chatMessage.findFirst({
        where: { OR: [{ senderId: me.id, recipientId: f.id }, { senderId: f.id, recipientId: me.id }] },
        orderBy: { createdAt: 'desc' },
      })
      const unread = await db.chatMessage.count({
        where: { senderId: f.id, recipientId: me.id, readAt: null },
      })
      return {
        friend: publicUser(f),
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

  // friends with the freshest messages float to the top
  conversations.sort((a, b) => {
    const ta = a.lastMessage ? new Date(a.lastMessage.createdAt).getTime() : 0
    const tb = b.lastMessage ? new Date(b.lastMessage.createdAt).getTime() : 0
    return tb - ta
  })

  return NextResponse.json({ conversations })
}
