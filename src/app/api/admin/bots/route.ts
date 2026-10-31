import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, isUserAdmin } from '@/lib/auth'
import type { Prisma } from '@prisma/client'

/**
 * BOT & BOT-UGC CLEANUP — admin-only housekeeping for junk accounts and bot UGC.
 *
 * GET   /api/admin/bots      — lists accounts; bot-shaped usernames flagged with `likelyBot`
 *                              supports ?q=... (search) and ?filter=all|bots
 * POST  /api/admin/bots      — { userIds: [...] } or { purgeAllBots: true }
 *                              Fast bulk removal of those accounts and EVERYTHING they own/created
 *                              (UGC items, inventory, trades, listings, chats).
 *                              Admins can never be removed.
 */

export const BOT_PATTERN = /^(mxl[a-z0-9]{4,}|probe|bot[_-]?|test[_-]?user|npc|ai[_-]|auto[_-]|fake|sample|dummy|guest[_-]?\d+|user\d{5,}|player[_-]?\d{4,}|spam|junk|anon[_-]?\d+)/i

async function requireAdmin(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return { error: NextResponse.json({ error: 'Login required' }, { status: 401 }) }
  if (!isUserAdmin(user)) return { error: NextResponse.json({ error: 'Admins only.' }, { status: 403 }) }
  return { user }
}

