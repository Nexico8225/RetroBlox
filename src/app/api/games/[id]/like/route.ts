import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = await req.json()
  const value = Number(body.value)
  if (![1, -1, 0].includes(value)) {
    return NextResponse.json({ error: 'Invalid vote' }, { status: 400 })
  }

  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })

  const existing = await db.gameLike.findUnique({
    where: { userId_gameId: { userId: user.id, gameId: id } },
  })

  let myLike = 0
  if (value === 0 || (existing && existing.value === value)) {
    await db.gameLike.deleteMany({ where: { userId: user.id, gameId: id } })
  } else if (existing) {
    await db.gameLike.update({ where: { id: existing.id }, data: { value } })
    myLike = value
  } else {
    await db.gameLike.create({ data: { userId: user.id, gameId: id, value } })
    myLike = value
  }

  const likes = await db.gameLike.count({ where: { gameId: id, value: 1 } })
  const dislikes = await db.gameLike.count({ where: { gameId: id, value: -1 } })

  return NextResponse.json({
    likes,
    dislikes,
    rating: likes + dislikes > 0 ? Math.round((likes / (likes + dislikes)) * 100) : null,
    myLike,
  })
}
