import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

function getClientIp(req: NextRequest): string {
  const forwarded = req.headers.get('x-forwarded-for')
  if (forwarded) return forwarded.split(',')[0].trim()
  const realIp = req.headers.get('x-real-ip')
  if (realIp) return realIp.trim()
  return '127.0.0.1'
}

export async function GET(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const ip = getClientIp(req)
  const fullUser = await db.user.findUnique({
    where: { id: user.id },
    select: { id: true, username: true, rbxBalance: true, bankBalance: true, role: true },
  })
  if (!fullUser) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  // Find active unpaid loan for this user OR this IP
  const activeLoan = await db.bankLoan.findFirst({
    where: {
      OR: [
        { userId: user.id, repaid: false },
        { ipAddress: ip, repaid: false },
      ],
    },
    orderBy: { createdAt: 'desc' },
  })

  const isAdmin = fullUser.role === 'admin' || fullUser.username.toLowerCase() === 'nexico8225'

  return NextResponse.json({
    walletBalance: fullUser.rbxBalance ?? 10,
    bankBalance: fullUser.bankBalance ?? 0,
    activeLoan: activeLoan
      ? {
          id: activeLoan.id,
          amount: activeLoan.amount,
          createdAt: activeLoan.createdAt,
          isUserLoan: activeLoan.userId === user.id,
        }
      : null,
    canLoan: !activeLoan,
    maxLoan: 500,
    isAdmin,
  })
}

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const ip = getClientIp(req)
  const body = (await req.json().catch(() => ({}))) as {
    action?: 'deposit' | 'withdraw' | 'loan' | 'repay_loan' | 'admin_mint' | 'sell_to_website'
    amount?: number
    itemId?: string
  }

  const action = body.action
  const fullUser = await db.user.findUnique({
    where: { id: user.id },
    select: { id: true, username: true, rbxBalance: true, bankBalance: true, role: true },
  })
  if (!fullUser) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  const isAdmin = fullUser.role === 'admin' || fullUser.username.toLowerCase() === 'nexico8225'

  // 1. DEPOSIT: move Tix from wallet to RetroBank
  if (action === 'deposit') {
    const amount = Math.floor(Number(body.amount) || 0)
    if (amount <= 0) return NextResponse.json({ error: 'Deposit amount must be at least 1 Tix.' }, { status: 400 })
    if (fullUser.rbxBalance < amount) return NextResponse.json({ error: 'Not enough Tix in your wallet.' }, { status: 400 })

    await db.user.update({
      where: { id: user.id },
      data: {
        rbxBalance: fullUser.rbxBalance - amount,
        bankBalance: (fullUser.bankBalance ?? 0) + amount,
      },
    })
    return NextResponse.json({ ok: true, message: `Deposited T$ ${amount.toLocaleString('en-US')} into RetroBank.` })
  }

  // 2. WITHDRAW: move Tix from RetroBank to wallet
  if (action === 'withdraw') {
    const amount = Math.floor(Number(body.amount) || 0)
    if (amount <= 0) return NextResponse.json({ error: 'Withdraw amount must be at least 1 Tix.' }, { status: 400 })
    if ((fullUser.bankBalance ?? 0) < amount) return NextResponse.json({ error: 'Not enough Tix in your RetroBank vault.' }, { status: 400 })

    await db.user.update({
      where: { id: user.id },
      data: {
        rbxBalance: fullUser.rbxBalance + amount,
        bankBalance: (fullUser.bankBalance ?? 0) - amount,
      },
    })
    return NextResponse.json({ ok: true, message: `Withdrew T$ ${amount.toLocaleString('en-US')} to your wallet.` })
  }

  // 3. LOAN: borrow up to 500 Tix (enforcing 1 loan per IP until repaid)
  if (action === 'loan') {
    const amount = Math.floor(Number(body.amount) || 0)
    if (amount <= 0 || amount > 500) {
      return NextResponse.json({ error: 'You can loan between 1 and 500 Tix.' }, { status: 400 })
    }

    // Check if an active unpaid loan exists for this IP or this user
    const existing = await db.bankLoan.findFirst({
      where: {
        OR: [
          { userId: user.id, repaid: false },
          { ipAddress: ip, repaid: false },
        ],
      },
    })
    if (existing) {
      return NextResponse.json(
        { error: 'An active unpaid loan already exists for this IP address or account. Repay it first.' },
        { status: 400 }
      )
    }

    await db.$transaction([
      db.bankLoan.create({
        data: {
          userId: user.id,
          ipAddress: ip,
          amount,
          repaid: false,
        },
      }),
      db.user.update({
        where: { id: user.id },
        data: {
          rbxBalance: fullUser.rbxBalance + amount,
        },
      }),
    ])

    return NextResponse.json({ ok: true, message: `Bank loan of T$ ${amount.toLocaleString('en-US')} approved and credited to your wallet!` })
  }

  // 4. REPAY LOAN: pay back active loan
  if (action === 'repay_loan') {
    const loan = await db.bankLoan.findFirst({
      where: { userId: user.id, repaid: false },
      orderBy: { createdAt: 'desc' },
    })
    if (!loan) return NextResponse.json({ error: 'You do not have an active loan to repay.' }, { status: 400 })

    if (fullUser.rbxBalance < loan.amount) {
      return NextResponse.json(
        { error: `You need T$ ${loan.amount.toLocaleString('en-US')} to repay this loan. Current wallet: T$ ${fullUser.rbxBalance}.` },
        { status: 400 }
      )
    }

    await db.$transaction([
      db.bankLoan.update({
        where: { id: loan.id },
        data: { repaid: true, repaidAt: new Date() },
      }),
      db.user.update({
        where: { id: user.id },
        data: { rbxBalance: fullUser.rbxBalance - loan.amount },
      }),
    ])

    return NextResponse.json({ ok: true, message: `Loan of T$ ${loan.amount.toLocaleString('en-US')} fully repaid! You are now eligible for future loans.` })
  }

  // 5. ADMIN FREE TIX: only for Nexico8225 / admin
  if (action === 'admin_mint') {
    if (!isAdmin) {
      return NextResponse.json({ error: 'Admin only.' }, { status: 403 })
    }
    const amount = Math.min(100000, Math.max(1, Math.floor(Number(body.amount) || 500)))
    await db.user.update({
      where: { id: user.id },
      data: { rbxBalance: fullUser.rbxBalance + amount },
    })
    return NextResponse.json({ ok: true, message: `Admin minted +T$ ${amount.toLocaleString('en-US')} successfully!` })
  }

  // 6. SELL TO WEBSITE: Instant cashout for UGC item
  if (action === 'sell_to_website') {
    const itemId = String(body.itemId || '')
    if (!itemId) return NextResponse.json({ error: 'Item ID required.' }, { status: 400 })

    const entry = await db.inventoryEntry.findUnique({
      where: { userId_itemId: { userId: user.id, itemId } },
      include: { item: true },
    })
    if (!entry) return NextResponse.json({ error: 'You do not own this item.' }, { status: 404 })

    const it = entry.item
    // Instant buyback price: 80% of price or RAP (min 1 Tix)
    const baseVal = Math.max(1, it.price || 5)
    const payout = Math.max(1, Math.round(baseVal * 0.8))

    await db.$transaction([
      db.inventoryEntry.delete({
        where: { id: entry.id },
      }),
      db.user.update({
        where: { id: user.id },
        data: { rbxBalance: fullUser.rbxBalance + payout },
      }),
      db.rbxTransaction.create({
        data: {
          userId: user.id,
          amount: payout,
          type: 'trade_in',
          balanceBefore: fullUser.rbxBalance,
          balanceAfter: fullUser.rbxBalance + payout,
          note: `Sold ${it.name} to RetroBank website cashout`,
        },
      }),
    ])

    return NextResponse.json({
      ok: true,
      message: `Sold ${it.name} to the website for T$ ${payout.toLocaleString('en-US')}!`,
      payout,
    })
  }

  return NextResponse.json({ error: 'Unknown action.' }, { status: 400 })
}
