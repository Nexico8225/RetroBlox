import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

/** POST /api/colormaps/[id]/play — count one map play (fired when a player enters the map). */
export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const map = await db.colorMap.findUnique({ where: { id }, select: { id: true } })
  if (!map) return NextResponse.json({ error: 'Map not found' }, { status: 404 })
  const updated = await db.colorMap.update({ where: { id }, data: { plays: { increment: 1 } } })
  return NextResponse.json({ plays: updated.plays })
}
