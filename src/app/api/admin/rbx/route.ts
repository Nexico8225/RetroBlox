import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { ensurePackages, grantRbx } from '@/lib/rbx'
import { paymentsMode } from '@/lib/stripe'

async function requireAdmin(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return { error: NextResponse.json({ error: 'Login required' }, { status: 401 }) }
  if (user.role !== 'admin') return { error: NextResponse.json({ error: 'Admins only.' }, { status: 403 }) }
  return { user }
}

/** GET /api/admin/rbx — everything the RBX admin panel shows, in one call. */
export async function GET(req: NextRequest) {
  const { error } = await requireAdmin(req)
  if (error) return error

  await ensurePackages()
  const [packages, payments, transactions, holders, paidAgg] = await Promise.all([
    db.rbxPackage.findMany({ orderBy: [{ sortOrder: 'asc' }, { priceCents: 'asc' }] }),
    db.payment.findMany({
      take: 100,
      orderBy: { createdAt: 'desc' },
      include: {
        user: { select: { username: true } },
        package: { select: { name: true, rbxAmount: true } },
      },
    }),
    db.rbxTransaction.findMany({
      take: 100,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { username: true } } },
    }),
    db.user.findMany({
      select: { id: true, username: true, rbxBalance: true, role: true },
      orderBy: { rbxBalance: 'desc' },
      take: 100,
    }),
    db.payment.aggregate({
      where: { status: { in: ['succeeded', 'refunded', 'partially_refunded'] } },
      _count: { _all: true },
      _sum: { amountPaid: true, refundedCents: true, rbxCredited: true, rbxReversed: true },
    }),
  ])

  return NextResponse.json({
    mode: paymentsMode(),
    packages,
    payments: payments.map((p) => ({
      id: p.id,
      username: p.user?.username || '(deleted)',
      packageName: p.package?.name || '—',
      amountPaid: p.amountPaid,
      currency: p.currency,
      status: p.status,
      refundedCents: p.refundedCents,
      rbxCredited: p.rbxCredited,
      rbxReversed: p.rbxReversed,
      sessionId: p.stripeCheckoutSessionId,
      paymentIntentId: p.stripePaymentIntentId,
      createdAt: p.createdAt,
    })),
    transactions: transactions.map((t) => ({
      id: t.id,
      username: t.user.username,
      amount: t.amount,
      type: t.type,
      balanceBefore: t.balanceBefore,
      balanceAfter: t.balanceAfter,
      note: t.note,
      stripeEventId: t.stripeEventId,
      stripePaymentIntentId: t.stripePaymentIntentId,
      createdAt: t.createdAt,
    })),
    holders,
    stats: {
      paymentsCount: paidAgg._count._all,
      totalPaidCents: paidAgg._sum.amountPaid || 0,
      totalRefundedCents: paidAgg._sum.refundedCents || 0,
      totalRbxGranted: paidAgg._sum.rbxCredited || 0,
      totalRbxReversed: paidAgg._sum.rbxReversed || 0,
    },
  })
}

