import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { MarketError, assertOwnsAll, moveTix, transferItem, notify, parseIdArray } from '@/lib/market'

/**
 * GET  /api/trades/[id] — the trade, item details and the negotiation chat (both parties only)
 * POST /api/trades/[id] — { action, ... }
 *   message {text}                                chat ("throw in the Dominus and it's a deal")
 *   counter {giveItemIds, takeItemIds, tixFrom, tixTo}   edit the terms and send it back
 *   accept  {}                                    BOTH sides confirm here: items + Tix swap atomically
 *   decline {}                                    no deal
 *   cancel  {}                                    the sender takes it back
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const trade = await db.ugcTrade.findUnique({
    where: { id },
    include: {
      fromUser: { select: { id: true, username: true, avatarUrl: true } },
      toUser: { select: { id: true, username: true, avatarUrl: true } },
    },
  })
  if (!trade) return NextResponse.json({ error: 'Trade not found' }, { status: 404 })
  if (trade.fromUserId !== me.id && trade.toUserId !== me.id) {
    return NextResponse.json({ error: 'This trade is not yours.' }, { status: 403 })
  }

  const messages = await db.ugcTradeMessage.findMany({
    where: { tradeId: id },
    orderBy: { createdAt: 'asc' },
    take: 100,
    include: { sender: { select: { id: true, username: true, avatarUrl: true } } },
  })

  const ids = [...new Set([...parseIdArray(trade.giveItemIds), ...parseIdArray(trade.takeItemIds)])]
  const items = await db.avatarItem.findMany({
    where: { id: { in: ids } },
    select: { id: true, name: true, type: true, imageFileId: true, isLimited: true, price: true, stock: true },
  })
  const itemMap = Object.fromEntries(items.map((i) => [i.id, i]))

  // live ownership flags — the UI shows exactly what still makes sense
  const mineEntries = await db.inventoryEntry.findMany({ where: { userId: me.id, itemId: { in: ids } }, select: { itemId: true } })
  const iStillOwn = new Set(mineEntries.map((e) => e.itemId))

  return NextResponse.json({
    trade: {
      id: trade.id,
      status: trade.status,
      fromUserId: trade.fromUserId,
      toUserId: trade.toUserId,
      fromUser: trade.fromUser,
      toUser: trade.toUser,
      giveItemIds: parseIdArray(trade.giveItemIds),
      takeItemIds: parseIdArray(trade.takeItemIds),
      tixFrom: trade.tixFrom,
      tixTo: trade.tixTo,
      createdAt: trade.createdAt,
      updatedAt: trade.updatedAt,
    },
    itemMap,
    iStillOwn: [...iStillOwn],
    messages,
  })
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
  const action = String(body.action || '')

  const trade = await db.ugcTrade.findUnique({ where: { id } })
  if (!trade) return NextResponse.json({ error: 'Trade not found' }, { status: 404 })
  const isSender = trade.fromUserId === me.id
  const isRecipient = trade.toUserId === me.id
  if (!isSender && !isRecipient) return NextResponse.json({ error: 'This trade is not yours.' }, { status: 403 })
  const otherId = isSender ? trade.toUserId : trade.fromUserId

  // ---------------- chat ----------------
  if (action === 'message') {
    const text = String(body.text || '').trim().slice(0, 300)
    if (!text) return NextResponse.json({ error: 'Type a message first.' }, { status: 400 })
    await db.ugcTradeMessage.create({ data: { tradeId: id, senderId: me.id, text } })
    if (trade.status === 'pending') {
      await notify(otherId, {
        type: 'trade_message',
        title: `${me.username} replied to the trade`,
        body: text.slice(0, 140),
        link: '/trades',
        data: { tradeId: id },
      })
    }
    return NextResponse.json({ ok: true })
  }

  // ---------------- counter (edit the terms) ----------------
  if (action === 'counter') {
    if (trade.status !== 'pending') return NextResponse.json({ error: 'This trade is already settled.' }, { status: 400 })
    const giveItemIds = [...new Set(parseIdArray(JSON.stringify(body.giveItemIds ?? [])))]
    const takeItemIds = [...new Set(parseIdArray(JSON.stringify(body.takeItemIds ?? [])))]
    const tixFrom = Math.max(0, Math.floor(Number(body.tixFrom) || 0))
    const tixTo = Math.max(0, Math.floor(Number(body.tixTo) || 0))
    if (!giveItemIds.length && !takeItemIds.length && !tixFrom && !tixTo) {
      return NextResponse.json({ error: 'A counter still needs something on the table.' }, { status: 400 })
    }
    if (giveItemIds.length > 8 || takeItemIds.length > 8) {
      return NextResponse.json({ error: 'Keep it to 8 items per side.' }, { status: 400 })
    }
    await db.$transaction(async (tx) => {
      // the counter's terms keep the ORIGINAL directions: give = from the
      // trade's sender, take = from its recipient — whoever counters just
      // reshuffles what sits on each side
      await assertOwnsAll(tx, trade.fromUserId, giveItemIds)
      await assertOwnsAll(tx, trade.toUserId, takeItemIds)
    })
    await db.ugcTrade.update({
      where: { id },
      data: { giveItemIds: JSON.stringify(giveItemIds), takeItemIds: JSON.stringify(takeItemIds), tixFrom, tixTo },
    })
    await notify(otherId, {
      type: 'trade_offer',
      title: `${me.username} countered the trade`,
      body: 'The terms changed — look again before you accept.',
      link: '/trades',
      data: { tradeId: id },
    })
    return NextResponse.json({ ok: true, message: 'Counter sent.' })
  }

  // ---------------- ACCEPT — the swap ----------------
  if (action === 'accept') {
    if (trade.status !== 'pending') return NextResponse.json({ error: 'This trade is already settled.' }, { status: 400 })
    const giveItemIds = parseIdArray(trade.giveItemIds)
    const takeItemIds = parseIdArray(trade.takeItemIds)
    const result = await db.$transaction(async (tx) => {
      // fresh ownership checks — stale offers can never teleport items
      await assertOwnsAll(tx, trade.fromUserId, giveItemIds)
      await assertOwnsAll(tx, trade.toUserId, takeItemIds)
      // Tix both ways (moveTix throws a friendly error on insufficient funds)
      if (trade.tixFrom > 0) await moveTix(tx, trade.fromUserId, trade.toUserId, trade.tixFrom, 'Trade')
      if (trade.tixTo > 0) await moveTix(tx, trade.toUserId, trade.fromUserId, trade.tixTo, 'Trade')
      // items cross — give: fromUser -> toUser, take: toUser -> fromUser
      for (const itemId of giveItemIds) await transferItem(tx, itemId, trade.fromUserId, trade.toUserId)
      for (const itemId of takeItemIds) await transferItem(tx, itemId, trade.toUserId, trade.fromUserId)
      await tx.ugcTrade.update({ where: { id }, data: { status: 'accepted' } })
      return { giveCount: giveItemIds.length, takeCount: takeItemIds.length }
    })
    await notify(otherId, {
      type: 'trade_accepted',
      title: 'Trade accepted!',
      body: `${me.username} accepted — check your inventory, the items and Tix have moved.`,
      link: '/trades',
      data: { tradeId: id },
    })
    return NextResponse.json({ ok: true, message: `Trade complete — ${result.giveCount + result.takeCount} item(s) changed hands!` })
  }

  // ---------------- decline / cancel ----------------
  if (action === 'decline' || action === 'cancel') {
    if (trade.status !== 'pending') return NextResponse.json({ error: 'This trade is already settled.' }, { status: 400 })
    if (action === 'decline' && !isRecipient && !isSender) return NextResponse.json({ error: 'Not your trade.' }, { status: 403 })
    await db.ugcTrade.update({ where: { id }, data: { status: action === 'decline' ? 'declined' : 'cancelled' } })
    await notify(otherId, {
      type: action === 'decline' ? 'trade_declined' : 'trade_cancelled',
      title: action === 'decline' ? `${me.username} declined the trade` : `${me.username} cancelled the trade`,
      body: 'Nothing moved — the offer is off the table.',
      link: '/trades',
      data: { tradeId: id },
    })
    return NextResponse.json({ ok: true, message: action === 'decline' ? 'Trade declined.' : 'Trade cancelled.' })
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
