import { NextRequest, NextResponse } from 'next/server'
import { getUserFromReq } from '@/lib/auth'
import { db } from '@/lib/db'
import { debitRbx, transferRbx, RbxError } from '@/lib/rbx'
import { PLATFORM_CORS } from '@/lib/platform'

/**
 * POST /api/rbx/spend
 *
 * In-game Tix spending endpoint called by the RetroBlox SDK's GamePassPrompt.
 * Headers: Authorization: Bearer <token>
 * Body: { amount: number, to?: string, note?: string, gameId?: string }
 *
 * - Validates the player's session token.
 * - If a recipient (`to` username/id) or `gameId` is provided (and not self),
 *   transfers the Tix directly to the recipient/creator wallet with full ledger records.
 * - If spending without a recipient or testing as the creator, debits the player's
 *   wallet atomically.
 * - Returns { ok: true, balanceAfter } with PLATFORM_CORS headers.
 */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json(
      { ok: false, error: 'Unauthorized: invalid or expired token' },
      { status: 401, headers: PLATFORM_CORS }
    )
  }

  const body = (await req.json().catch(() => ({}))) as {
    amount?: unknown
    to?: unknown
    note?: unknown
    gameId?: unknown
  }

  const amount = typeof body.amount === 'number' ? Math.floor(body.amount) : NaN
  if (!Number.isFinite(amount) || amount < 1) {
    return NextResponse.json(
      { ok: false, error: 'Spend amount must be at least 1 Tix (whole number).' },
      { status: 400, headers: PLATFORM_CORS }
    )
  }

  const toRaw = typeof body.to === 'string' ? body.to.trim() : ''
  const gameIdRaw = typeof body.gameId === 'string' || typeof body.gameId === 'number' ? String(body.gameId).trim() : ''
  let note = typeof body.note === 'string' ? body.note.trim() : ''

  try {
    let targetUsername = ''

    if (toRaw) {
      const cleanTo = toRaw.replace(/^@/, '')
      const recipient = await db.user.findFirst({
        where: {
          OR: [
            { username: cleanTo },
            { id: cleanTo },
          ],
        },
        select: { id: true, username: true },
      })
      if (recipient && recipient.id !== user.id) {
        targetUsername = recipient.username
      }
    } else if (gameIdRaw) {
      const isSeq = /^\d+$/.test(gameIdRaw)
      const game = await db.game.findFirst({
        where: {
          OR: [
            { id: gameIdRaw },
            ...(isSeq ? [{ seqId: Number(gameIdRaw) }] : []),
          ],
        },
        select: {
          id: true,
          name: true,
          creator: { select: { id: true, username: true } },
        },
      })
      if (game?.creator && game.creator.id !== user.id) {
        targetUsername = game.creator.username
        if (!note) {
          note = `Game pass purchase in ${game.name}`
        }
      }
    }

    let balanceAfter: number

    if (targetUsername) {
      const res = await transferRbx({
        fromUserId: user.id,
        toUsername: targetUsername,
        amount,
        note: note || (gameIdRaw ? `Game pass in game #${gameIdRaw}` : 'In-game purchase'),
      })
      balanceAfter = res.balanceAfter
    } else {
      const res = await debitRbx({
        userId: user.id,
        amount,
        type: 'spend',
        note: note || (gameIdRaw ? `In-game purchase (game #${gameIdRaw})` : 'In-game spend'),
      })
      balanceAfter = res.balanceAfter
    }

    return NextResponse.json(
      { ok: true, balanceAfter },
      { headers: PLATFORM_CORS }
    )
  } catch (e) {
    if (e instanceof RbxError) {
      return NextResponse.json(
        { ok: false, error: e.message, code: e.code },
        { status: 400, headers: PLATFORM_CORS }
      )
    }
    console.error('[rbx/spend] error:', e)
    return NextResponse.json(
      { ok: false, error: 'Failed to process in-game spend request.' },
      { status: 500, headers: PLATFORM_CORS }
    )
  }
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
