import { db } from '@/lib/db'
import { limitedPrice } from '@/lib/avatarAssets'

/* ------------------------------------------------------------------
   RBX WALLET LEDGER — every balance change goes through here.
   Rules:
   - the balance column is ONLY moved inside the same transaction that
     writes the ledger row (atomic, no read-then-write races)
   - stripeEventId is UNIQUE: a retried webhook can never credit twice
   - reversals clamp to the available balance so a refund after the
     player spent the RBX can't push a wallet negative (the shortfall
     is noted on the ledger row instead)
------------------------------------------------------------------ */

export class RbxError extends Error {
  code: string
  constructor(code: string, message: string) {
    super(message)
    this.code = code
  }
}

/** The classic starter packages — seeded once, then editable in /admin. */
export const DEFAULT_PACKAGES = [
  { code: 'PACKAGE_100', name: '100 RBX', rbxAmount: 100, priceCents: 99, sortOrder: 1 },
  { code: 'PACKAGE_550', name: '550 RBX', rbxAmount: 550, priceCents: 499, sortOrder: 2 },
  { code: 'PACKAGE_1200', name: '1,200 RBX', rbxAmount: 1200, priceCents: 999, sortOrder: 3 },
  { code: 'PACKAGE_2500', name: '2,500 RBX', rbxAmount: 2500, priceCents: 1999, sortOrder: 4 },
  { code: 'PACKAGE_6500', name: '6,500 RBX', rbxAmount: 6500, priceCents: 4999, sortOrder: 5 },
  { code: 'PACKAGE_14000', name: '14,000 RBX', rbxAmount: 14000, priceCents: 9999, sortOrder: 6 },
]

/** Seed the classic packages once (existing rows are never touched —
 *  the admin panel owns them after that). */
export async function ensurePackages() {
  for (const p of DEFAULT_PACKAGES) {
    const existing = await db.rbxPackage.findUnique({ where: { code: p.code }, select: { id: true } })
    if (!existing) await db.rbxPackage.create({ data: p })
  }
}

export interface GrantOpts {
  userId: string
  amount: number // > 0 normally; negative allowed for admin corrections (never below 0)
  type: 'purchase' | 'admin_grant'
  note?: string
  packageId?: string
  stripeEventId?: string
  stripePaymentIntentId?: string
}

export interface GrantResult {
  duplicate: boolean
  balanceAfter: number
}

/** Credit (or admin-adjust) a wallet. When stripeEventId is given and was
 *  already processed, this is a no-op that reports duplicate:true. */
export async function grantRbx(opts: GrantOpts): Promise<GrantResult> {
  if (!Number.isInteger(opts.amount) || opts.amount === 0) {
    throw new RbxError('BAD_AMOUNT', 'The RBX amount must be a non-zero whole number.')
  }
  if (opts.amount > 0 && opts.type !== 'purchase' && opts.type !== 'admin_grant') {
    throw new RbxError('BAD_TYPE', 'Credits are only allowed for purchases and admin grants.')
  }

  try {
    return await db.$transaction(async (tx) => {
      if (opts.stripeEventId) {
        const seen = await tx.rbxTransaction.findUnique({ where: { stripeEventId: opts.stripeEventId! }, select: { id: true } })
        if (seen) {
          const u = await tx.user.findUnique({ where: { id: opts.userId }, select: { rbxBalance: true } })
          return { duplicate: true, balanceAfter: u?.rbxBalance ?? 0 }
        }
      }
      const u = await tx.user.findUnique({ where: { id: opts.userId }, select: { rbxBalance: true } })
      if (!u) throw new RbxError('NO_USER', 'That account does not exist.')
      const before = u.rbxBalance
      const after = before + opts.amount
      if (after < 0) {
        throw new RbxError('NEGATIVE', 'This adjustment would push the balance below zero.')
      }
      await tx.user.update({ where: { id: opts.userId }, data: { rbxBalance: after } })
      await tx.rbxTransaction.create({
        data: {
          userId: opts.userId,
          amount: opts.amount,
          type: opts.type,
          balanceBefore: before,
          balanceAfter: after,
          note: opts.note || '',
          packageId: opts.packageId,
          stripeEventId: opts.stripeEventId,
          stripePaymentIntentId: opts.stripePaymentIntentId,
        },
      })
      return { duplicate: false, balanceAfter: after }
    })
  } catch (e) {
    // two webhook deliveries racing on the SAME event: the unique index is
    // the final judge — the loser rolls back cleanly as a duplicate
    if (opts.stripeEventId && typeof e === 'object' && e !== null && 'code' in e && (e as { code?: string }).code === 'P2002') {
      const u = await db.user.findUnique({ where: { id: opts.userId }, select: { rbxBalance: true } })
      return { duplicate: true, balanceAfter: u?.rbxBalance ?? 0 }
    }
    throw e
  }
}

export interface DebitOpts {
  userId: string
  amount: number // > 0
  type: 'spend' | 'reversal'
  note?: string
  packageId?: string
  stripeEventId?: string
  stripePaymentIntentId?: string
  /** refunds clamp to the available balance instead of failing */
  clampToBalance?: boolean
}

export interface DebitResult {
  applied: number
  balanceAfter: number
  clamped: boolean
}

