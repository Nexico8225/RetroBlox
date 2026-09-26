import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

/** POST /api/music/{id}/play — count a listen (fire-and-forget from the player) */
export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  try {
    const track = await db.musicTrack.update({
      where: { id },
      data: { plays: { increment: 1 } },
      select: { plays: true },
    })
    return NextResponse.json({ ok: true, plays: track.plays })
  } catch {
    return NextResponse.json({ error: 'Track not found' }, { status: 404 })
  }
}
