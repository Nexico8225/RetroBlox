import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { PLATFORM_CORS } from '@/lib/platform'
import {
  ensureBaseplate,
  sanitizeChatText,
  lazyGameGC,
  PRESENCE_ACTIVE_S,
  CHAT_MIN_GAP_MS,
} from '@/lib/places'

/**
 * GAME HEARTBEAT — POST /api/game/state   (Authorization: Bearer <token>)
 *
 * THE multiplayer loop, one request per tick (~150ms):
 *   - upserts the caller's presence row (position / yaw / anim state)
 *   - optionally posts one chat message (rate limited server-side)
 *   - optionally leaves the place (leave: true)
 * and returns everything the caller needs to render the world:
 *   - every OTHER active player (seen in the last 10s) with their state
 *   - every chat message posted since `since` (any player, including
 *     the caller's own echo — clients that showed it optimistically
 *     just skip their own userId)
 *
 * LOGIN ONLY: guests do not exist in RetroBlox worlds — the token IS
 * the player. Positions are studs (1 unit = 1 stud), yaw radians.
 */

const STATES = new Set(['idle', 'walk', 'jump', 'fall', 'climb'])
const WORLD_LIMIT = 100000 // studs from origin — anything beyond is junk

function num(value: unknown, fallback = 0): number {
  const n = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.max(-WORLD_LIMIT, Math.min(WORLD_LIMIT, n))
}

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json(
      { error: 'Invalid or expired token' },
      { status: 401, headers: PLATFORM_CORS }
    )
  }

  let body: Record<string, unknown>
  try {
    body = (await req.json()) as Record<string, unknown>
  } catch {
    return NextResponse.json({ error: 'Bad request body' }, { status: 400, headers: PLATFORM_CORS })
  }

  try {
    const place = await ensureBaseplate()
    const placeId = place.id

    // ---- leave: remove the presence row, done ----
    if (body.leave === true) {
      await db.playerPresence.deleteMany({ where: { userId: user.id, placeId } })
      return NextResponse.json({ ok: true, left: true }, { headers: PLATFORM_CORS })
    }

    // ---- chat (optional, rate limited) ----
    let chatPosted = false
    const text = sanitizeChatText(body.chat)
    if (text.length > 0) {
      const last = await db.placeChat.findFirst({
        where: { placeId, userId: user.id },
        orderBy: { createdAt: 'desc' },
        select: { createdAt: true },
      })
      const gapOk = !last || Date.now() - last.createdAt.getTime() >= CHAT_MIN_GAP_MS
      if (gapOk) {
        await db.placeChat.create({
          data: { placeId, userId: user.id, username: user.username, text },
        })
        chatPosted = true
      }
    }

    // ---- presence upsert ----
    const stateRaw = typeof body.state === 'string' ? body.state : 'idle'
    const state = STATES.has(stateRaw) ? stateRaw : 'idle'
    const data = {
      placeId,
      username: user.username,
      x: num(body.x),
      y: num(body.y, 10),
      z: num(body.z),
      yaw: num(body.yaw),
      state,
      shiftlock: body.shiftlock === true,
    }
    await db.playerPresence.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...data },
      update: data,
    })

    // ---- everything the caller needs to see ----
    const now = Date.now()
    const activeCutoff = new Date(now - PRESENCE_ACTIVE_S * 1000)
    const others = await db.playerPresence.findMany({
      where: { placeId, updatedAt: { gte: activeCutoff }, userId: { not: user.id } },
      select: {
        userId: true,
        username: true,
        x: true,
        y: true,
        z: true,
        yaw: true,
        state: true,
        shiftlock: true,
      },
      take: 64,
    })

    let sinceDate: Date | null = null
    if (typeof body.since === 'string' && body.since.length > 0) {
      const t = Date.parse(body.since)
      if (Number.isFinite(t)) sinceDate = new Date(t)
    }
    const chatRows = await db.placeChat.findMany({
      where: { placeId, ...(sinceDate ? { createdAt: { gt: sinceDate } } : {}) },
      orderBy: { createdAt: 'asc' },
      take: 30,
      select: { id: true, userId: true, username: true, text: true, createdAt: true },
    })

    // occasional GC piggybacked on real traffic (~4% of ticks)
    if (Math.random() < 0.04) lazyGameGC().catch(() => {})

    return NextResponse.json(
      {
        ok: true,
        chatPosted,
        players: others,
        chat: chatRows,
        place: { slug: place.slug, name: place.name, maxPlayers: place.maxPlayers },
        serverTime: new Date(now).toISOString(),
      },
      { headers: PLATFORM_CORS }
    )
  } catch (err) {
    console.error('[game/state] failed:', err)
    return NextResponse.json({ error: 'Game state failed' }, { status: 500, headers: PLATFORM_CORS })
  }
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
