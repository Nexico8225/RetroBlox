import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import type { Prisma } from '@prisma/client'

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

async function purgeUser(tx: Prisma.TransactionClient, targetId: string): Promise<number> {
  // 1. UGC listings messages & offers & listings where target is buyer/seller
  await tx.ugcListingMessage.deleteMany({ where: { senderId: targetId } })
  await tx.ugcOffer.deleteMany({ where: { buyerId: targetId } })
  await tx.ugcListing.updateMany({ where: { buyerId: targetId }, data: { buyerId: null } })

  const userListings = await tx.ugcListing.findMany({ where: { sellerId: targetId }, select: { id: true } })
  const userListingIds = userListings.map((l) => l.id)
  if (userListingIds.length > 0) {
    await tx.ugcOffer.deleteMany({ where: { listingId: { in: userListingIds } } })
    await tx.ugcListingMessage.deleteMany({ where: { listingId: { in: userListingIds } } })
    await tx.ugcListing.deleteMany({ where: { id: { in: userListingIds } } })
  }

  // 2. Trades (model uses fromUserId and toUserId)
  await tx.trade.deleteMany({ where: { OR: [{ fromUserId: targetId }, { toUserId: targetId }] } })

  // 3. Notifications, Inventory, Sessions, Transactions
  await tx.notification.deleteMany({ where: { userId: targetId } })
  await tx.inventoryEntry.deleteMany({ where: { userId: targetId } })
  await tx.session.deleteMany({ where: { userId: targetId } })
  await tx.rbxTransaction.deleteMany({ where: { userId: targetId } })
  await tx.payment.deleteMany({ where: { userId: targetId } })
  await tx.avatarConfig.deleteMany({ where: { userId: targetId } })
  await tx.gameData.deleteMany({ where: { userId: targetId } })

  // 4. UGC items created by this user (clean dependencies first to avoid foreign key violations)
  const userItems = await tx.avatarItem.findMany({ where: { creatorId: targetId }, select: { id: true } })
  const userItemIds = userItems.map((i) => i.id)
  let itemsDeleted = 0
  if (userItemIds.length > 0) {
    const itemListingIds = (
      await tx.ugcListing.findMany({ where: { itemId: { in: userItemIds } }, select: { id: true } })
    ).map((l) => l.id)
    if (itemListingIds.length > 0) {
      await tx.ugcOffer.deleteMany({ where: { listingId: { in: itemListingIds } } })
      await tx.ugcListingMessage.deleteMany({ where: { listingId: { in: itemListingIds } } })
      await tx.ugcListing.deleteMany({ where: { id: { in: itemListingIds } } })
    }
    await tx.inventoryEntry.deleteMany({ where: { itemId: { in: userItemIds } } })
    await tx.ugcPricePoint.deleteMany({ where: { itemId: { in: userItemIds } } })
    await tx.itemComment.deleteMany({ where: { itemId: { in: userItemIds } } })
    const ugc = await tx.avatarItem.deleteMany({ where: { id: { in: userItemIds } } })
    itemsDeleted = ugc.count
  }

  // UGC price points and comments
  await tx.ugcPricePoint.deleteMany({ where: { OR: [{ buyerId: targetId }, { sellerId: targetId }] } })
  await tx.itemComment.deleteMany({ where: { userId: targetId } })

  // 5. Social & Chat
  await tx.chatMessage.deleteMany({ where: { OR: [{ senderId: targetId }, { recipientId: targetId }] } })
  await tx.friendship.deleteMany({ where: { OR: [{ requesterId: targetId }, { addresseeId: targetId }] } })
  await tx.follow.deleteMany({ where: { OR: [{ followerId: targetId }, { followingId: targetId }] } })
  await tx.placeChatMessage.deleteMany({ where: { userId: targetId } })
  await tx.placePresence.deleteMany({ where: { userId: targetId } })
  await tx.playerPresence.deleteMany({ where: { userId: targetId } })

  // 6. Groups
  await tx.groupPostReply.deleteMany({ where: { authorId: targetId } })
  await tx.groupPost.deleteMany({ where: { authorId: targetId } })
  await tx.groupMember.deleteMany({ where: { userId: targetId } })
  const ownedGroups = await tx.group.findMany({ where: { ownerId: targetId }, select: { id: true } })
  const ownedGroupIds = ownedGroups.map((g) => g.id)
  if (ownedGroupIds.length > 0) {
    await tx.groupPostReply.deleteMany({ where: { post: { groupId: { in: ownedGroupIds } } } })
    await tx.groupPost.deleteMany({ where: { groupId: { in: ownedGroupIds } } })
    await tx.groupRole.deleteMany({ where: { groupId: { in: ownedGroupIds } } })
    await tx.groupMember.deleteMany({ where: { groupId: { in: ownedGroupIds } } })
    await tx.avatarItem.updateMany({ where: { groupId: { in: ownedGroupIds } }, data: { groupId: null } })
    await tx.game.updateMany({ where: { groupId: { in: ownedGroupIds } }, data: { groupId: null } })
    await tx.group.deleteMany({ where: { id: { in: ownedGroupIds } } })
  }

  // 7. Community & Videos & Labs & Subs & Music
  await tx.communityComment.deleteMany({ where: { authorId: targetId } })
  const userPosts = await tx.communityPost.findMany({ where: { authorId: targetId }, select: { id: true } })
  const postIds = userPosts.map((p) => p.id)
  if (postIds.length > 0) {
    await tx.communityComment.deleteMany({ where: { postId: { in: postIds } } })
    await tx.communityPost.deleteMany({ where: { id: { in: postIds } } })
  }

  await tx.videoComment.deleteMany({ where: { authorId: targetId } })
  const userVideos = await tx.video.findMany({ where: { authorId: targetId }, select: { id: true } })
  const videoIds = userVideos.map((v) => v.id)
  if (videoIds.length > 0) {
    await tx.videoComment.deleteMany({ where: { videoId: { in: videoIds } } })
    await tx.video.deleteMany({ where: { id: { in: videoIds } } })
  }

  await tx.labReply.deleteMany({ where: { authorId: targetId } })
  const labPosts = await tx.labPost.findMany({ where: { authorId: targetId }, select: { id: true } })
  const labPostIds = labPosts.map((p) => p.id)
  if (labPostIds.length > 0) {
    await tx.labReply.deleteMany({ where: { postId: { in: labPostIds } } })
    await tx.labPost.deleteMany({ where: { id: { in: labPostIds } } })
  }

  const subs = await tx.sub.findMany({ where: { creatorId: targetId }, select: { id: true } })
  const subIds = subs.map((s) => s.id)
  if (subIds.length > 0) {
    await tx.communityPost.updateMany({ where: { subId: { in: subIds } }, data: { subId: null } })
    await tx.sub.deleteMany({ where: { id: { in: subIds } } })
  }

  await tx.musicTrack.deleteMany({ where: { creatorId: targetId } })

  // 8. Games & Plays
  await tx.playerBadge.deleteMany({ where: { userId: targetId } })
  await tx.gameDownload.deleteMany({ where: { userId: targetId } })
  await tx.gameLike.deleteMany({ where: { userId: targetId } })
  await tx.favorite.deleteMany({ where: { userId: targetId } })
  await tx.comment.deleteMany({ where: { userId: targetId } })
  await tx.gamePlay.deleteMany({ where: { userId: targetId } })
  await tx.playSession.deleteMany({ where: { userId: targetId } })

  const userGames = await tx.game.findMany({ where: { creatorId: targetId }, select: { id: true } })
  const gameIds = userGames.map((g) => g.id)
  if (gameIds.length > 0) {
    await tx.gameLike.deleteMany({ where: { gameId: { in: gameIds } } })
    await tx.favorite.deleteMany({ where: { gameId: { in: gameIds } } })
    await tx.comment.deleteMany({ where: { gameId: { in: gameIds } } })
    await tx.gamePlay.deleteMany({ where: { gameId: { in: gameIds } } })
    await tx.playSession.deleteMany({ where: { gameId: { in: gameIds } } })
    await tx.gameDownload.deleteMany({ where: { gameId: { in: gameIds } } })
    await tx.gameData.deleteMany({ where: { gameId: { in: gameIds } } })
    await tx.game.deleteMany({ where: { id: { in: gameIds } } })
  }

  // 9. Finally, the user record
  await tx.user.delete({ where: { id: targetId } })
  return itemsDeleted
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
  const errors: string[] = []
  let itemsDeleted = 0

  for (const target of removable) {
    try {
      const deleted = await db.$transaction(async (tx) => {
        return await purgeUser(tx, target.id)
      })
      itemsDeleted += deleted
      removed.push(target.username)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      console.error(`Failed to remove user ${target.username}:`, err)
      errors.push(`${target.username}: ${msg}`)
    }
  }

  // Also clean up any orphan UGC whose creator no longer exists
  try {
    const existingUserIds = (await db.user.findMany({ select: { id: true } })).map((u) => u.id)
    const orphanItems = await db.avatarItem.findMany({
      where: { creatorId: { notIn: existingUserIds } },
      select: { id: true },
    })
    const orphanItemIds = orphanItems.map((i) => i.id)
    if (orphanItemIds.length > 0) {
      await db.inventoryEntry.deleteMany({ where: { itemId: { in: orphanItemIds } } })
      await db.ugcListing.deleteMany({ where: { itemId: { in: orphanItemIds } } })
      await db.ugcPricePoint.deleteMany({ where: { itemId: { in: orphanItemIds } } })
      await db.itemComment.deleteMany({ where: { itemId: { in: orphanItemIds } } })
      const orphanUgc = await db.avatarItem.deleteMany({ where: { id: { in: orphanItemIds } } })
      itemsDeleted += orphanUgc.count
    }
  } catch {
    /* ignore orphan cleanup errors */
  }

  if (removed.length === 0 && errors.length > 0) {
    return NextResponse.json({ error: `Deletion failed: ${errors[0]}` }, { status: 500 })
  }

  return NextResponse.json({
    ok: true,
    removed,
    itemsDeleted,
    count: removed.length,
    errors: errors.length > 0 ? errors : undefined,
  })
}
