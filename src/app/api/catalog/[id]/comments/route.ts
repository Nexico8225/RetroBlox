import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * GET  /api/catalog/[id]/comments — the item page comment section (newest first)
 * POST /api/catalog/[id]/comments — leave a comment ([shake]Text FX welcome[/shake])
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const comments = await db.ugcComment.findMany({
    where: { itemId: id },
    orderBy: { createdAt: 'desc' },
    take: 100,
    include: { user: { select: { id: true, username: true, avatarUrl: true, playerNo: true } } },
  })
  return NextResponse.json({ comments })
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { id } = await params
  const body = await req.json().catch(() => ({}))
  const text = String(body?.text || '').trim().slice(0, 300)
  if (!text) return NextResponse.json({ error: 'Write something first.' }, { status: 400 })

  const item = await db.avatarItem.findUnique({ where: { id }, select: { id: true, deletedAt: true } })
  if (!item || item.deletedAt) return NextResponse.json({ error: 'Item not found.' }, { status: 404 })

  const comment = await db.ugcComment.create({
    data: { itemId: id, userId: user.id, text },
    include: { user: { select: { id: true, username: true, avatarUrl: true, playerNo: true } } },
  })
  return NextResponse.json({ ok: true, comment })
}
