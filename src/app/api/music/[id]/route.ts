import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

/** DELETE /api/music/{id} — soft-delete a track (owner or admin) */
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { id } = await params

  const track = await db.musicTrack.findUnique({ where: { id } })
  if (!track || track.deletedAt) {
    return NextResponse.json({ error: 'Track not found' }, { status: 404 })
  }
  if (track.creatorId !== user.id && user.role !== 'admin') {
    return NextResponse.json({ error: 'You can only delete your own tracks.' }, { status: 403 })
  }

  await db.musicTrack.update({ where: { id }, data: { deletedAt: new Date() } })
  return NextResponse.json({ ok: true })
}
