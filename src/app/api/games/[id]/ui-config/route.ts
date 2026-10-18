import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// "1" -> Game ID #1; cuid keeps working (same resolver the game routes use)
async function resolveGameParam(raw: string): Promise<string | null> {
  const p = (raw || '').trim()
  if (!p) return null
  if (/^\d+$/.test(p)) {
    const bySeq = await db.game.findUnique({ where: { seqId: Number(p) }, select: { id: true } })
    if (bySeq) return bySeq.id
  }
  return p
}

// v6: the PUBLISHED game UI — the desktop player fetches this at startup and
// spawns the widgets for EVERY player. Public read, no login needed (guests
// play too); only the owner can change it (PATCH /api/games/[id] uiConfig).
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const gid = await resolveGameParam(id)
  if (!gid) return NextResponse.json({ error: 'Game not found' }, { status: 404 })
  const game = await db.game.findUnique({ where: { id: gid }, select: { uiConfigJson: true } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })
  if (!game.uiConfigJson) return NextResponse.json({ uiConfig: null })
  try {
    return NextResponse.json({ uiConfig: JSON.parse(game.uiConfigJson) })
  } catch {
    return NextResponse.json({ uiConfig: null })
  }
}