/** Debit a wallet (catalog purchases, refund reversals). Atomic with the ledger row. */
export async function debitRbx(opts: DebitOpts): Promise<DebitResult> {
  if (!Number.isInteger(opts.amount) || opts.amount <= 0) {
    throw new RbxError('BAD_AMOUNT', 'The RBX amount must be a positive whole number.')
  }
  return db.$transaction(async (tx) => {
    if (opts.stripeEventId) {
      const seen = await tx.rbxTransaction.findUnique({ where: { stripeEventId: opts.stripeEventId! }, select: { id: true } })
      if (seen) {
        const u = await tx.user.findUnique({ where: { id: opts.userId }, select: { rbxBalance: true } })
        return { applied: 0, balanceAfter: u?.rbxBalance ?? 0, clamped: false }
      }
    }
    const u = await tx.user.findUnique({ where: { id: opts.userId }, select: { rbxBalance: true } })
    if (!u) throw new RbxError('NO_USER', 'That account does not exist.')
    let applied = opts.amount
    let clamped = false
    if (u.rbxBalance < applied) {
      if (opts.clampToBalance) {
        applied = u.rbxBalance
        clamped = true
      } else {
        throw new RbxError('INSUFFICIENT', 'Not enough RBX.')
      }
    }
    if (applied > 0 || clamped) {
      // clamped reversals still write their row (amount 0 when the wallet was
      // already empty) — the shortfall stays visible in the audit trail
      const before = u.rbxBalance
      const after = before - applied
      await tx.user.update({ where: { id: opts.userId }, data: { rbxBalance: after } })
      await tx.rbxTransaction.create({
        data: {
          userId: opts.userId,
          amount: -applied,
          type: opts.type,
          balanceBefore: before,
          balanceAfter: after,
          note: clamped ? `${opts.note || ''} [clamped: wallet held less than the reversal]`.trim() : opts.note || '',
          packageId: opts.packageId,
          stripeEventId: opts.stripeEventId,
          stripePaymentIntentId: opts.stripePaymentIntentId,
        },
      })
      return { applied, balanceAfter: after, clamped }
    }
    return { applied: 0, balanceAfter: u.rbxBalance, clamped: false }
  })
}

/* ------------------------------------------------------------------
   LIMITED PRICING — the price DOUBLES as copies sell. A limited's
   `price` column is the ORIGINAL price; every sold copy pushes the
   next buyer's price to 2x (classic scarcity).
   The sold count is always the REAL inventory row count, read inside
   the purchase transaction so two buyers can never race a price.
------------------------------------------------------------------ */

/** The price a BUYER pays for a catalog item.
 *  - normal items: exactly what the creator set
 *  - limiteds: the rising price (original x2 per sold copy) — pass the
 *    sold count you read INSIDE your transaction, never a stale one. */
export function buyPrice(
  item: { price: number; isLimited: boolean },
  soldCount = 0
): number {
  return item.isLimited ? limitedPrice(item.price, soldCount) : item.price
}

/* ------------------------------------------------------------------
   P2P TRANSFERS — send Tix to another player, straight from your
   wallet. Same atomic rules as everything else: both balances move
   inside ONE transaction, both sides get a ledger row, and a sender
   can never send more than they have or send to themselves.
------------------------------------------------------------------ */

export interface TransferOpts {
  fromUserId: string
  toUsername: string
  amount: number
  note?: string
}

export interface TransferResult {
  balanceAfter: number
  recipient: { id: string; username: string; balanceAfter: number }
}

export async function transferRbx(opts: TransferOpts): Promise<TransferResult> {
  if (!Number.isInteger(opts.amount) || opts.amount < 1) {
    throw new RbxError('BAD_AMOUNT', 'Send at least 1 Tix (whole numbers only).')
  }
  const toUsername = opts.toUsername.trim().replace(/^@/, '')
  if (!toUsername) throw new RbxError('NO_RECIPIENT', 'Type who should get the Tix.')

  return db.$transaction(async (tx) => {
    const sender = await tx.user.findUnique({
      where: { id: opts.fromUserId },
      select: { id: true, username: true, rbxBalance: true },
    })
    if (!sender) throw new RbxError('NO_USER', 'That account does not exist.')

    const recipient = await tx.user.findUnique({
      where: { username: toUsername },
      select: { id: true, username: true, rbxBalance: true },
    })
    if (!recipient) throw new RbxError('NO_RECIPIENT', `No player named "${toUsername}" exists.`)
    if (recipient.id === sender.id) {
      throw new RbxError('SELF', 'You cannot send Tix to yourself!')
    }
    if (sender.rbxBalance < opts.amount) {
      throw new RbxError(
        'NO_FUNDS',
        `You only have ${sender.rbxBalance.toLocaleString('en-US')} Tix — that is not enough.`
      )
    }

    const senderAfter = sender.rbxBalance - opts.amount
    const recipientAfter = recipient.rbxBalance + opts.amount

    await tx.user.update({ where: { id: sender.id }, data: { rbxBalance: senderAfter } })
    await tx.user.update({ where: { id: recipient.id }, data: { rbxBalance: recipientAfter } })

    const note = opts.note?.slice(0, 140) || ''
    await tx.rbxTransaction.create({
      data: {
        userId: sender.id,
        amount: -opts.amount,
        type: 'transfer_sent',
        balanceBefore: sender.rbxBalance,
        balanceAfter: senderAfter,
        note: note ? `Sent to ${recipient.username} — ${note}` : `Sent to ${recipient.username}`,
      },
    })
    await tx.rbxTransaction.create({
      data: {
        userId: recipient.id,
        amount: opts.amount,
        type: 'transfer_received',
        balanceBefore: recipient.rbxBalance,
        balanceAfter: recipientAfter,
        note: note ? `From ${sender.username} — ${note}` : `From ${sender.username}`,
      },
    })

    return {
      balanceAfter: senderAfter,
      recipient: { id: recipient.id, username: recipient.username, balanceAfter: recipientAfter },
    }
  })
}
