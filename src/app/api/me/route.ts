import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ user: null })

  const pendingCount = await db.friendship.count({
    where: { addresseeId: user.id, status: 'pending' },
  })

  const unreadChats = await db.chatMessage.count({
    where: { recipientId: user.id, readAt: null },
  })

  return NextResponse.json({
    user: publicUser(user),
    pendingFriendRequests: pendingCount,
    unreadChats,
  })
}
