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
 *   2. Connect to the cloud database and run that script — but ONLY if
 *      the database is still empty.
 *
 * - Fresh Turso database  -> all 34 tables get created during the build.
 * - Already-populated DB  -> untouched, redeploying is always safe.
 * - Local "file:" dev DB  -> no-op, nothing happens.
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

  // already deployed before? NEVER touch existing data
  const existing = await client.execute(
    "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
  )
  const tableCount = Number(existing.rows[0]?.n ?? 0)
  if (tableCount > 0) {
    console.log(
      `[sync-schema] database already has ${tableCount} tables — skipping. Your data is safe.`
    )
    process.exit(0)
  }

  console.log('[sync-schema] fresh cloud database — creating all tables…')

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

  await client.executeMultiple(ddl)

  const after = await client.execute(
    "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
  )
  console.log(
    `[sync-schema] done! ${Number(after.rows[0]?.n ?? 0)} tables are ready. 🎉`
  )
  process.exit(0)
} catch (err) {
  // FAIL-SOFT: a bad/unreachable DATABASE_URL must never block the deploy.
  // The site goes live anyway and /api/health pinpoints the exact problem.
  console.error('')
  console.error('==============================================================')
  console.error('[sync-schema] WARNING: could not set up the database tables.')
  console.error('[sync-schema] Reason: ' + (err?.message || err))
  console.error('[sync-schema]')
  console.error('[sync-schema] The build CONTINUES so the site still deploys.')
  console.error('[sync-schema] If the site then errors (login fails, pages 500),')
  console.error('[sync-schema] fix in this order, then Redeploy:')
  console.error('[sync-schema]   1. Vercel -> your project -> Settings ->')
  console.error('[sync-schema]      Environment Variables. DATABASE_URL must be')
  console.error('[sync-schema]      ONE line, no quotes, no spaces, like:')
  console.error('[sync-schema]      libsql://your-db-host.turso.io?authToken=YOUR_TOKEN')
  console.error('[sync-schema]   2. Env vars are PER-PROJECT on Vercel — a project')
  console.error('[sync-schema]      freshly connected to GitHub starts EMPTY.')
  console.error('[sync-schema]      Add all 4: DATABASE_URL, AUTH_SECRET,')
  console.error('[sync-schema]      STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET.')
  console.error('[sync-schema]   3. Open https://YOUR-SITE/api/health — it tells')
  console.error('[sync-schema]      you exactly which variable is wrong.')
  console.error('==============================================================')
  console.error('')
  process.exit(0)
}
