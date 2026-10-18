import { Prisma } from '@prisma/client'
import { db } from '@/lib/db'

/* ------------------------------------------------------------------
   UGC MARKET — the player-to-player economy layer.

   The classic limited loop:
     1. A player buys a limited from its creator (the rising ladder).
     2. The suggested RESALE value is 1.5x what they paid — so every
        hand-off can be a profit ("you can make infinite Tix by buying
        and selling at 1.5x the price"), IF the other side wants it.
     3. Buyers haggle in the listing chat, send Tix offers the seller
        is free to take or leave, or offer item-for-item trades.

   Everything here is atomic: items and Tix only ever move inside ONE
   transaction, verified against fresh rows — never a stale snapshot.
------------------------------------------------------------------ */

export type Tx = Prisma.TransactionClient

/** The resale multiplier — the profit loop the market runs on. */
export const RESALE_MULTIPLIER = 1.5

/* Robux has left the economy: Tix is the only money on RetroBlox. The old
   moveRobux / exchangeCurrency helpers and the exchange rates were removed
   with it (the exchange desk answers 410 Gone via /api/rbx/balance POST). */

/** Suggested resale value for a copy: 1.5x what the owner paid
 *  (rounded up). `paid` 0 = the creator's own master copy — the site
 *  suggests 1.5x the item's ORIGINAL price for those. */
export function resaleValue(paid: number, originalPrice: number): number {
  const base = paid > 0 ? paid : originalPrice
  return Math.max(1, Math.ceil(base * RESALE_MULTIPLIER))
}

/** Create a notification row (never throws — a failed bell must not
 *  kill a trade). */
export async function notify(
  userId: string,
  n: { type: string; title: string; body?: string; link?: string; data?: Record<string, unknown> }
) {
  try {
    await db.notification.create({
      data: {
        userId,
        type: n.type,
        title: n.title.slice(0, 120),
        body: (n.body || '').slice(0, 300),
        link: n.link || '',
        dataJson: JSON.stringify(n.data || {}),
      },
    })
  } catch (e) {
    console.error('[market] notify failed:', e)
  }
}

/** Record a REAL sale for the item's market-history graph. */
export async function pricePoint(
  tx: Tx,
  itemId: string,
  price: number,
  kind: 'mint' | 'resale' | 'trade',
  buyerId: string,
  sellerId?: string | null
) {
  await tx.ugcPricePoint.create({
    data: { itemId, price, kind, buyerId, sellerId: sellerId ?? null },
  })
}

/** Move Tix between two wallets inside a transaction, with ledger rows.
 *  Both balances are read fresh in the SAME transaction — no races. */
export async function moveTix(
  tx: Tx,
  fromId: string,
  toId: string,
  amount: number,
  note: string
) {
  if (amount <= 0) return
  const from = await tx.user.findUnique({ where: { id: fromId }, select: { username: true, rbxBalance: true } })
  if (!from) throw new MarketError('NO_USER', 'That account does not exist.')
  if (from.rbxBalance < amount) {
    throw new MarketError(
      'NO_FUNDS',
      `${from.username} only has T$ ${from.rbxBalance.toLocaleString('en-US')} — not enough for this trade.`
    )
  }
  const to = await tx.user.findUnique({ where: { id: toId }, select: { rbxBalance: true } })
  if (!to) throw new MarketError('NO_USER', 'That account does not exist.')

  const fromAfter = from.rbxBalance - amount
  const toAfter = to.rbxBalance + amount
  await tx.user.update({ where: { id: fromId }, data: { rbxBalance: fromAfter } })
  await tx.user.update({ where: { id: toId }, data: { rbxBalance: toAfter } })
  await tx.rbxTransaction.create({
    data: { userId: fromId, amount: -amount, currency: 'tix', type: 'transfer_sent', balanceBefore: from.rbxBalance, balanceAfter: fromAfter, note },
  })
  await tx.rbxTransaction.create({
    data: { userId: toId, amount, currency: 'tix', type: 'transfer_received', balanceBefore: to.rbxBalance, balanceAfter: toAfter, note },
  })
}

/** Hand ONE item copy from one player to another inside a transaction.
 *  - verifies the sender still owns it (fresh read)
 *  - the recipient must not already own a copy of the same item
 *    (one copy per member per item, classic rule)
 *  - the copy's LIMITED serial number travels with it
 *  - any active listing the sender had on it is cancelled (the copy
 *    just changed hands behind that listing's back) */
export async function transferItem(tx: Tx, itemId: string, fromUserId: string, toUserId: string) {
  const entry = await tx.inventoryEntry.findUnique({
    where: { userId_itemId: { userId: fromUserId, itemId } },
    select: { id: true, serial: true },
  })
  if (!entry) throw new MarketError('NOT_OWNED', 'One of the traded items is no longer in that player\u2019s inventory.')

  const clash = await tx.inventoryEntry.findUnique({
    where: { userId_itemId: { userId: toUserId, itemId } },
    select: { id: true },
  })
  if (clash) {
    const item = await tx.avatarItem.findUnique({ where: { id: itemId }, select: { name: true } })
    throw new MarketError('ALREADY_OWNED', `They already own "${item?.name || 'that item'}" — one copy per member.`)
  }

  await tx.inventoryEntry.delete({ where: { id: entry.id } })
  await tx.inventoryEntry.create({ data: { userId: toUserId, itemId, serial: entry.serial } })

  // any active listing by the OLD owner for this item dies with the sale
  await tx.ugcListing.updateMany({
    where: { itemId, sellerId: fromUserId, status: 'active' },
    data: { status: 'cancelled' },
  })
}

/** Verify a player owns every item id (fresh read, inside a tx). */
export async function assertOwnsAll(tx: Tx, userId: string, itemIds: string[]) {
  for (const itemId of itemIds) {
    const row = await tx.inventoryEntry.findUnique({
      where: { userId_itemId: { userId, itemId } },
      select: { id: true },
    })
    if (!row) {
      const item = await tx.avatarItem.findUnique({ where: { id: itemId }, select: { name: true } })
      throw new MarketError('NOT_OWNED', `You no longer own "${item?.name || 'one of the items'}".`)
    }
  }
}

export class MarketError extends Error {
  code: string
  constructor(code: string, message: string) {
    super(message)
    this.code = code
  }
}

/** Parse a JSON string-array column (giveItemIds / takeItemIds). */
export function parseIdArray(raw: string | null | undefined): string[] {
  try {
    const v = JSON.parse(raw || '[]')
    return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []
  } catch {
    return []
  }
}

/** What the current owner paid for their copy — the latest price point
 *  bought by THEM (resale > mint). 0 when unknown (creators etc.). */
export async function paidByOwner(itemId: string, ownerId: string): Promise<number> {
  const rows = await db.ugcPricePoint.findMany({
    where: { itemId, buyerId: ownerId },
    orderBy: { createdAt: 'desc' },
    take: 1,
    select: { price: true },
  })
  return rows[0]?.price ?? 0
}
