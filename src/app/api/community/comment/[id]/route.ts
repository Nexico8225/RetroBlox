import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { parseIds } from '@/lib/stats'

// PATCH /api/community/comment/[id] — toggle like on a comment
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { id } = await params

  const comment = await db.communityComment.findUnique({ where: { id } })
  if (!comment) return NextResponse.json({ error: 'Comment not found' }, { status: 404 })

  const likes = parseIds(comment.likeIds)
  const has = likes.includes(me.id)
  const next = has ? likes.filter((x) => x !== me.id) : [...likes, me.id]
  await db.communityComment.update({ where: { id }, data: { likeIds: JSON.stringify(next) } })

  return NextResponse.json({ likes: next.length, myLike: !has })
}

// DELETE /api/community/comment/[id] — author or admin
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { id } = await params

  const comment = await db.communityComment.findUnique({ where: { id } })
  if (!comment) return NextResponse.json({ error: 'Comment not found' }, { status: 404 })
  if (comment.authorId !== me.id && me.role !== 'admin') {
    return NextResponse.json({ error: 'Not your comment!' }, { status: 403 })
  }

  await db.communityComment.delete({ where: { id } })
  return NextResponse.json({ ok: true })
}
