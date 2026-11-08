import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, isOnline } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const viewer = await getUserFromReq(req)
  const url = new URL(req.url)
  const q = (url.searchParams.get('q') || '').trim()
  const itemId = (url.searchParams.get('itemId') || '').trim()

  const items = await db.avatarItem.findMany({
    where: {
      deletedAt: null,
      ...(itemId
        ? { id: itemId }
        : q
          ? {
              OR: [
                { name: { contains: q } },
                { description: { contains: q } },
                { assetId: { contains: q } },
              ],
            }
          : { OR: [{ isLimited: true }, { isSuperLimited: true }] }),
    },
    select: {
      id: true,
      assetId: true,
      name: true,
      type: true,
      price: true,
      isLimited: true,
      isSuperLimited: true,
      stock: true,
      imageFileId: true,
      creatorId: true,
    },
    take: 20,
    orderBy: { createdAt: 'desc' },
  })

  const itemIds = items.map((i) => i.id)
  const entries = itemIds.length > 0
    ? await db.inventoryEntry.findMany({
        where: { itemId: { in: itemIds } },
        include: {
          user: {
            select: {
              id: true,
              username: true,
              avatarUrl: true,
              lastSeen: true,
              seqId: true,
            },
          },
        },
        orderBy: { acquiredAt: 'desc' },
        take: 200,
      })
    : []

  const ownerMap = new Map<string, Array<{
    id: string
    username: string
    avatarUrl: string | null
    online: boolean
    isCreator: boolean
    isViewer: boolean
    acquiredAt: Date
  }>>()

  for (const entry of entries) {
    if (!ownerMap.has(entry.itemId)) ownerMap.set(entry.itemId, [])
    const item = items.find((i) => i.id === entry.itemId)
    ownerMap.get(entry.itemId)!.push({
      id: entry.user.id,
      username: entry.user.username,
      avatarUrl: entry.user.avatarUrl,
      online: isOnline(entry.user.lastSeen),
      isCreator: item?.creatorId === entry.user.id,
      isViewer: viewer?.id === entry.user.id,
      acquiredAt: entry.acquiredAt,
    })
  }

  const results = items.map((item) => ({
    ...item,
    owners: ownerMap.get(item.id) || [],
  }))

  return NextResponse.json({ items: results })
}
