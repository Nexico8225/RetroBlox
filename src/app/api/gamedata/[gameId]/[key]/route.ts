import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { PLATFORM_CORS } from '@/lib/platform'

/**
 * GAME DATA / SAVE API — /api/gamedata/{gameId}/{key}
 * A tiny per-player DataStore so games can save progress through the
 * platform instead of inventing their own storage:
 *   GET  (Bearer token) -> { key, value }   value = any JSON you stored
 *   PUT  (Bearer token) { value: {...} }    -> saved
 * Writes are ALWAYS scoped to the authenticated player — one account
 * can never read or overwrite another player's saves.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ gameId: string; key: string }> }) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401, headers: PLATFORM_CORS })
  const { gameId, key } = await params

  const row = await db.gameData.findUnique({
    where: { gameId_userId_key: { gameId, userId: user.id, key } },
  })
  return NextResponse.json({ gameId, key, value: row ? JSON.parse(row.value) : null }, { headers: PLATFORM_CORS })
}

export async function PUT(req: NextRequest, { params }: { params: Promise<{ gameId: string; key: string }> }) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401, headers: PLATFORM_CORS })
  const { gameId, key } = await params
  const body = (await req.json().catch(() => null)) as { value?: unknown } | null
  if (body === null) return NextResponse.json({ error: 'Body must be { value: ... }' }, { status: 400 })

  const serialized = JSON.stringify(body.value ?? null)
  if (serialized.length > 512 * 1024) {
    return NextResponse.json({ error: 'Value too large (512KB max)' }, { status: 413, headers: PLATFORM_CORS })
  }

  const row = await db.gameData.upsert({
    where: { gameId_userId_key: { gameId, userId: user.id, key } },
    update: { value: serialized },
    create: { gameId, userId: user.id, key, value: serialized },
  })
  return NextResponse.json({ ok: true, updatedAt: row.updatedAt }, { headers: PLATFORM_CORS })
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
