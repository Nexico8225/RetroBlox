import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { PLATFORM_CORS } from '@/lib/platform'

/**
 * PLACE CHAT + PRESENCE — the RetroBlox Player's in-game social loop.
 *
 * The Godot client polls:
 *   GET  /api/placechat/{placeId}
 *        -> { ok, messages: [...latest 60, oldest first], players: [...online now] }
 *        Public on purpose (like classic Roblox place pages). "Online" =
 *        presence rows touched in the last 30 seconds. Every message and
 *        player carries the sender's #seqId so chat shows "Nexico8225 #1".
 *
 *   POST /api/placechat/{placeId}   (Authorization: Bearer <token>)
 *        body { text: "..." }            -> send a chat line (rate limited)
 *        body { x, y, z, heading }       -> presence heartbeat (every ~4s)
 *        Guests have no token: they can watch chat and see other players,
 *        but only signed-in members appear online and talk (no bot rows,
 *        no anonymous spam writes — same rule as the rest of the platform).
 *
 * placeId is the client's built-in place slug ("baseplate" | "obby" |
 * "skylands") — places are not Game rows, so nothing else is validated.
 */

const ONLINE_WINDOW_MS = 30_000
const CHAT_COOLDOWN_MS = 800
const MAX_LEN = 240

function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status, headers: PLATFORM_CORS })
}

type MsgRow = {
  id: string
  userId: string
  text: string
  createdAt: Date
  user: { username: string; seqId: number | null }
}

function shapeMessage(m: MsgRow) {
  return {
    id: m.id,
    userId: m.userId,
    username: m.user.username,
    seqId: m.user.seqId,
    text: m.text,
    at: m.createdAt.toISOString(),
  }
}

export async function GET(_req: NextRequest, { params }: { params: Promise<{ placeId: string }> }) {
  const { placeId } = await params

  const rows = await db.placeChatMessage
    .findMany({
      where: { placeId },
      orderBy: { createdAt: 'desc' },
      take: 60,
      include: { user: { select: { username: true, seqId: true } } },
    })
    .catch(() => [])
  const messages = rows.reverse().map(shapeMessage)

  const cutoff = new Date(Date.now() - ONLINE_WINDOW_MS)
  const presence = await db.placePresence
    .findMany({
      where: { placeId, updatedAt: { gte: cutoff } },
      orderBy: { updatedAt: 'desc' },
      include: { user: { select: { username: true, seqId: true } } },
    })
    .catch(() => [])

  return json({
    ok: true,
    messages,
    players: presence.map((p) => ({
      userId: p.userId,
      username: p.user.username,
      seqId: p.user.seqId,
      pos: [p.x, p.y, p.z],
      heading: p.heading,
      at: p.updatedAt.toISOString(),
    })),
  })
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ placeId: string }> }) {
  const { placeId } = await params
  const user = await getUserFromReq(req)
  if (!user) return json({ error: 'Sign in to use place chat' }, 401)

  const body = (await req.json().catch(() => null)) as
    | { text?: unknown; x?: unknown; y?: unknown; z?: unknown; heading?: unknown }
    | null
  if (!body) return json({ error: 'Bad request' }, 400)

  // ---- chat send ----
  if (typeof body.text === 'string') {
    const text = body.text.replace(/\s+/g, ' ').replace(/[\u0000-\u001f]/g, '').trim().slice(0, MAX_LEN)
    if (!text) return json({ error: 'Say something first!' }, 400)

    const last = await db.placeChatMessage.findFirst({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      select: { createdAt: true },
    })
    if (last && Date.now() - last.createdAt.getTime() < CHAT_COOLDOWN_MS) {
      return json({ error: "You're chatting too fast — wait a moment!" }, 429)
    }

    const msg = await db.placeChatMessage.create({
      data: { placeId, userId: user.id, text },
      include: { user: { select: { username: true, seqId: true } } },
    })
    await db.user.update({ where: { id: user.id }, data: { lastSeen: new Date() } }).catch(() => {})
    return json({ ok: true, message: shapeMessage(msg) })
  }

  // ---- presence heartbeat ----
  const x = Number(body.x)
  const y = Number(body.y)
  const z = Number(body.z)
  const heading = Number.isFinite(Number(body.heading)) ? Number(body.heading) : 0
  if (Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(z)) {
    // clamp absurd teleport dumps (client sends its real studs position)
    const px = Math.max(-100000, Math.min(100000, x))
    const py = Math.max(-100000, Math.min(100000, y))
    const pz = Math.max(-100000, Math.min(100000, z))
    await db.placePresence
      .upsert({
        where: { userId: user.id },
        create: { userId: user.id, placeId, x: px, y: py, z: pz, heading },
        update: { placeId, x: px, y: py, z: pz, heading },
      })
      .catch(() => {})
    return json({ ok: true })
  }

  return json({ error: 'Nothing to do' }, 400)
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
