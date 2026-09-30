import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { MarketError, assertOwnsAll, notify, parseIdArray } from '@/lib/market'

/**
 * GET /api/trades — my pending trades (incoming + outgoing) with item previews
 * POST /api/trades — offer a trade: { toUsername, giveItemIds[], takeItemIds[], tix, message? }
 *
 * A trade is items (+ optional Tix) for items: the recipient gets a
 * notification, chats back ("throw in the Dominus and it's a deal"),
 * counters, accepts or declines. Accepting moves everything atomically.
 */
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const include = {
    fromUser: { select: { id: true, username: true, avatarUrl: true } },
    toUser: { select: { id: true, username: true, avatarUrl: true } },
    messages: { orderBy: { createdAt: 'desc' as const }, take: 1, include: { sender: { select: { id: true, username: true } } } },
  }

  const [incoming, outgoing] = await Promise.all([
    db.ugcTrade.findMany({ where: { toUserId: me.id, status: 'pending' }, orderBy: { updatedAt: 'desc' }, take: 25, include }),
    db.ugcTrade.findMany({ where: { fromUserId: me.id, status: 'pending' }, orderBy: { updatedAt: 'desc' }, take: 25, include }),
  ])

  // one pass for every item preview the two lists need
  const ids = new Set<string>()
  for (const t of [...incoming, ...outgoing]) {
    for (const id of parseIdArray(t.giveItemIds)) ids.add(id)
    for (const id of parseIdArray(t.takeItemIds)) ids.add(id)
  }
  const items = await db.avatarItem.findMany({
    where: { id: { in: [...ids] } },
    select: { id: true, name: true, type: true, imageFileId: true, isLimited: true },
  })
  const itemMap = Object.fromEntries(items.map((i) => [i.id, i]))

  return NextResponse.json({ incoming, outgoing, itemMap })
}

const MAX_ITEMS_PER_SIDE = 8

export async function POST(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>

  const toUsername = String(body.toUsername || '').trim().replace(/^@/, '')
  const toUserId = String(body.toUserId || '').trim()
  const giveItemIds = [...new Set(parseIdArray(JSON.stringify(body.giveItemIds ?? [])))]
  const takeItemIds = [...new Set(parseIdArray(JSON.stringify(body.takeItemIds ?? [])))]
  const tix = Math.max(0, Math.floor(Number(body.tix) || 0))
  const message = String(body.message || '').trim().slice(0, 300)

  if (!giveItemIds.length && !takeItemIds.length && tix <= 0) {
    return NextResponse.json({ error: 'Offer at least one item or some Tix — an empty trade is just a handshake.' }, { status: 400 })
  }
  if (giveItemIds.length > MAX_ITEMS_PER_SIDE || takeItemIds.length > MAX_ITEMS_PER_SIDE) {
    return NextResponse.json({ error: `Keep it to ${MAX_ITEMS_PER_SIDE} items per side.` }, { status: 400 })
  }

  const target = toUserId
    ? await db.user.findUnique({ where: { id: toUserId } })
    : await db.user.findUnique({ where: { username: toUsername } })
  if (!target) return NextResponse.json({ error: `No player named "${toUsername || toUserId}" exists.` }, { status: 404 })
  if (target.id === me.id) return NextResponse.json({ error: 'You cannot trade with yourself!' }, { status: 400 })

  // sanity: I own what I give; they own what I ask for; I have the Tix
  try {
    await db.$transaction(async (tx) => {
      await assertOwnsAll(tx, me.id, giveItemIds)
      await assertOwnsAll(tx, target.id, takeItemIds)
      if (tix > 0) {
        const u = await tx.user.findUnique({ where: { id: me.id }, select: { rbxBalance: true } })
        if (!u || u.rbxBalance < tix) throw new MarketError('NO_FUNDS', `You only have T$ ${(u?.rbxBalance ?? 0).toLocaleString('en-US')} — not enough for this offer.`)
      }
    })
  } catch (e) {
    if (e instanceof MarketError) return NextResponse.json({ error: e.message }, { status: 400 })
    throw e
  }

  const trade = await db.ugcTrade.create({
    data: {
      fromUserId: me.id,
      toUserId: target.id,
      giveItemIds: JSON.stringify(giveItemIds),
      takeItemIds: JSON.stringify(takeItemIds),
      tixFrom: tix,
    },
  })
  if (message) {
    await db.ugcTradeMessage.create({ data: { tradeId: trade.id, senderId: me.id, text: message } })
  }

  await notify(target.id, {
    type: 'trade_offer',
    title: `${me.username} wants to trade with you!`,
    body: message
      ? `"${message}"`
      : `${giveItemIds.length} item(s)${tix > 0 ? ` + T$ ${tix.toLocaleString('en-US')}` : ''} on the table — take a look before it's gone.`,
    link: `/trades/${trade.id}`,
    data: { tradeId: trade.id },
  })

  return NextResponse.json({ ok: true, tradeId: trade.id, message: 'Trade offer sent!' })
}
