import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'
import { ensureNotificationSchema } from '@/lib/notifications'

export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ user: null })

  const pendingCount = await db.friendship.count({
    where: { addresseeId: user.id, status: 'pending' },
  })

  const unreadChats = await db.chatMessage.count({
    where: { recipientId: user.id, readAt: null },
  })

  // bell badge — heals the Notification table first if this is a fresh
  // serverless instance that never saw it (cheap, runs once per process)
  let unreadNotifications = 0
  if (await ensureNotificationSchema()) {
    unreadNotifications = await db.notification
      .count({ where: { userId: user.id, readAt: null } })
      .catch(() => 0)
  }

  return NextResponse.json({
    user: publicUser(user),
    pendingFriendRequests: pendingCount,
    unreadChats,
    unreadNotifications,
  })
}