export async function GET(req: NextRequest) {
  const { error } = await requireAdmin(req)
  if (error) return error

  const url = new URL(req.url)
  const q = (url.searchParams.get('q') || '').trim().toLowerCase()
  const filter = (url.searchParams.get('filter') || 'all').toLowerCase()
  const limit = Math.min(Math.max(Number(url.searchParams.get('limit')) || 300, 10), 1000)

  const whereClause: Prisma.UserWhereInput = {}
  if (q) {
    whereClause.username = { contains: q }
  }

  const users = await db.user.findMany({
    where: whereClause,
    orderBy: { createdAt: 'desc' },
    take: limit,
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

  const mapped = users.map((u) => ({
    id: u.id,
    username: u.username,
    playerNo: u.seqId,
    createdAt: u.createdAt,
    lastSeen: u.lastSeen,
    role: u.role,
    _count: u._count,
    likelyBot: BOT_PATTERN.test(u.username),
  }))

  const filtered = filter === 'bots' ? mapped.filter((u) => u.likelyBot) : mapped

  return NextResponse.json({
    users: filtered,
    total: mapped.length,
    botCount: mapped.filter((u) => u.likelyBot).length,
  })
}

async function purgeUsersBulk(tx: Prisma.TransactionClient, targetIds: string[]): Promise<number> {
  if (targetIds.length === 0) return 0

  // 1. UGC listings messages & offers & listings where target is buyer/seller
  await tx.ugcListingMessage.deleteMany({ where: { senderId: { in: targetIds } } }).catch(() => {})
  await tx.ugcOffer.deleteMany({ where: { buyerId: { in: targetIds } } }).catch(() => {})
  await tx.ugcListing.updateMany({ where: { buyerId: { in: targetIds } }, data: { buyerId: null } }).catch(() => {})

  const userListings = await tx.ugcListing.findMany({ where: { sellerId: { in: targetIds } }, select: { id: true } })
  const userListingIds = userListings.map((l) => l.id)
  if (userListingIds.length > 0) {
    await tx.ugcOffer.deleteMany({ where: { listingId: { in: userListingIds } } }).catch(() => {})
    await tx.ugcListingMessage.deleteMany({ where: { listingId: { in: userListingIds } } }).catch(() => {})
    await tx.ugcListing.deleteMany({ where: { id: { in: userListingIds } } }).catch(() => {})
  }

  // 2. Trades
  await tx.trade.deleteMany({ where: { OR: [{ fromUserId: { in: targetIds } }, { toUserId: { in: targetIds } }] } }).catch(() => {})

  // 3. Notifications, Inventory, Sessions, Transactions, Presence, Chat
  await tx.notification.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.inventoryEntry.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.session.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.rbxTransaction.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.payment.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.avatarConfig.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.gameData.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.placeChatMessage.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.placeChat.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.placePresence.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.playerPresence.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.chatMessage.deleteMany({ where: { OR: [{ senderId: { in: targetIds } }, { recipientId: { in: targetIds } }] } }).catch(() => {})
  await tx.friendship.deleteMany({ where: { OR: [{ requesterId: { in: targetIds } }, { addresseeId: { in: targetIds } }] } }).catch(() => {})
  await tx.follow.deleteMany({ where: { OR: [{ followerId: { in: targetIds } }, { followingId: { in: targetIds } }] } }).catch(() => {})
  await tx.itemComment.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.ugcPricePoint.deleteMany({ where: { OR: [{ buyerId: { in: targetIds } }, { sellerId: { in: targetIds } }] } }).catch(() => {})

  // 4. UGC items created by any of these users
  const userItems = await tx.avatarItem.findMany({ where: { creatorId: { in: targetIds } }, select: { id: true } })
  const userItemIds = userItems.map((i) => i.id)
  let itemsDeleted = 0
  if (userItemIds.length > 0) {
    const itemListingIds = (
      await tx.ugcListing.findMany({ where: { itemId: { in: userItemIds } }, select: { id: true } })
    ).map((l) => l.id)
    if (itemListingIds.length > 0) {
      await tx.ugcOffer.deleteMany({ where: { listingId: { in: itemListingIds } } }).catch(() => {})
      await tx.ugcListingMessage.deleteMany({ where: { listingId: { in: itemListingIds } } }).catch(() => {})
      await tx.ugcListing.deleteMany({ where: { id: { in: itemListingIds } } }).catch(() => {})
    }
    await tx.inventoryEntry.deleteMany({ where: { itemId: { in: userItemIds } } }).catch(() => {})
    await tx.ugcPricePoint.deleteMany({ where: { itemId: { in: userItemIds } } }).catch(() => {})
    await tx.itemComment.deleteMany({ where: { itemId: { in: userItemIds } } }).catch(() => {})
    const ugc = await tx.avatarItem.deleteMany({ where: { id: { in: userItemIds } } }).catch(() => ({ count: 0 }))
    itemsDeleted = ugc.count
  }

  // 5. Groups
  await tx.groupPostReply.deleteMany({ where: { authorId: { in: targetIds } } }).catch(() => {})
  await tx.groupPost.deleteMany({ where: { authorId: { in: targetIds } } }).catch(() => {})
  await tx.groupMember.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  const ownedGroups = await tx.group.findMany({ where: { ownerId: { in: targetIds } }, select: { id: true } })
  const ownedGroupIds = ownedGroups.map((g) => g.id)
  if (ownedGroupIds.length > 0) {
    await tx.groupPostReply.deleteMany({ where: { post: { groupId: { in: ownedGroupIds } } } }).catch(() => {})
    await tx.groupPost.deleteMany({ where: { groupId: { in: ownedGroupIds } } }).catch(() => {})
    await tx.groupRole.deleteMany({ where: { groupId: { in: ownedGroupIds } } }).catch(() => {})
    await tx.groupMember.deleteMany({ where: { groupId: { in: ownedGroupIds } } }).catch(() => {})
    await tx.avatarItem.updateMany({ where: { groupId: { in: ownedGroupIds } }, data: { groupId: null } }).catch(() => {})
    await tx.game.updateMany({ where: { groupId: { in: ownedGroupIds } }, data: { groupId: null } }).catch(() => {})
    await tx.group.deleteMany({ where: { id: { in: ownedGroupIds } } }).catch(() => {})
  }

  // 6. Community, Videos, Labs, Subs, Music
  await tx.communityComment.deleteMany({ where: { authorId: { in: targetIds } } }).catch(() => {})
  const userPosts = await tx.communityPost.findMany({ where: { authorId: { in: targetIds } }, select: { id: true } })
  const postIds = userPosts.map((p) => p.id)
  if (postIds.length > 0) {
    await tx.communityComment.deleteMany({ where: { postId: { in: postIds } } }).catch(() => {})
    await tx.communityPost.deleteMany({ where: { id: { in: postIds } } }).catch(() => {})
  }

  await tx.videoComment.deleteMany({ where: { authorId: { in: targetIds } } }).catch(() => {})
  const userVideos = await tx.video.findMany({ where: { authorId: { in: targetIds } }, select: { id: true } })
  const videoIds = userVideos.map((v) => v.id)
  if (videoIds.length > 0) {
    await tx.videoComment.deleteMany({ where: { videoId: { in: videoIds } } }).catch(() => {})
    await tx.video.deleteMany({ where: { id: { in: videoIds } } }).catch(() => {})
  }

  await tx.labReply.deleteMany({ where: { authorId: { in: targetIds } } }).catch(() => {})
  const labPosts = await tx.labPost.findMany({ where: { authorId: { in: targetIds } }, select: { id: true } })
  const labPostIds = labPosts.map((p) => p.id)
  if (labPostIds.length > 0) {
    await tx.labReply.deleteMany({ where: { postId: { in: labPostIds } } }).catch(() => {})
    await tx.labPost.deleteMany({ where: { id: { in: labPostIds } } }).catch(() => {})
  }

  const subs = await tx.sub.findMany({ where: { creatorId: { in: targetIds } }, select: { id: true } })
  const subIds = subs.map((s) => s.id)
  if (subIds.length > 0) {
    await tx.communityPost.updateMany({ where: { subId: { in: subIds } }, data: { subId: null } }).catch(() => {})
    await tx.sub.deleteMany({ where: { id: { in: subIds } } }).catch(() => {})
  }
  await tx.musicTrack.deleteMany({ where: { creatorId: { in: targetIds } } }).catch(() => {})

  // 7. Games & Plays
  await tx.playerBadge.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.gameDownload.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.gameLike.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.favorite.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.comment.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.gamePlay.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})
  await tx.playSession.deleteMany({ where: { userId: { in: targetIds } } }).catch(() => {})

  const userGames = await tx.game.findMany({ where: { creatorId: { in: targetIds } }, select: { id: true } })
  const gameIds = userGames.map((g) => g.id)
  if (gameIds.length > 0) {
    await tx.gameLike.deleteMany({ where: { gameId: { in: gameIds } } }).catch(() => {})
    await tx.favorite.deleteMany({ where: { gameId: { in: gameIds } } }).catch(() => {})
    await tx.comment.deleteMany({ where: { gameId: { in: gameIds } } }).catch(() => {})
    await tx.gamePlay.deleteMany({ where: { gameId: { in: gameIds } } }).catch(() => {})
    await tx.playSession.deleteMany({ where: { gameId: { in: gameIds } } }).catch(() => {})
    await tx.gameDownload.deleteMany({ where: { gameId: { in: gameIds } } }).catch(() => {})
    await tx.gameData.deleteMany({ where: { gameId: { in: gameIds } } }).catch(() => {})
    await tx.game.deleteMany({ where: { id: { in: gameIds } } }).catch(() => {})
  }

  // 8. Delete user records in bulk!
  await tx.user.deleteMany({ where: { id: { in: targetIds } } })
  return itemsDeleted
}

