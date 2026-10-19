import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { DEFAULT_SITE_UI, normalizeSiteUi } from '@/lib/siteui-config'

/* ------------------------------------------------------------------
   /api/site-ui — the WEB UI the owner edits at /site-ui.

   GET  (public)  -> the current config, merged over the defaults.
                      Never throws: a missing table or empty row just
                      means "the site looks like the default theme".
   PUT  (admin)   -> save a new config. Only the site owner (role
                      admin) can touch the web's UI; everyone else
                      gets 403.
------------------------------------------------------------------ */

export const dynamic = 'force-dynamic'

export async function GET() {
  try {
    const row = await db.siteUi.findUnique({ where: { id: 1 } })
    return NextResponse.json({ config: normalizeSiteUi(row ? safeJson(row.config) : null) })
  } catch {
    return NextResponse.json({ config: DEFAULT_SITE_UI })
  }
}

export async function PUT(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  if (user.role !== 'admin') {
    return NextResponse.json({ error: 'Only the site owner can edit the web UI' }, { status: 403 })
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const config = normalizeSiteUi((body as { config?: unknown })?.config ?? body)

  try {
    await db.siteUi.upsert({
      where: { id: 1 },
      update: { config: JSON.stringify(config) },
      create: { id: 1, config: JSON.stringify(config) },
    })
  } catch {
    // self-heal: the row/table may not exist yet on a fresh database
    try {
      await db.$executeRawUnsafe(
        `CREATE TABLE IF NOT EXISTS "SiteUi" ("id" INTEGER NOT NULL PRIMARY KEY, "config" TEXT NOT NULL, "updatedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)`
      )
      await db.$executeRawUnsafe(
        `INSERT INTO "SiteUi" ("id","config","updatedAt") VALUES (1, ?, CURRENT_TIMESTAMP)
         ON CONFLICT("id") DO UPDATE SET "config" = excluded."config", "updatedAt" = CURRENT_TIMESTAMP`,
        JSON.stringify(config)
      )
    } catch {
      return NextResponse.json({ error: 'Could not save site UI' }, { status: 500 })
    }
  }

  return NextResponse.json({ ok: true, config })
}

function safeJson(s: string): unknown {
  try {
    return JSON.parse(s)
  } catch {
    return null
  }
}
