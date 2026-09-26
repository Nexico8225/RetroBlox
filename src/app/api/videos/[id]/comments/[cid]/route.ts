import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

// DELETE /api/videos/[id]/comments/[cid] — comment author or admin
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string; cid: string }> }) {
  const { cid } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const comment = await db.videoComment.findUnique({ where: { id: cid } })
  if (!comment) return NextResponse.json({ error: 'Comment not found' }, { status: 404 })
  if (comment.authorId !== me.id && me.role !== 'admin') {
    return NextResponse.json({ error: 'You can only delete your own comments.' }, { status: 403 })
  }

  await db.videoComment.delete({ where: { id: cid } })
  return NextResponse.json({ ok: true })
}