/** POST /api/admin/rbx — { action: 'package.create' | 'package.update' | 'grant', ... } */
export async function POST(req: NextRequest) {
  const { error } = await requireAdmin(req)
  if (error) return error

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
  const action = String(body.action || '')

  if (action === 'package.create') {
    const name = String(body.name || '').trim()
    const rbxAmount = Math.floor(Number(body.rbxAmount))
    const priceCents = Math.round(Number(body.priceCents))
    if (name.length < 2 || name.length > 40) {
      return NextResponse.json({ error: 'Package name must be 2-40 characters.' }, { status: 400 })
    }
    if (!Number.isFinite(rbxAmount) || rbxAmount < 1 || rbxAmount > 10_000_000) {
      return NextResponse.json({ error: 'Tix amount must be between 1 and 10,000,000.' }, { status: 400 })
    }
    if (!Number.isFinite(priceCents) || priceCents < 1 || priceCents > 1_000_000) {
      return NextResponse.json({ error: 'Price must be between $0.01 and $10,000.' }, { status: 400 })
    }
    let code = String(body.code || '').trim().toUpperCase() || `PACKAGE_${rbxAmount}_${Date.now().toString(36).toUpperCase()}`
    if (!/^PACKAGE_[A-Z0-9_]+$/.test(code)) code = `PACKAGE_${rbxAmount}_${Date.now().toString(36).toUpperCase()}`
    const clash = await db.rbxPackage.findUnique({ where: { code }, select: { id: true } })
    if (clash) code = `${code}_${Date.now().toString(36).toUpperCase()}`
    const sortOrder = Math.floor(Number(body.sortOrder)) || 99
    const pkg = await db.rbxPackage.create({
      data: { code, name, rbxAmount, priceCents, currency: 'usd', active: true, sortOrder },
    })
    return NextResponse.json({ ok: true, package: pkg })
  }

  if (action === 'package.update') {
    const id = String(body.id || '')
    const pkg = await db.rbxPackage.findUnique({ where: { id } })
    if (!pkg) return NextResponse.json({ error: 'Package not found.' }, { status: 404 })
    const data: { name?: string; rbxAmount?: number; priceCents?: number; active?: boolean; sortOrder?: number } = {}
    if (body.name !== undefined) {
      const name = String(body.name).trim()
      if (name.length < 2 || name.length > 40) {
        return NextResponse.json({ error: 'Package name must be 2-40 characters.' }, { status: 400 })
      }
      data.name = name
    }
    if (body.rbxAmount !== undefined) {
      const n = Math.floor(Number(body.rbxAmount))
      if (!Number.isFinite(n) || n < 1 || n > 10_000_000) {
        return NextResponse.json({ error: 'Tix amount must be between 1 and 10,000,000.' }, { status: 400 })
      }
      data.rbxAmount = n
    }
    if (body.priceCents !== undefined) {
      const n = Math.round(Number(body.priceCents))
      if (!Number.isFinite(n) || n < 1 || n > 1_000_000) {
        return NextResponse.json({ error: 'Price must be between $0.01 and $10,000.' }, { status: 400 })
      }
      data.priceCents = n
    }
    if (body.active !== undefined) data.active = !!body.active
    if (body.sortOrder !== undefined) data.sortOrder = Math.floor(Number(body.sortOrder)) || 99
    const pkg2 = await db.rbxPackage.update({ where: { id }, data })
    return NextResponse.json({ ok: true, package: pkg2 })
  }

  if (action === 'grant') {
    const username = String(body.username || '').trim()
    const rawAmount = Number(body.amount)
    const amount = Math.floor(rawAmount)
    const note = String(body.note || '').trim().slice(0, 200)
    if (!username) return NextResponse.json({ error: 'Pick a username.' }, { status: 400 })
    if (!Number.isInteger(rawAmount) || rawAmount === 0 || Math.abs(rawAmount) > 10_000_000) {
      return NextResponse.json({ error: 'Amount must be a whole number of Tix (use a negative amount to take Tix back).' }, { status: 400 })
    }
    const target = await db.user.findFirst({
      where: { OR: [{ username }, { usernameLower: username.toLowerCase() }] },
      select: { id: true, username: true },
    })
    if (!target) return NextResponse.json({ error: `No account named "${username}".` }, { status: 404 })
    try {
      const res = await grantRbx({
        userId: target.id,
        amount,
        type: 'admin_grant',
        note: note || `Admin grant by an administrator`,
      })
      return NextResponse.json({ ok: true, balanceAfter: res.balanceAfter, target: target.username })
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Grant failed.'
      const status = (e as { code?: string }).code === 'NEGATIVE' ? 400 : 500
      return NextResponse.json({ error: msg }, { status })
    }
  }

  return NextResponse.json({ error: 'Unknown action.' }, { status: 400 })
}
