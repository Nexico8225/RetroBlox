import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ user: null })

  // every badge count is wrapped: a broken counter must never take the
  // whole shell down (a 500 here blanks the entire site for that player)
  let pendingCount = 0
  let unreadChats = 0
  let unreadNotifications = 0
  try {
    pendingCount = await db.friendship.count({ where: { addresseeId: user.id, status: 'pending' } })
  } catch (e) { console.error('[me] friendship.count failed:', e) }
  try {
    unreadChats = await db.chatMessage.count({ where: { recipientId: user.id, readAt: null } })
  } catch (e) { console.error('[me] chatMessage.count failed:', e) }
  try {
    unreadNotifications = await db.notification.count({ where: { userId: user.id, readAt: null } })
  } catch (e) { console.error('[me] notification.count failed:', e) }

  return NextResponse.json({
    user: publicUser(user),
    pendingFriendRequests: pendingCount,
    unreadChats,
    unreadNotifications,
  })
}