export async function POST(req: NextRequest) {
  const { error, user: admin } = await requireAdmin(req)
  if (error) return error
  const body = await req.json().catch(() => ({}))

  const adminLower = admin.username.toLowerCase()
  let userIds: string[] = []

  if (body?.purgeAllBots) {
    const allUsers = await db.user.findMany({
      where: {
        role: { not: 'admin' },
        id: { not: admin.id },
        usernameLower: { notIn: ['nexico8225', 'neixco8225'] },
      },
      select: { id: true, username: true },
      take: 1000,
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

  // Prevent deleting admins or owner accounts
  const removable = targets.filter((t) => {
    const low = t.username.toLowerCase()
    return t.role !== 'admin' && t.id !== admin.id && low !== 'nexico8225' && low !== 'neixco8225' && low !== adminLower
  })

  if (removable.length === 0) {
    return NextResponse.json({ ok: true, removed: [], count: 0, itemsDeleted: 0, message: 'No eligible accounts to delete.' })
  }

  const targetIds = removable.map((t) => t.id)
  const removedNames = removable.map((t) => t.username)

  let itemsDeleted = 0
  try {
    itemsDeleted = await db.$transaction(async (tx) => {
      return await purgeUsersBulk(tx, targetIds)
    })
  } catch (err: unknown) {
    console.error('Bulk bot purge failed:', err)
    return NextResponse.json(
      { error: `Deletion failed: ${err instanceof Error ? err.message : String(err)}` },
      { status: 500 }
    )
  }

  // Clean up any remaining orphan UGC items whose creators no longer exist
  try {
    const existingUserIds = (await db.user.findMany({ select: { id: true } })).map((u) => u.id)
    const orphanItems = await db.avatarItem.findMany({
      where: { creatorId: { notIn: existingUserIds } },
      select: { id: true },
    })
    const orphanItemIds = orphanItems.map((i) => i.id)
    if (orphanItemIds.length > 0) {
      await db.inventoryEntry.deleteMany({ where: { itemId: { in: orphanItemIds } } }).catch(() => {})
      await db.ugcListing.deleteMany({ where: { itemId: { in: orphanItemIds } } }).catch(() => {})
      await db.ugcPricePoint.deleteMany({ where: { itemId: { in: orphanItemIds } } }).catch(() => {})
      await db.itemComment.deleteMany({ where: { itemId: { in: orphanItemIds } } }).catch(() => {})
      const orphanUgc = await db.avatarItem.deleteMany({ where: { id: { in: orphanItemIds } } }).catch(() => ({ count: 0 }))
      itemsDeleted += orphanUgc.count
    }
  } catch {
    /* ignore orphan cleanup errors */
  }

  return NextResponse.json({
    ok: true,
    removed: removedNames,
    itemsDeleted,
    count: removedNames.length,
  })
}
