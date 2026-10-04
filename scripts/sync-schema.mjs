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
 *   2. Connect to the cloud database and run that script.
 *
 * - Fresh Turso database  -> all tables get created during the build.
 * - Already-populated DB  -> every statement is CREATE ... IF NOT EXISTS,
 *   so existing tables AND their data are never touched, while tables
 *   added to the schema since the last deploy (new features) get created.
 * - Local "file:" dev DB  -> no-op, nothing happens (Prisma pushes files).
 *
 * NOTE: this only creates MISSING TABLES. Adding a column to an existing
 * model needs a one-off migration (Turso does not ALTER here on purpose —
 * touching live columns is how data gets destroyed).
 *
 * Token sources: ?authToken= inside DATABASE_URL, or LIBSQL_AUTH_TOKEN /
 * TURSO_AUTH_TOKEN env vars. Set for testing: SYNC_SCHEMA_URL overrides
 * the target (used to simulate a cloud DB with a local file).
 */
import { createClient } from '@libsql/client'
import { execSync } from 'node:child_process'

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

  // snapshot which tables exist BEFORE the run, for the summary line
  const before = await client.execute(
    "SELECT name FROM sqlite_master WHERE type = 'table'"
  )
  const known = new Set(before.rows.map((r) => String(r.name)))
  if (known.size > 0) {
    console.log(
      `[sync-schema] database has ${known.size} tables — creating any MISSING tables only (existing data untouched).`
    )
  } else {
    console.log('[sync-schema] fresh cloud database — creating all tables…')
  }

  // pure offline operation: schema.prisma -> CREATE TABLE script
  const raw = execSync(
    'npx --no-install prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script',
    {
      encoding: 'utf8',
      // diff never connects anywhere, but schema validation wants a
      // file: URL when DATABASE_URL is a libsql:// one — give it a dummy
      env: { ...process.env, DATABASE_URL: 'file:./.schema-diff-dummy.db' },
    }
  )

  // make every CREATE idempotent (extra safety for parallel deploys)
  // and drop PRAGMA lines (cloud libSQL ignores some of them)
  const ddl = raw
    .split('\n')
    .filter((line) => !line.trim().toUpperCase().startsWith('PRAGMA'))
    .join('\n')
    .replace(/CREATE TABLE /g, 'CREATE TABLE IF NOT EXISTS ')
    .replace(/CREATE UNIQUE INDEX /g, 'CREATE UNIQUE INDEX IF NOT EXISTS ')
    .replace(/CREATE INDEX /g, 'CREATE INDEX IF NOT EXISTS ')

  // which models does the schema promise? (model X { ... } lines)
  const wanted = [...raw.matchAll(/^model (\w+)/gm)].map((m) => m[1])
  const missing = wanted.filter((t) => !known.has(t))

  await client.executeMultiple(ddl)

  const after = await client.execute(
    "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
  )
  if (missing.length > 0) {
    console.log(`[sync-schema] created ${missing.length} new table(s): ${missing.join(', ')}`)
  }
  console.log(
    `[sync-schema] done! ${Number(after.rows[0]?.n ?? 0)} tables are ready. 🎉`
  )
  process.exit(0)
} catch (err) {
  console.error('[sync-schema] FAILED:', err?.message || err)
  process.exit(1)
}
