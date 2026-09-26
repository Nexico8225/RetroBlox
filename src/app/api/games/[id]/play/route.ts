import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

// POST /api/games/[id]/play — fired when a player hits "Play now".
// Powers the "Games You've Played" rail on the home page + profile stat.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })

  const play = await db.gamePlay.upsert({
    where: { userId_gameId: { userId: user.id, gameId: id } },
    create: { userId: user.id, gameId: id },
    update: { playCount: { increment: 1 }, lastPlayedAt: new Date() },
  })

  return NextResponse.json({ ok: true, playCount: play.playCount })
}
