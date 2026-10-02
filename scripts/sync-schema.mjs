/**
 * BUILD-TIME SCHEMA SYNC — creates all database tables automatically AND
 * adds any MISSING COLUMNS to an already-populated database.
 *
 * WHY THIS EXISTS:
 * Vercel/Netlify servers cannot write to their own disk, so RetroBlox
 * uses a free Turso (libSQL) cloud database when DATABASE_URL starts
 * with "libsql://". But the Prisma 6 CLI only accepts "file:" URLs for
 * `prisma db push`, so it cannot create tables or columns in Turso by
 * itself. This script bridges that gap with @libsql/client (already
 * installed):
 *
 *   1. Ask `prisma migrate diff` to turn prisma/schema.prisma into a
 *      plain CREATE TABLE script (purely offline, no DB connection).
 *   2. Connect to the cloud database.
 *   3. Fresh database -> run the whole script (all tables appear).
 *      Populated database -> NEVER touch data. Instead, compare every
 *      expected column with the live `PRAGMA table_info` and run a
 *      safe `ALTER TABLE ... ADD COLUMN` for each missing one, so new
 *      schema fields (metallic, roughness, ...) ship with the deploy.
 *
 * - Fresh Turso database  -> all tables get created during the build.
 * - Already-populated DB  -> only additive column patches, data is safe.
 * - Local "file:" dev DB  -> no-op, nothing happens (prisma db push
 *   handles files natively).
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

  // pure offline operation: schema.prisma -> CREATE TABLE script (needed for
  // BOTH paths — fresh installs run it whole, existing ones get parsed)
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

  if (tableCount > 0) {
    console.log(
      `[sync-schema] database already has ${tableCount} tables — adding any missing columns…`
    )
    let patched = 0
    try {
      // parse the DDL into { table: [(name, declType)] } so each expected
      // column can be checked against the live table. CREATE TABLE blocks
      // end at a line that is exactly ");" (or ");") — the parser below
      // handles both the quoted-name and plain-name styles Prisma emits.
      const expected = new Map()
      let curTable = null
      for (const line of raw.split('\n')) {
        const t = line.match(/^\s*CREATE TABLE\s+"?(\w+)"?\s*\(/i)
        if (t) {
          curTable = t[1]
          expected.set(curTable, [])
          continue
        }
        if (curTable) {
          if (/^\s*\);?\s*$/.test(line)) {
            curTable = null
            continue
          }
          const col = line.match(/^\s*"(\w+)"\s+([A-Za-z]+(?:\(\d+\))?)/)
          if (col) expected.get(curTable).push([col[1], col[2]])
        }
      }
      // every table the live DB actually has
      const liveTables = new Set(
        (
          await client.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_prisma%' AND name NOT LIKE '_cf_%'"
          )
        ).rows.map((r) => r.name)
      )
      for (const [table, cols] of expected) {
        if (!liveTables.has(table) || cols.length === 0) continue
        const have = new Set(
          (await client.execute(`PRAGMA table_info("${table}")`)).rows.map((r) => r.name)
        )
        for (const [col, decl] of cols) {
          if (have.has(col)) continue
          // ADD COLUMN is always safe: new columns are NULL for existing rows
          await client.execute(`ALTER TABLE "${table}" ADD COLUMN "${col}" ${decl}`)
          console.log(`[sync-schema]   + ${table}.${col} ${decl}`)
          patched++
        }
      }
      if (patched === 0) console.log('[sync-schema]   schema is up to date — nothing to add.')
      else console.log(`[sync-schema]   ${patched} column(s) added. Data untouched.`)
    } catch (err) {
      // the deploy must NEVER fail because of the sync; the app tolerates
      // older schemas worse than a hard stop, so log loudly and continue
      console.error('[sync-schema] column sync warning:', err?.message || err)
    }
    console.log('[sync-schema] done.')
    process.exit(0)
  }

  console.log('[sync-schema] fresh cloud database — creating all tables…')

  await client.executeMultiple(ddl)

  const after = await client.execute(
    "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
  )
  console.log(
    `[sync-schema] done! ${Number(after.rows[0]?.n ?? 0)} tables are ready. 🎉`
  )
  process.exit(0)
} catch (err) {
  console.error('[sync-schema] FAILED:', err?.message || err)
  process.exit(1)
}
