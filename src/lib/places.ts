import { db } from '@/lib/db'
import { BASEPLATE_MAP } from '@/lib/baseplate-map'
import type { Place } from '@prisma/client'

/* ------------------------------------------------------------------
   IN-GAME PLACES — server-side helpers for the web-synced player.

   The WEBSITE owns the games. The desktop player asks these endpoints
   for the game list and the map JSON every launch, so whatever is on
   the site is what everyone plays. ONE place ships right now:
   baseplate — the classic brick world (parts / spawns / ladder truss,
   all in studs, identical to the original Godot scene).
------------------------------------------------------------------ */

export const BASEPLATE_SLUG = 'baseplate'

/** How fresh a presence row must be to count as "in the game" (seconds). */
export const PRESENCE_ACTIVE_S = 10
/** Presence rows older than this are garbage (seconds) — lazily pruned. */
export const PRESENCE_GC_S = 120
/** Chat rows older than this are pruned lazily (seconds). */
export const CHAT_TTL_S = 30 * 60
/** Minimal gap between two chat messages from the same player (ms). */
export const CHAT_MIN_GAP_MS = 700

/**
 * Idempotent seed — makes sure the classic Baseplate place exists with the
 * full map. Runs on every game API call (cheap unique find) and NEVER
 * overwrites an existing row, so web-side edits stay authoritative.
 */
export async function ensureBaseplate(): Promise<Place> {
  const existing = await db.place.findUnique({ where: { slug: BASEPLATE_SLUG } })
  if (existing) return existing
  return db.place.create({
    data: {
      slug: BASEPLATE_SLUG,
      name: BASEPLATE_MAP.name,
      description:
        'The classic brick world — spawn pads, stairs, gap slabs and the ladder tower. Everyone plays together here.',
      dataJson: JSON.stringify(BASEPLATE_MAP),
      sortOrder: 0,
      active: true,
    },
  })
}

/** Parse a place's dataJson, tolerating junk (never trust stored JSON). */
export function parseMapData(raw: string): Record<string, unknown> {
  try {
    const data = JSON.parse(raw || '{}')
    if (data && typeof data === 'object' && !Array.isArray(data)) return data as Record<string, unknown>
    return {}
  } catch {
    return {}
  }
}

/** Strip control/bidi characters and cap length — chat is plain text only. */
export function sanitizeChatText(input: unknown, max = 180): string {
  if (typeof input !== 'string') return ''
  const cleaned = input
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E\u2060-\u206F]/g, '')
    .slice(0, max)
    .trim()
  return cleaned
}

/** Live players per place id: {placeId: count} for rows seen recently. */
export async function activePresenceCounts(): Promise<Map<string, number>> {
  const cutoff = new Date(Date.now() - PRESENCE_ACTIVE_S * 1000)
  const rows = await db.playerPresence.findMany({
    where: { updatedAt: { gte: cutoff } },
    select: { placeId: true },
  })
  const counts = new Map<string, number>()
  for (const row of rows) counts.set(row.placeId, (counts.get(row.placeId) ?? 0) + 1)
  return counts
}

/** Best-effort lazy GC — presence junk + ancient chat. Safe to call often. */
export async function lazyGameGC(): Promise<void> {
  const now = Date.now()
  await db.playerPresence.deleteMany({
    where: { updatedAt: { lt: new Date(now - PRESENCE_GC_S * 1000) } },
  })
  await db.placeChat.deleteMany({
    where: { createdAt: { lt: new Date(now - CHAT_TTL_S * 1000) } },
  })
}
