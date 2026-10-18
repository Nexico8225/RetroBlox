import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { bumpStats } from '@/lib/stats'

// Called right before the file is fetched for a Download / Re-Download.
// "Play now" does NOT hit this (opening an already-owned file is free!).
// Also records the download per-user for the "Your Downloaded Games" rail.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })
  if (!game.fileId) return NextResponse.json({ error: 'No game file' }, { status: 404 })

  const updated = await db.game.update({
    where: { id },
    data: { downloads: { increment: 1 }, statsJson: bumpStats(game.statsJson, 'd') },
  })

  // per-player download log (home rail "Your Downloaded Games")
  await db.gameDownload.upsert({
    where: { userId_gameId: { userId: user.id, gameId: id } },
    create: { userId: user.id, gameId: id },
    update: { count: { increment: 1 }, lastAt: new Date() },
  })

  return NextResponse.json({
    downloads: updated.downloads,
    fileUrl: `/api/files/${game.fileId}?dl=1`,
  })
}
