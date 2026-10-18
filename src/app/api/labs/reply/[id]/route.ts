import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { parseIds } from '@/lib/stats'

// PATCH /api/labs/reply/[id] — toggle like on a RetroLabs reply
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { id } = await params

  const reply = await db.labReply.findUnique({ where: { id } })
  if (!reply) return NextResponse.json({ error: 'Reply not found' }, { status: 404 })

  const likes = parseIds(reply.likeIds)
  const has = likes.includes(me.id)
  const next = has ? likes.filter((x) => x !== me.id) : [...likes, me.id]
  await db.labReply.update({ where: { id }, data: { likeIds: JSON.stringify(next) } })

  return NextResponse.json({ likes: next.length, myLike: !has })
}

// DELETE /api/labs/reply/[id] — author or admin
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { id } = await params

  const reply = await db.labReply.findUnique({ where: { id } })
  if (!reply) return NextResponse.json({ error: 'Reply not found' }, { status: 404 })
  if (reply.authorId !== me.id && me.role !== 'admin') {
    return NextResponse.json({ error: 'Not your reply!' }, { status: 403 })
  }

  await db.labReply.delete({ where: { id } })
  return NextResponse.json({ ok: true })
}
