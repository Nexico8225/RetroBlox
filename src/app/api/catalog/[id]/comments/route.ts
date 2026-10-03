import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/**
 * GET  /api/catalog/[id]/comments — the item's comment wall (newest first)
 * POST /api/catalog/[id]/comments — { text } — comment on a UGC item
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const rows = await db.itemComment.findMany({
    where: { itemId: id },
    include: { user: { select: { id: true, username: true, avatarUrl: true, seqId: true } } },
    orderBy: { createdAt: 'desc' },
    take: 50,
  })
  return NextResponse.json({
    comments: rows.map((c) => ({
      id: c.id,
      text: c.text,
      createdAt: c.createdAt,
      user: c.user,
    })),
  })
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const body = (await req.json().catch(() => ({}))) as { text?: string }
  const text = String(body.text || '').trim().slice(0, 500)
  if (!text) return NextResponse.json({ error: 'Write something first.' }, { status: 400 })

  const item = await db.avatarItem.findUnique({ where: { id }, select: { id: true, name: true, creatorId: true, deletedAt: true } })
  if (!item || item.deletedAt) return NextResponse.json({ error: 'Item not found' }, { status: 404 })

  const comment = await db.itemComment.create({
    data: { itemId: id, userId: user.id, text },
    include: { user: { select: { id: true, username: true, avatarUrl: true, seqId: true } } },
  })

  // tell the creator (the bell) — but not when commenting on your own item
  if (item.creatorId !== user.id) {
    await db.notification.create({
      data: {
        userId: item.creatorId,
        type: 'item_comment',
        dataJson: JSON.stringify({ itemId: id, itemName: item.name, fromName: user.username, text: text.slice(0, 80) }),
      },
    })
  }

  return NextResponse.json({
    ok: true,
    comment: { id: comment.id, text: comment.text, createdAt: comment.createdAt, user: comment.user },
  })
}
