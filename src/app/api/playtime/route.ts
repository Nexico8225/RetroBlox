import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { evaluateBadges, levelForXp, BADGES } from '@/lib/badges'
import { PLATFORM_CORS } from '@/lib/platform'

const BADGE_XP: Record<string, number> = Object.fromEntries(BADGES.map((b) => [b.id, b.xp]))

/**
 * PLAYTIME HEARTBEAT — POST /api/playtime   (Authorization: Bearer <token>)
 *
 * The player calls this every ~60 seconds WHILE IN-GAME. The server
 * accumulates real playtime per (user, game) session:
 *   • beat within 5 minutes of the last one → same session, we bank the
 *     elapsed seconds (capped at 120 so a stuck client can't farm time)
 *   • otherwise → brand new session (counts as a fresh "Play" too)
 *
 * This powers ALL the Steam-style features: profile "hours played",
 * "Last 2 Weeks" recently-played rows, game detail playtime stats,
 * playtime XP toward the account LEVEL, and playtime BADGES.
 *
 * Response also carries newlyUnlocked badges so the game can show
 * "Achievement unlocked!" toasts right when they happen.
 */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json({ error: 'Login required' }, { status: 401, headers: PLATFORM_CORS })
  }

  const body = (await req.json().catch(() => null)) as { gameId?: string; clientSeconds?: number } | null
  const gameId = (body?.gameId || '').trim()
  if (!gameId) {
    return NextResponse.json({ error: 'gameId required' }, { status: 400, headers: PLATFORM_CORS })
  }
  const game = await db.game.findUnique({ where: { id: gameId }, select: { id: true } })
  if (!game) {
    return NextResponse.json({ error: 'Game not found' }, { status: 404, headers: PLATFORM_CORS })
  }

  const now = new Date()
  const SESSION_GAP_MS = 5 * 60 * 1000 // >5 min since last beat = new session
  const MAX_DELTA_S = 120 // cap per-beat credit (beat every 60s = 60s credit)

  // continue an open session, or start a new one
  const open = await db.playSession.findFirst({
    where: { userId: user.id, gameId, lastBeatAt: { gt: new Date(now.getTime() - SESSION_GAP_MS) } },
    orderBy: { lastBeatAt: 'desc' },
  })

  let delta = 0
  let session: { id: string; seconds: number }
  if (open) {
    delta = Math.max(0, Math.min(MAX_DELTA_S, Math.round((now.getTime() - new Date(open.lastBeatAt).getTime()) / 1000)))
    session = await db.playSession.update({
      where: { id: open.id },
      data: { seconds: { increment: delta }, lastBeatAt: now },
      select: { id: true, seconds: true },
    })
  } else {
    // client may send clientSeconds on the FIRST beat (time already played
    // before the first heartbeat landed) — capped, optional
    delta = Math.max(0, Math.min(300, Math.round(body?.clientSeconds || 0)))
    session = await db.playSession.create({
      data: { userId: user.id, gameId, seconds: delta, startedAt: now, lastBeatAt: now },
      select: { id: true, seconds: true },
    })
  }

  // aggregate totals on GamePlay (fast profile reads)
  const play = await db.gamePlay.upsert({
    where: { userId_gameId: { userId: user.id, gameId } },
    create: { userId: user.id, gameId, playCount: 1, seconds: delta, firstPlayedAt: now, lastPlayedAt: now },
    update: {
      seconds: { increment: delta },
      lastPlayedAt: now,
      ...(open ? {} : { playCount: { increment: 1 } }), // a new session = another Play
    },
    select: { seconds: true, playCount: true },
  })

  // badges can unlock from playtime milestones — evaluate now and let the game toast
  const newly = await evaluateBadges(user.id)

  // account XP: 1 XP per minute played + badge XP
  const badgeRows = await db.playerBadge.findMany({ where: { userId: user.id }, select: { badgeId: true } })
  const badgeXp = badgeRows.reduce((sum, r) => sum + (BADGE_XP[r.badgeId] || 0), 0)
  const xp = Math.floor(play.seconds / 60) + badgeXp

  return NextResponse.json(
    {
      ok: true,
      sessionSeconds: session.seconds,
      totalSeconds: play.seconds,
      playCount: play.playCount,
      xp,
      level: levelForXp(xp).level,
      newlyUnlocked: newly.map((b) => ({ id: b.id, name: b.name, desc: b.desc, color: b.color })),
    },
    { headers: PLATFORM_CORS }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: PLATFORM_CORS })
}
