import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * BOT CLEANUP — admin-only housekeeping for junk accounts.
 *
 * GET   /api/admin/bots      — recent accounts (newest 60); probe/bot-shaped
 *                              usernames get a `likelyBot` hint so they are
 *                              easy to spot.
 * POST  /api/admin/bots      — { userIds: [...] } hard-removes those accounts
 *                              and EVERYTHING they own (a real sweep, not a
 *                              soft delete). Admins can never be removed,
 *                              and neither can the caller themself.
 */

const BOT_PATTERN = /^(mxl[a-z0-9]{6,}|probe|bot[_-]?|test[_-]?user)/i

async function requireAdmin(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return { error: NextResponse.json({ error: 'Login required' }, { status: 401 }) }
  if (user.role !== 'admin') return { error: NextResponse.json({ error: 'Admins only.' }, { status: 403 }) }
  return { user }
}

export async function GET(req: NextRequest) {
  const { error } = await requireAdmin(req)
  if (error) return error
  const users = await db.user.findMany({
    orderBy: { createdAt: 'desc' },
    take: 60,
    select: {
      id: true,
      username: true,
      playerNo: true,
      createdAt: true,
      lastSeen: true,
      role: true,
      _count: { select: { inventory: true, ugcItems: true, tradesSent: true, tradesRecv: true } },
    },
  })
  return NextResponse.json({
    users: users.map((u) => ({
      ...u,
      likelyBot: BOT_PATTERN.test(u.username),
    })),
  })
}

export async function POST(req: NextRequest) {
  const { error, user: admin } = await requireAdmin(req)
  if (error) return error
  const body = await req.json().catch(() => ({}))
  const userIds: string[] = [...new Set(Array.isArray(body?.userIds) ? (body.userIds as unknown[]).map((x) => String(x)) : [])]
  if (userIds.length === 0) return NextResponse.json({ error: 'Pick at least one account to remove.' }, { status: 400 })

  const targets = await db.user.findMany({ where: { id: { in: userIds } }, select: { id: true, username: true, role: true } })
  const removable = targets.filter((t) => t.role !== 'admin' && t.id !== admin.id)
  const skipped = targets.length - removable.length
  if (removable.length === 0) {
    return NextResponse.json({ error: 'Admins (and you) can never be removed.' }, { status: 400 })
  }

  const removed: string[] = []
  for (const target of removable) {
    // delete in one transaction — anything the account owns or made goes
    // with it, so no orphans linger behind
    await db.$transaction(async (tx) => {
      await tx.ugcTradeMessage.deleteMany({ where: { senderId: target.id } })
      await tx.ugcListingMessage.deleteMany({ where: { senderId: target.id } })
      await tx.ugcTrade.deleteMany({ where: { OR: [{ fromUserId: target.id }, { toUserId: target.id }] } })
      await tx.ugcOffer.deleteMany({ where: { buyerId: target.id } })
      await tx.ugcListing.deleteMany({ where: { sellerId: target.id } })
      await tx.ugcPricePoint.deleteMany({ where: { OR: [{ buyerId: target.id }, { sellerId: target.id }] } })
      await tx.ugcComment.deleteMany({ where: { userId: target.id } })
      await tx.notification.deleteMany({ where: { userId: target.id } })
      await tx.inventoryEntry.deleteMany({ where: { userId: target.id } })
      await tx.avatarItem.deleteMany({ where: { creatorId: target.id } })
      await tx.session.deleteMany({ where: { userId: target.id } })
      await tx.rbxTransaction.deleteMany({ where: { userId: target.id } })
      await tx.chatMessage.deleteMany({ where: { OR: [{ senderId: target.id }, { recipientId: target.id }] } })
      await tx.friendship.deleteMany({ where: { OR: [{ requesterId: target.id }, { addresseeId: target.id }] } })
      await tx.follow.deleteMany({ where: { OR: [{ followerId: target.id }, { followingId: target.id }] } })
      await tx.groupMember.deleteMany({ where: { userId: target.id } })
      await tx.gamePlay.deleteMany({ where: { userId: target.id } })
      await tx.playSession.deleteMany({ where: { userId: target.id } })
      await tx.comment.deleteMany({ where: { userId: target.id } })
      await tx.communityPost.deleteMany({ where: { authorId: target.id } })
      await tx.video.deleteMany({ where: { authorId: target.id } })
      await tx.user.delete({ where: { id: target.id } })
    })
    removed.push(target.username)
  }

  return NextResponse.json({ ok: true, removed, skipped })
}
