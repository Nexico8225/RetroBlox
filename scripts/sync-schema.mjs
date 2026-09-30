/**
 * BUILD-TIME SCHEMA SYNC — creates all database tables automatically.
 *
 * WHY THIS EXISTS:
 * Vercel/Netlify servers cannot write to their own disk, so RetroBlox
 * uses a free Turso (libSQL) cloud database when DATABASE_URL starts
 * with "libsql://". But the Prisma 6 CLI only accepts "file:" URLs for
 * `prisma db push`, so it cannot create tables in Turso by itself.
 * This script bridges that gap with @libsql/client (already installed):
 *
 *   1. Ask `prisma migrate diff` to turn prisma/schema.prisma into a
 *      plain CREATE TABLE script (purely offline, no DB connection).
 *   2. Connect to the cloud database and apply what is MISSING:
 *      - fresh/empty database  -> every table + index is created
 *      - existing database     -> only NEW tables and NEW indexes are
 *        added (CREATE ... IF NOT EXISTS), plus the hand-listed new
 *        columns below (COLUMN_PATCHES) are ALTERed in. Existing data
 *        is NEVER touched, so redeploying is always safe.
 *
 * The existing-DB path is what ships new features: any table added to
 * schema.prisma appears on the live Turso automatically on the next
 * deploy — no terminal, no manual import, no data loss.
 *
 * Token sources: ?authToken= inside DATABASE_URL, or LIBSQL_AUTH_TOKEN /
 * TURSO_AUTH_TOKEN env vars. Set for testing: SYNC_SCHEMA_URL overrides
 * the target (used to simulate a cloud DB with a local file).
 */
import { createClient } from '@libsql/client'
import { execSync } from 'node:child_process'

// ---------------------------------------------------------------------------
// COLUMN PATCHES — new columns on tables that ALREADY exist in the live
// database. Prisma's from-empty diff only emits CREATE TABLEs, so additions
// to existing tables are listed here (checked against table_info first, so
// they are idempotent). Append a patch when you add a column to schema.prisma.
// ---------------------------------------------------------------------------
const COLUMN_PATCHES = [
  { table: 'InventoryEntry', column: 'serial', ddl: 'ALTER TABLE InventoryEntry ADD COLUMN serial INTEGER' },
  // market pitches + UGC-on-offers (web-market-2)
  { table: 'UgcListing', column: 'title', ddl: "ALTER TABLE UgcListing ADD COLUMN title TEXT NOT NULL DEFAULT ''" },
  { table: 'UgcListing', column: 'description', ddl: "ALTER TABLE UgcListing ADD COLUMN description TEXT NOT NULL DEFAULT ''" },
  { table: 'UgcOffer', column: 'offerItemIdsJson', ddl: "ALTER TABLE UgcOffer ADD COLUMN offerItemIdsJson TEXT NOT NULL DEFAULT '[]'" },
]

const envUrl = process.env.DATABASE_URL || ''
const url = process.env.SYNC_SCHEMA_URL || envUrl
// test hook (SYNC_SCHEMA_URL) can force a run against any target;
// production only ever syncs when the real DATABASE_URL is a cloud one
const isCloud =
  envUrl.startsWith('libsql:') || Boolean(process.env.SYNC_SCHEMA_URL)

// local SQLite dev database — Prisma handles files natively, nothing to do
if (!isCloud) {
  console.log('[sync-schema] local file database detected — nothing to sync.')
  process.exit(0)
}

// the token can ride inside the URL (?authToken=...) or a separate env var
const fromUrl = url.match(/[?&]authToken=([^&]+)/)?.[1]
const authToken =
  fromUrl || process.env.LIBSQL_AUTH_TOKEN || process.env.TURSO_AUTH_TOKEN

console.log('[sync-schema] connecting to cloud database…')

try {
  const client = createClient({
    url,
    ...(authToken ? { authToken } : {}),
  })

  const existing = await client.execute(
    "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
  )
  const tableCount = Number(existing.rows[0]?.n ?? 0)

  // pure offline operation: schema.prisma -> CREATE TABLE script
  // (diff never connects anywhere, but schema validation wants a
  // file: URL when DATABASE_URL is a libsql:// one — give it a dummy)
  const raw = execSync(
    'npx --no-install prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script',
    {
      encoding: 'utf8',
      env: { ...process.env, DATABASE_URL: 'file:./.schema-diff-dummy.db' },
    }
  )

  // statement-level split (migrate diff emits one statement per ';',
  // each prefixed by a `-- CreateTable` style comment line)
  const statements = raw
    .split(';')
    .map((s) =>
      s
        .split('\n')
        .filter((line) => {
          const up = line.trim().toUpperCase()
          return !up.startsWith('PRAGMA') && !up.startsWith('--')
        })
        .join('\n')
        .trim()
    )
    .filter(Boolean)

  // keep ONLY the additive DDL — never DROP, never INSERT, never SET
  const creates = statements
    .filter((s) => /^CREATE TABLE\b/i.test(s))
    .map((s) => s.replace(/CREATE TABLE /i, 'CREATE TABLE IF NOT EXISTS '))
  const indexes = statements
    .filter((s) => /^CREATE (UNIQUE )?INDEX\b/i.test(s))
    .map((s) => s.replace(/CREATE (UNIQUE )?INDEX /i, 'CREATE $1INDEX IF NOT EXISTS '))

  if (tableCount === 0) {
    console.log('[sync-schema] fresh cloud database — creating all tables…')
    await client.executeMultiple(
      [...creates, ...indexes]
        .join(';\n')
        .replace(/CREATE TABLE /g, 'CREATE TABLE ') + ';\n'
    )
    const after = await client.execute(
      "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
    )
    console.log(`[sync-schema] done! ${Number(after.rows[0]?.n ?? 0)} tables are ready. 🎉`)
    process.exit(0)
  }

  // ---- existing database: apply ONLY what is missing ---------------------
  console.log(`[sync-schema] existing database (${tableCount} tables) — checking for missing tables, indexes and columns…`)

  let applied = 0
  // 1. missing tables (IF NOT EXISTS makes replays harmless)
  for (const ddl of [...creates, ...indexes]) {
    try {
      await client.execute(ddl)
      applied++
      const name = ddl.match(/^CREATE (?:UNIQUE )?(?:INDEX IF NOT EXISTS |TABLE IF NOT EXISTS |TABLE )"?(\w+)"?/i)?.[1] || ddl.slice(0, 60)
      console.log(`[sync-schema]   + ensured: ${name}`)
    } catch (e) {
      console.error(`[sync-schema]   ! skipped a statement: ${e?.message || e}`)
    }
  }

  // 2. missing columns on existing tables (checked via table_info first)
  for (const patch of COLUMN_PATCHES) {
    try {
      const info = await client.execute(`PRAGMA table_info(${patch.table})`)
      const has = info.rows.some((r) => String(r.name) === patch.column)
      if (has) continue
      await client.execute(patch.ddl)
      applied++
      console.log(`[sync-schema]   + column: ${patch.table}.${patch.column}`)
    } catch (e) {
      console.error(`[sync-schema]   ! column patch ${patch.table}.${patch.column} failed: ${e?.message || e}`)
    }
  }

  console.log(applied > 0
    ? `[sync-schema] applied ${applied} schema addition(s). Your data is safe. ✅`
    : '[sync-schema] schema already up to date — nothing to do. ✅')
  process.exit(0)
} catch (err) {
  console.error('[sync-schema] FAILED:', err?.message || err)
  process.exit(1)
}
