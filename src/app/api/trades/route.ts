import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * GET  /api/trades — my trades (incoming + outgoing), newest first
 * POST /api/trades — send a trade offer
 *      { toUserId, giveItemIds: string[], takeItemIds: string[], tix?: number, message?: string }
 *
 * A trade is an OFFER: the sender gives their own UGC (+ optional Tix) and
 * asks for UGC the RECIPIENT owns. Nothing moves until the recipient
 * accepts — accepting swaps ownership + Tix inside ONE transaction.
 */
export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const trades = await db.trade.findMany({
    where: { OR: [{ fromUserId: user.id }, { toUserId: user.id }] },
    include: {
      fromUser: { select: { id: true, username: true, avatarUrl: true } },
      toUser: { select: { id: true, username: true, avatarUrl: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 60,
  })

  // the items referenced by every trade, batched into one query
  const idSet = new Set<string>()
  for (const t of trades) {
    for (const x of JSON.parse(t.giveItemIds || '[]') as string[]) idSet.add(x)
    for (const x of JSON.parse(t.takeItemIds || '[]') as string[]) idSet.add(x)
  }
  const ids = [...idSet]
  const items = ids.length
    ? await db.avatarItem.findMany({
        where: { id: { in: ids } },
        select: { id: true, assetId: true, name: true, type: true, imageFileId: true, modelFileId: true },
      })
    : []
  const itemMap = Object.fromEntries(items.map((i) => [i.id, i]))

  return NextResponse.json({
    trades: trades.map((t) => ({
      id: t.id,
      status: t.status,
      tix: t.tix,
      message: t.message,
      notes: JSON.parse(t.notesJson || '[]'),
      createdAt: t.createdAt,
      respondedAt: t.respondedAt,
      from: t.fromUser,
      to: t.toUser,
      give: (JSON.parse(t.giveItemIds || '[]') as string[]).map((x) => itemMap[x]).filter(Boolean),
      take: (JSON.parse(t.takeItemIds || '[]') as string[]).map((x) => itemMap[x]).filter(Boolean),
      isIncoming: t.toUserId === user.id,
    })),
  })
}

function idsEqual(a: string[], b: string[]): boolean {
  return a.length === b.length && [...a].sort().every((v, i) => v === [...b].sort()[i])
}

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = (await req.json().catch(() => ({}))) as {
    toUserId?: string
    giveItemIds?: string[]
    takeItemIds?: string[]
    tix?: number
    message?: string
  }

  const toUserId = String(body.toUserId || '')
  const giveIds = Array.isArray(body.giveItemIds) ? [...new Set(body.giveItemIds.map(String))] : []
  const takeIds = Array.isArray(body.takeItemIds) ? [...new Set(body.takeItemIds.map(String))] : []
  const tix = Math.max(0, Math.floor(Number(body.tix) || 0))
  const message = String(body.message || '').slice(0, 300)

  if (!toUserId || toUserId === user.id) {
    return NextResponse.json({ error: 'Pick someone else to trade with.' }, { status: 400 })
  }
  if (giveIds.length === 0 && takeIds.length === 0 && tix === 0) {
    return NextResponse.json({ error: 'An empty trade — put in items or Tix first.' }, { status: 400 })
  }
  if (giveIds.length > 8 || takeIds.length > 8) {
    return NextResponse.json({ error: '8 items per side max — this is a trade, not a warehouse.' }, { status: 400 })
  }
  const toUser = await db.user.findUnique({ where: { id: toUserId }, select: { id: true, username: true } })
  if (!toUser) return NextResponse.json({ error: 'That player does not exist.' }, { status: 404 })

  // the sender must OWN everything they give
  if (giveIds.length > 0) {
    const owned = await db.inventoryEntry.findMany({
      where: { userId: user.id, itemId: { in: giveIds } },
      select: { itemId: true },
    })
    const ownedSet = new Set(owned.map((o) => o.itemId))
    const missing = giveIds.filter((x) => !ownedSet.has(x))
    if (missing.length > 0) {
      return NextResponse.json({ error: 'You can only trade items you own.' }, { status: 400 })
    }
    const real = await db.avatarItem.count({ where: { id: { in: giveIds }, deletedAt: null } })
    if (real !== giveIds.length) {
      return NextResponse.json({ error: 'One of the items you are offering no longer exists.' }, { status: 400 })
    }
  }
  if (takeIds.length > 0) {
    // the requested items must exist and belong to the recipient
    const theirItems = await db.inventoryEntry.findMany({
      where: { userId: toUserId, itemId: { in: takeIds } },
      select: { itemId: true },
    })
    if (theirItems.length !== takeIds.length) {
      return NextResponse.json({ error: 'They do not own (all of) the items you asked for.' }, { status: 400 })
    }
  }
  if (tix > 0) {
    const me = await db.user.findUnique({ where: { id: user.id }, select: { rbxBalance: true } })
    if (!me || me.rbxBalance < tix) {
      return NextResponse.json({ error: 'Not enough Tix in your wallet for that offer.' }, { status: 400 })
    }
  }

  // no duplicate pending offers of exactly the same contents to the same person
  const dupes = await db.trade.findMany({
    where: { fromUserId: user.id, toUserId, status: 'pending' },
    select: { giveItemIds: true, takeItemIds: true, tix: true },
  })
  for (const d of dupes) {
    if (
      idsEqual(JSON.parse(d.giveItemIds || '[]') as string[], giveIds) &&
      idsEqual(JSON.parse(d.takeItemIds || '[]') as string[], takeIds) &&
      d.tix === tix
    ) {
      return NextResponse.json({ error: 'You already have that exact offer pending for them.' }, { status: 400 })
    }
  }

  const trade = await db.trade.create({
    data: {
      fromUserId: user.id,
      toUserId,
      giveItemIds: JSON.stringify(giveIds),
      takeItemIds: JSON.stringify(takeIds),
      tix,
      message,
    },
  })

  // tell the recipient (the bell)
  await db.notification.create({
    data: {
      userId: toUserId,
      type: 'trade_offer',
      dataJson: JSON.stringify({
        tradeId: trade.id,
        fromName: user.username,
        fromId: user.id,
        tix,
        giveCount: giveIds.length,
        takeCount: takeIds.length,
      }),
    },
  })

  return NextResponse.json({ ok: true, trade: { id: trade.id } })
}
