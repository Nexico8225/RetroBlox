import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, isOnline } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const viewer = await getUserFromReq(req)
  const q = req.nextUrl.searchParams.get('q')?.trim().toLowerCase() || ''

  // Fetch all pending marketplace trades
  const trades = await db.trade.findMany({
    where: {
      status: 'pending',
      notesJson: { contains: 'public_marketplace' },
    },
    include: {
      fromUser: {
        select: {
          id: true,
          username: true,
          avatarUrl: true,
          seqId: true,
          lastSeen: true,
        },
      },
    },
    orderBy: { createdAt: 'desc' },
    take: 50,
  })

  // Batch load all items
  const idSet = new Set<string>()
  for (const t of trades) {
    for (const x of JSON.parse(t.giveItemIds || '[]') as string[]) idSet.add(x)
    for (const x of JSON.parse(t.takeItemIds || '[]') as string[]) idSet.add(x)
  }
  const ids = [...idSet]
  const items = ids.length
    ? await db.avatarItem.findMany({
        where: { id: { in: ids } },
        select: {
          id: true,
          assetId: true,
          name: true,
          type: true,
          price: true,
          isLimited: true,
          imageFileId: true,
        },
      })
    : []
  const itemMap = Object.fromEntries(items.map((i) => [i.id, i]))

  // Viewer's owned items
  let viewerOwnedSet = new Set<string>()
  if (viewer) {
    const viewerInventory = await db.inventoryEntry.findMany({
      where: { userId: viewer.id },
      select: { itemId: true },
    })
    viewerOwnedSet = new Set(viewerInventory.map((i) => i.itemId))
  }

  const mapped = trades
    .map((t) => {
      const give = (JSON.parse(t.giveItemIds || '[]') as string[]).map((x) => itemMap[x]).filter(Boolean)
      const take = (JSON.parse(t.takeItemIds || '[]') as string[]).map((x) => itemMap[x]).filter(Boolean)
      const isMine = viewer?.id === t.fromUserId
      const canAccept = !isMine && viewer != null && take.every((it) => viewerOwnedSet.has(it.id))

      return {
        id: t.id,
        tix: t.tix,
        message: t.message,
        createdAt: t.createdAt,
        from: {
          id: t.fromUser.id,
          username: t.fromUser.username,
          avatarUrl: t.fromUser.avatarUrl,
          seqId: t.fromUser.seqId,
          online: isOnline(t.fromUser.lastSeen),
        },
        give,
        take,
        isMine,
        canAccept,
      }
    })
    .filter((t) => {
      if (!q) return true
      const matchGive = t.give.some((it) => it.name.toLowerCase().includes(q) || it.type.toLowerCase().includes(q))
      const matchTake = t.take.some((it) => it.name.toLowerCase().includes(q) || it.type.toLowerCase().includes(q))
      const matchUser = t.from.username.toLowerCase().includes(q)
      const matchMsg = t.message.toLowerCase().includes(q)
      return matchGive || matchTake || matchUser || matchMsg
    })

  return NextResponse.json({ trades: mapped })
}
