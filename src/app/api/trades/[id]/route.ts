import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * GET  /api/trades/[id] — one trade (participants only)
 * POST /api/trades/[id] — { action: 'accept' | 'decline' | 'cancel' | 'message', text? }
 *
 * accept — EVERYTHING moves inside ONE transaction: every offered item
 *          changes owner, the Tix move through the wallet + ledger. Any
 *          missing copy (traded away elsewhere in the meantime) fails the
 *          whole trade — half-trades can never happen.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const t = await db.trade.findUnique({
    where: { id },
    include: {
      fromUser: { select: { id: true, username: true, avatarUrl: true } },
      toUser: { select: { id: true, username: true, avatarUrl: true } },
    },
  })
  if (!t) return NextResponse.json({ error: 'Trade not found' }, { status: 404 })
  if (t.fromUserId !== user.id && t.toUserId !== user.id) {
    return NextResponse.json({ error: 'This trade is not yours.' }, { status: 403 })
  }
  return NextResponse.json({
    trade: {
      id: t.id,
      status: t.status,
      tix: t.tix,
      message: t.message,
      notes: JSON.parse(t.notesJson || '[]'),
      createdAt: t.createdAt,
      respondedAt: t.respondedAt,
      from: t.fromUser,
      to: t.toUser,
      give: JSON.parse(t.giveItemIds || '[]'),
      take: JSON.parse(t.takeItemIds || '[]'),
      isIncoming: t.toUserId === user.id,
    },
  })
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as { action?: string; text?: string }

  const t = await db.trade.findUnique({ where: { id } })
  if (!t) return NextResponse.json({ error: 'Trade not found' }, { status: 404 })
  const isIncoming = t.toUserId === user.id
  const isSender = t.fromUserId === user.id
  if (!isIncoming && !isSender) {
    return NextResponse.json({ error: 'This trade is not yours.' }, { status: 403 })
  }
  if (t.status !== 'pending' && body.action !== 'message') {
    return NextResponse.json({ error: `This trade was already ${t.status}.` }, { status: 400 })
  }

  const giveIds = JSON.parse(t.giveItemIds || '[]') as string[]
  const takeIds = JSON.parse(t.takeItemIds || '[]') as string[]

  // ---------------- message (both sides, while pending) ----------------
  if (body.action === 'message') {
    const text = String(body.text || '').trim().slice(0, 300)
    if (!text) return NextResponse.json({ error: 'Type a message first.' }, { status: 400 })
    if (t.status !== 'pending') {
      return NextResponse.json({ error: 'The trade is closed — no more messages.' }, { status: 400 })
    }
    const notes = JSON.parse(t.notesJson || '[]') as { userId: string; text: string; at: string }[]
    notes.push({ userId: user.id, text, at: new Date().toISOString() })
    await db.trade.update({ where: { id }, data: { notesJson: JSON.stringify(notes.slice(-30)) } })
    // notify the other side
    const otherId = isIncoming ? t.fromUserId : t.toUserId
    await db.notification.create({
      data: {
        userId: otherId,
        type: 'trade_message',
        dataJson: JSON.stringify({ tradeId: id, fromName: user.username }),
      },
    })
    return NextResponse.json({ ok: true })
  }

  // ---------------- cancel (sender only) ----------------
  if (body.action === 'cancel') {
    if (!isSender) return NextResponse.json({ error: 'Only the sender can cancel.' }, { status: 403 })
    await db.trade.update({ where: { id }, data: { status: 'cancelled', respondedAt: new Date() } })
    await db.notification.create({
      data: {
        userId: t.toUserId,
        type: 'trade_cancelled',
        dataJson: JSON.stringify({ tradeId: id, fromName: user.username }),
      },
    })
    return NextResponse.json({ ok: true, message: 'Trade cancelled.' })
  }

  // ---------------- decline (recipient only) ----------------
  if (body.action === 'decline') {
    if (!isIncoming) return NextResponse.json({ error: 'Only the recipient can decline.' }, { status: 403 })
    await db.trade.update({ where: { id }, data: { status: 'declined', respondedAt: new Date() } })
    await db.notification.create({
      data: {
        userId: t.fromUserId,
        type: 'trade_declined',
        dataJson: JSON.stringify({ tradeId: id, fromName: user.username }),
      },
    })
    return NextResponse.json({ ok: true, message: 'Offer declined.' })
  }

  // ---------------- accept (recipient only) — the atomic swap ----------------
  if (body.action === 'accept') {
    if (!isIncoming) return NextResponse.json({ error: 'Only the recipient can accept.' }, { status: 403 })
    try {
      const result = await db.$transaction(async (tx) => {
        // re-read inside the transaction — no racing accepts
        const fresh = await tx.trade.findUnique({ where: { id } })
        if (!fresh || fresh.status !== 'pending') throw new Error('This trade is no longer pending.')

        const missing: string[] = []
        // every offered item must still be owned by the right side
        if (giveIds.length > 0) {
          const rows = await tx.inventoryEntry.findMany({ where: { itemId: { in: giveIds } }, select: { itemId: true, userId: true } })
          for (const gid of giveIds) {
            const row = rows.find((r) => r.itemId === gid)
            if (!row || row.userId !== fresh.fromUserId) missing.push(gid)
          }
        }
        if (takeIds.length > 0) {
          const rows = await tx.inventoryEntry.findMany({ where: { itemId: { in: takeIds } }, select: { itemId: true, userId: true } })
          for (const tid of takeIds) {
            const row = rows.find((r) => r.itemId === tid)
            if (!row || row.userId !== fresh.toUserId) missing.push(tid)
          }
        }
        if (missing.length > 0) {
          throw new Error('Those items are not available anymore — the other side traded them away.')
        }

        // move the items: give -> recipient, take -> sender
        for (const gid of giveIds) {
          await tx.inventoryEntry.update({ where: { userId_itemId: { userId: fresh.fromUserId, itemId: gid } }, data: { userId: fresh.toUserId, acquiredAt: new Date() } })
        }
        for (const tid of takeIds) {
          await tx.inventoryEntry.update({ where: { userId_itemId: { userId: fresh.toUserId, itemId: tid } }, data: { userId: fresh.fromUserId, acquiredAt: new Date() } })
        }

        // move the Tix through the wallet + ledger
        if (fresh.tix > 0) {
          const sender = await tx.user.findUnique({ where: { id: fresh.fromUserId }, select: { rbxBalance: true, username: true } })
          const recipient = await tx.user.findUnique({ where: { id: fresh.toUserId }, select: { rbxBalance: true, username: true } })
          if (!sender || !recipient) throw new Error('Account missing.')
          if (sender.rbxBalance < fresh.tix) throw new Error('The sender no longer has enough Tix.')
          const senderAfter = sender.rbxBalance - fresh.tix
          const recipAfter = recipient.rbxBalance + fresh.tix
          await tx.user.update({ where: { id: fresh.fromUserId }, data: { rbxBalance: senderAfter } })
          await tx.user.update({ where: { id: fresh.toUserId }, data: { rbxBalance: recipAfter } })
          await tx.rbxTransaction.create({
            data: {
              userId: fresh.fromUserId,
              amount: -fresh.tix,
              type: 'trade_out',
              balanceBefore: sender.rbxBalance,
              balanceAfter: senderAfter,
              note: `Trade with ${recipient.username} — sent an offer`,
            },
          })
          await tx.rbxTransaction.create({
            data: {
              userId: fresh.toUserId,
              amount: fresh.tix,
              type: 'trade_in',
              balanceBefore: recipient.rbxBalance,
              balanceAfter: recipAfter,
              note: `Trade with ${sender.username} — offer accepted`,
            },
          })
        }

        await tx.trade.update({ where: { id }, data: { status: 'accepted', respondedAt: new Date() } })
        return { give: giveIds.length, take: takeIds.length, tix: fresh.tix }
      })

      await db.notification.create({
        data: {
          userId: t.fromUserId,
          type: 'trade_accepted',
          dataJson: JSON.stringify({ tradeId: id, fromName: user.username }),
        },
      })
      return NextResponse.json({ ok: true, message: `Trade accepted — ${result.give + result.take} item(s) swapped${result.tix > 0 ? ` + T$ ${result.tix}` : ''}!` })
    } catch (e) {
      return NextResponse.json({ error: e instanceof Error ? e.message : 'The trade could not be accepted.' }, { status: 400 })
    }
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
