import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// POST /api/videos/[id]/view — count a watch (client guards per session)
export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const video = await db.video.findUnique({ where: { id }, select: { id: true } })
  if (!video) return NextResponse.json({ error: 'Video not found' }, { status: 404 })

  const updated = await db.video.update({
    where: { id },
    data: { views: { increment: 1 } },
    select: { views: true },
  })
  return NextResponse.json({ views: updated.views })
}
