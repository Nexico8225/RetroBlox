import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

// POST /api/games/[id]/gem — admins mark / unmark a game as a Hidden Gem.
// Hidden Gems is its own filter on the games browser.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  if (user.role !== 'admin') {
    return NextResponse.json({ error: 'Only admins can mark Hidden Gems.' }, { status: 403 })
  }

  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })

  const updated = await db.game.update({ where: { id }, data: { gem: !game.gem } })
  return NextResponse.json({ ok: true, gem: updated.gem })
}
