import { db } from '@/lib/db'

/**
 * SHORT NUMERIC IDS — every player and every game gets a small human ID:
 *
 *   the first person to join RetroBlox  ->  Player ID #1
 *   the first game ever published       ->  Game ID #1
 *
 * New signups / publishes reserve the next free number themselves
 * (see api/auth/signup, api/platform/signup and POST /api/games).
 * Accounts and games that predate the numbering are numbered here,
 * LAZILY, the first time they are read — always in creation order,
 * so the oldest account becomes #1 and the oldest game becomes #1.
 *
 * Everything here is best-effort and race-safe: a numbering failure
 * must never break the request that triggered it, and two requests
 * numbering the same row at the same moment can only lose one of the
 * writes (the loser re-reads the winner's number).
 */

type SeqRow = { id: string; seqId: number | null }

async function nextUserSeq(): Promise<number> {
  const agg = await db.user.aggregate({ _max: { seqId: true } })
  return (agg._max.seqId ?? 0) + 1
}

async function nextGameSeq(): Promise<number> {
  const agg = await db.game.aggregate({ _max: { seqId: true } })
  return (agg._max.seqId ?? 0) + 1
}

/** Give a player their #N if they don't have one yet (mutates + returns the row). */
export async function ensureUserSeq<T extends SeqRow>(u: T): Promise<T> {
  if (!u || typeof u.seqId === 'number') return u
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const n = await nextUserSeq()
      // the write only lands while seqId is still null — whoever writes
      // first wins; a loser just re-reads the number the winner chose
      const res = await db.user.updateMany({ where: { id: u.id, seqId: null }, data: { seqId: n } })
      if (res.count === 1) {
        u.seqId = n
        return u
      }
      const fresh = await db.user.findUnique({ where: { id: u.id }, select: { seqId: true } })
      if (fresh && typeof fresh.seqId === 'number') {
        u.seqId = fresh.seqId
        return u
      }
    } catch {
      /* someone took that number a moment ago — retry with a fresh max */
    }
  }
  return u
}

/** Give a game its #N if it doesn't have one yet (mutates + returns the row). */
export async function ensureGameSeq<T extends SeqRow>(g: T): Promise<T> {
  if (!g || typeof g.seqId === 'number') return g
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const n = await nextGameSeq()
      const res = await db.game.updateMany({ where: { id: g.id, seqId: null }, data: { seqId: n } })
      if (res.count === 1) {
        g.seqId = n
        return g
      }
      const fresh = await db.game.findUnique({ where: { id: g.id }, select: { seqId: true } })
      if (fresh && typeof fresh.seqId === 'number') {
        g.seqId = fresh.seqId
        return g
      }
    } catch {
      /* retry with a fresh max */
    }
  }
  return g
}

/**
 * Number every game that predates the numbering, oldest first (publish
 * order) — called from the games list before it reads, so a single visit
 * to the Games page heals the whole library at once.
 */
export async function healGameSeqs(): Promise<void> {
  try {
    const missing = await db.game.findMany({
      where: { seqId: null },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    })
    for (const g of missing) {
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const n = await nextGameSeq()
          const res = await db.game.updateMany({ where: { id: g.id, seqId: null }, data: { seqId: n } })
          if (res.count === 1) break
        } catch {
          /* retry with a fresh max */
        }
      }
    }
  } catch {
    /* numbering must never break a request */
  }
}
