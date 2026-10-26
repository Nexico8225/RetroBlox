import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * BOT & BOT-UGC CLEANUP — admin-only housekeeping for junk accounts and bot UGC.
 *
 * GET   /api/admin/bots      — lists accounts; bot-shaped usernames flagged with `likelyBot`
 * POST  /api/admin/bots      — { userIds: [...] } or { purgeAllBots: true }
 *                              Hard-removes those accounts and EVERYTHING they own/created
 *                              (UGC items, inventory, trades, listings, chats).
 *                              Admins can never be removed.
 */

export const BOT_PATTERN = /^(mxl[a-z0-9]{6,}|probe|bot[_-]?|test[_-]?user|npc|ai[_-]|auto[_-]|fake|sample|dummy)/i

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
    take: 200,
    select: {
      id: true,
      username: true,
      seqId: true,
      createdAt: true,
      lastSeen: true,
      role: true,
      _count: { select: { inventory: true, ugcItems: true, tradesSent: true, tradesRecv: true } },
    },
  })

  return NextResponse.json({
    users: users.map((u) => ({
      id: u.id,
      username: u.username,
      playerNo: u.seqId,
      createdAt: u.createdAt,
      lastSeen: u.lastSeen,
      role: u.role,
      _count: u._count,
      likelyBot: BOT_PATTERN.test(u.username),
    })),
  })
}

export async function POST(req: NextRequest) {
  const { error, user: admin } = await requireAdmin(req)
  if (error) return error
  const body = await req.json().catch(() => ({}))

  let userIds: string[] = []
  if (body?.purgeAllBots) {
    const allUsers = await db.user.findMany({
      where: { role: { not: 'admin' }, id: { not: admin.id } },
      select: { id: true, username: true },
      take: 500,
    })
    userIds = allUsers.filter((u) => BOT_PATTERN.test(u.username)).map((u) => u.id)
  } else {
    userIds = [...new Set(Array.isArray(body?.userIds) ? (body.userIds as unknown[]).map((x) => String(x)) : [])]
  }

  if (userIds.length === 0 && !body?.purgeAllBots) {
    return NextResponse.json({ error: 'Pick at least one account to remove.' }, { status: 400 })
  }

  const targets = await db.user.findMany({
    where: { id: { in: userIds } },
    select: { id: true, username: true, role: true },
  })
  const removable = targets.filter((t) => t.role !== 'admin' && t.id !== admin.id)
  const removed: string[] = []
  let itemsDeleted = 0

  for (const target of removable) {
    // Delete in one transaction — removes the account and everything it created or owns
    await db.$transaction(async (tx) => {
      await tx.ugcListingMessage.deleteMany({ where: { senderId: target.id } })
      await tx.trade.deleteMany({ where: { OR: [{ senderId: target.id }, { receiverId: target.id }] } })
      await tx.ugcOffer.deleteMany({ where: { buyerId: target.id } })
      await tx.ugcListing.deleteMany({ where: { sellerId: target.id } })
      await tx.notification.deleteMany({ where: { userId: target.id } })
      await tx.inventoryEntry.deleteMany({ where: { userId: target.id } })

      // Delete UGC items created by this user
      const ugc = await tx.avatarItem.deleteMany({ where: { creatorId: target.id } })
      itemsDeleted += ugc.count

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

  // Also clean up any orphan UGC whose creator no longer exists
  try {
    const existingUserIds = (await db.user.findMany({ select: { id: true } })).map((u) => u.id)
    const orphanUgc = await db.avatarItem.deleteMany({
      where: { creatorId: { notIn: existingUserIds } },
    })
    itemsDeleted += orphanUgc.count
  } catch {
    /* ignore if relation is strictly foreign-keyed */
  }

  return NextResponse.json({ ok: true, removed, itemsDeleted, count: removed.length })
}
