import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { bumpStats } from '@/lib/stats'

// One view per browser session per game (client guards with sessionStorage).
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const game = await db.game.findUnique({ where: { id }, select: { id: true, views: true, statsJson: true } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })

  const updated = await db.game.update({
    where: { id },
    data: { views: { increment: 1 }, statsJson: bumpStats(game.statsJson, 'v') },
  })
  return NextResponse.json({ views: updated.views })
}
