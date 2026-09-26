import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })

  const existing = await db.favorite.findUnique({
    where: { userId_gameId: { userId: user.id, gameId: id } },
  })

  if (existing) {
    await db.favorite.delete({ where: { id: existing.id } })
  } else {
    await db.favorite.create({ data: { userId: user.id, gameId: id } })
  }

  const favorites = await db.favorite.count({ where: { gameId: id } })
  return NextResponse.json({ favorites, myFavorite: !existing })
}
