import { db } from '@/lib/db'

/* ------------------------------------------------------------------
   NOTIFICATIONS — the bell icon feed.

   Events: a new player joins RetroBlox, someone sends you a friend
   request, someone accepts yours. Each one is a Notification row for
   the recipient, surfaced by GET /api/notifications and the header
   bell (polls /api/me for the unread badge).

   SELF-MIGRATING TABLE: the production database is Turso (created by
   sync-schema.mjs at build time), but an OLD deploy or a fresh lambda
   could hit an API before that ran. ensureNotificationSchema() issues
   CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS exactly
   once per process (cached promise), so the very first notification
   call heals the schema instead of throwing P2021 "table does not
   exist". Purely additive — existing tables and rows are untouched.
------------------------------------------------------------------ */

const NOTIF_DDL = [
  `CREATE TABLE IF NOT EXISTS "Notification" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "actorId" TEXT,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL DEFAULT '',
    "linkUrl" TEXT,
    "readAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Notification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "Notification_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
  )`,
  `CREATE INDEX IF NOT EXISTS "Notification_userId_readAt_idx" ON "Notification"("userId", "readAt")`,
  `CREATE INDEX IF NOT EXISTS "Notification_actorId_idx" ON "Notification"("actorId")`,
]

let ensurePromise: Promise<boolean> | null = null

/** Create the Notification table if the database doesn't have it yet
 *  (runs at most once per serverless instance; safe to call always). */
export function ensureNotificationSchema(): Promise<boolean> {
  if (!ensurePromise) {
    ensurePromise = (async () => {
      try {
        for (const sql of NOTIF_DDL) {
          await db.$executeRawUnsafe(sql)
        }
        return true
      } catch (e) {
        console.error('[notifications] schema ensure failed:', e)
        return false // queries below will surface the real error if any
      }
    })()
  }
  return ensurePromise
}

export interface NotificationInput {
  type: 'new_player' | 'friend_request' | 'friend_accepted'
  title: string
  body?: string
  linkUrl?: string
  actorId?: string
}

/** Best-effort: queue one notification for one user. Never throws. */
export async function notifyUser(userId: string, n: NotificationInput): Promise<void> {
  try {
    await ensureNotificationSchema()
    await db.notification.create({
      data: {
        userId,
        type: n.type,
        title: n.title,
        body: n.body || '',
        linkUrl: n.linkUrl || null,
        actorId: n.actorId || null,
      },
    })
  } catch (e) {
    console.error('[notifications] notifyUser failed:', e)
  }
}

/** Best-effort: one notification for EVERY member except the actor
 *  (used for "X joined RetroBlox!"). Batched in chunks. Never throws. */
export async function notifyEveryone(n: NotificationInput, exceptUserId?: string): Promise<void> {
  try {
    await ensureNotificationSchema()
    const users = await db.user.findMany({
      where: exceptUserId ? { id: { not: exceptUserId } } : {},
      select: { id: true },
    })
    if (users.length === 0) return
    const rows = users.map((u) => ({
      userId: u.id,
      type: n.type,
      title: n.title,
      body: n.body || '',
      linkUrl: n.linkUrl || null,
      actorId: n.actorId || null,
    }))
    // chunk so a huge member list can't blow a single statement limit
    for (let i = 0; i < rows.length; i += 100) {
      await db.notification.createMany({ data: rows.slice(i, i + 100) })
    }
  } catch (e) {
    console.error('[notifications] notifyEveryone failed:', e)
  }
}
