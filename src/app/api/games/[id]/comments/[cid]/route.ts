import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

// POST /api/games/[id]/comments/[cid] — toggle "Helpful" on a Steam-style review
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string; cid: string }> }) {
  const { cid } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const comment = await db.comment.findUnique({ where: { id: cid } })
  if (!comment) return NextResponse.json({ error: 'Review not found' }, { status: 404 })

  let ups: string[] = []
  try {
    ups = JSON.parse(comment.upIds || '[]')
  } catch { /* keep [] */ }

  const has = ups.includes(me.id)
  const next = has ? ups.filter((u) => u !== me.id) : [...ups, me.id]
  await db.comment.update({ where: { id: cid }, data: { upIds: JSON.stringify(next) } })

  return NextResponse.json({ ok: true, helpful: next.length, marked: !has })
}

// DELETE /api/games/[id]/comments/[cid] — review author or admin
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string; cid: string }> }) {
  const { cid } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const comment = await db.comment.findUnique({ where: { id: cid } })
  if (!comment) return NextResponse.json({ error: 'Review not found' }, { status: 404 })
  if (comment.userId !== me.id && me.role !== 'admin') {
    return NextResponse.json({ error: 'You can only delete your own reviews.' }, { status: 403 })
  }

  await db.comment.delete({ where: { id: cid } })
  return NextResponse.json({ ok: true })
}
