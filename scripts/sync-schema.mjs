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

  // already deployed before? NEVER touch existing data — but DO bring the
  // schema up to date when the prisma model gained NEW COLUMNS (additive
  // evolution: roughness/metallic, future fields) or NEW TABLES (the place
  // chat/presence models). Old deploys otherwise 500 forever because the
  // Prisma client queries tables/columns SQLite never got.
  const existing = await client.execute(
    "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
  )
  const tableCount = Number(existing.rows[0]?.n ?? 0)
  if (tableCount > 0) {
    console.log(
      `[sync-schema] database already has ${tableCount} tables — checking for missing tables + columns…`
    )
    // COLUMNS/tables go first (addMissingColumns adds per-statement with its
    // own try/catch), then the full idempotent DDL statement-by-statement —
    // a new unique index can reference a new column (User.seqId), so this
    // order guarantees the column exists before the index is created.
    await addMissingColumns(client)
    await runIdempotentDdl(client)
    const after = await client.execute(
      "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
    )
    console.log(
      `[sync-schema] done! ${Number(after.rows[0]?.n ?? 0)} tables are ready. 🎉`
    )
    process.exit(0)
  }

  console.log('[sync-schema] fresh cloud database — creating all tables…')
  await client.executeMultiple(buildIdempotentDdl())

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

/** schema.prisma -> one idempotent CREATE script (offline, no DB connection).
 *  Every CREATE gets IF NOT EXISTS so it is always safe to run. */
function buildIdempotentDdl() {
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
  return raw
    .split('\n')
    .filter((line) => !line.trim().toUpperCase().startsWith('PRAGMA'))
    .join('\n')
    .replace(/CREATE TABLE /g, 'CREATE TABLE IF NOT EXISTS ')
    .replace(/CREATE UNIQUE INDEX /g, 'CREATE UNIQUE INDEX IF NOT EXISTS ')
    .replace(/CREATE INDEX /g, 'CREATE INDEX IF NOT EXISTS ')
}

/** Run the idempotent DDL on an EXISTING database — one statement at a time,
 *  each with its own try/catch. A single drifted index must never abort the
 *  whole batch (executeMultiple would stop at the first error). */
async function runIdempotentDdl(client) {
  const script = buildIdempotentDdl()
  const statements = script
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0)
  for (const stmt of statements) {
    try {
      await client.execute(stmt + ';')
    } catch (err) {
      console.warn(`[sync-schema] ddl statement skipped: ${err?.message || err}`)
    }
  }
}

/* ------------------------------------------------------------------
   ADDITIVE COLUMN SYNC — the deploy-time auto-fixer for schema drift.

   SQLite cannot be asked "diff me against a prisma model" natively, so:
     1. `prisma migrate diff --from-empty --to-schema-datamodel` produces
        the DESIRED CREATE TABLE DDL (offline, no DB connection).
     2. For every table in that DDL, PRAGMA table_info lists the columns
        the live database actually has.
     3. Columns present in the DDL but missing live are added with
        `ALTER TABLE ... ADD COLUMN` — SQLite only supports ADD, which is
        exactly the safe subset: no data is ever rewritten or dropped.

   Idempotent by construction: the second deploy finds no missing columns
   and does nothing. Nullable / defaulted columns only, which every
   additive prisma field is.
------------------------------------------------------------------ */

/** Extract the column-definition lines from a captured CREATE TABLE body.
 *  `createSql` is the regex capture between the table's "(" and the final ");"
 *  (i.e. it starts with the first column line and ends with ")"). */
function parseColumns(createSql) {
  const close = createSql.lastIndexOf(')')
  if (close < 0) return []
  const body = createSql.slice(0, close)
  // split on top-level commas (parens can appear inside DEFAULT (expr))
  const parts = []
  let depth = 0
  let cur = ''
  for (const ch of body) {
    if (ch === '(') depth++
    if (ch === ')') depth--
    if (ch === ',' && depth === 0) {
      parts.push(cur)
      cur = ''
    } else cur += ch
  }
  if (cur.trim()) parts.push(cur)
  return parts
    .map((p) => p.trim())
    .filter((p) => /^"[^"]+"/.test(p)) // real column defs start with a quoted name
    .map((p) => {
      const name = p.match(/^"([^"]+)"/)[1]
      return { name, def: p }
    })
}

async function addMissingColumns(client) {
  // 1. the DESIRED state, straight from prisma/schema.prisma (offline)
  const raw = execSync(
    'npx --no-install prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script',
    {
      encoding: 'utf8',
      env: { ...process.env, DATABASE_URL: 'file:./.schema-diff-dummy.db' },
    }
  )

  // 2. every CREATE TABLE in the desired DDL
  const creates = [...raw.matchAll(/CREATE TABLE "([^"]+)" \(([\s\S]*?\);\n)/g)]
  if (creates.length === 0) {
    console.log('[sync-schema] no CREATE TABLE statements parsed — nothing to do.')
    return
  }

  let added = 0
  const haveTables = new Set(
    (await client.execute("SELECT name FROM sqlite_master WHERE type = 'table'")).rows.map((r) => String(r.name))
  )
  for (const [, table, fullSql] of creates) {
    if (!haveTables.has(table)) {
      // table does not exist yet — create it wholesale (IF NOT EXISTS is a
      // no-op when another deploy already made it)
      try {
        const stmt = raw.slice(raw.indexOf(`CREATE TABLE "${table}"`), raw.indexOf(';', raw.indexOf(`CREATE TABLE "${table}"`)) + 1)
        await client.execute(stmt.replace('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS '))
        added++
        console.log(`[sync-schema] + table ${table}`)
      } catch (err) {
        console.warn(`[sync-schema] could not create ${table}: ${err?.message || err}`)
      }
      continue
    }
    const info = await client.execute(`PRAGMA table_info("${table}")`)
    const liveCols = new Set(info.rows.map((r) => String(r.name)))
    for (const col of parseColumns(fullSql)) {
      if (liveCols.has(col.name)) continue
      // col.def starts with the quoted name: `"roughness" REAL` — exactly the
      // shape ALTER TABLE ADD COLUMN wants. Skipping existing columns makes
      // this idempotent; ADD COLUMN never rewrites data, only extends rows.
      try {
        await client.execute(`ALTER TABLE "${table}" ADD COLUMN ${col.def}`)
        added++
        console.log(`[sync-schema] + ${table}.${col.name}`)
      } catch (err) {
        console.warn(`[sync-schema] could not add ${table}.${col.name}: ${err?.message || err}`)
      }
    }
  }

  // 3. unique indexes the DDL declares (e.g. User.seqId) — CREATE UNIQUE
  //    INDEX IF NOT EXISTS is idempotent; SQLite unique indexes allow any
  //    number of NULLs, so backfill-in-progress rows never clash
  for (const m of raw.matchAll(/CREATE (UNIQUE )?INDEX "([^"]+)" ON "[^"]+" \(/g)) {
    const unique = m[1] || ''
    const idxName = m[2]
    const start = raw.indexOf(`CREATE ${unique}INDEX "${idxName}"`)
    const stmt = raw.slice(start, raw.indexOf(';', start) + 1).replace(/CREATE (UNIQUE )?INDEX /, `CREATE $1INDEX IF NOT EXISTS `)
    try {
      await client.execute(stmt)
    } catch (err) {
      console.warn(`[sync-schema] index ${idxName}: ${err?.message || err}`)
    }
  }

  // 4. ONE-TIME BACKFILLS — small, idempotent data fixes new columns need.
  //    Sequential player numbers: oldest account = #1, newest = last.
  try {
    const pending = await client.execute(
      'SELECT count(*) AS n FROM "User" WHERE "seqId" IS NULL'
    )
    if (Number(pending.rows[0]?.n ?? 0) > 0) {
      await client.execute(`
        UPDATE "User" SET "seqId" = (
          SELECT COUNT(*) FROM "User" AS u2
          WHERE u2."createdAt" <= "User"."createdAt"
        )
        WHERE "seqId" IS NULL`)
      console.log(`[sync-schema] seqId backfilled for ${Number(pending.rows[0].n)} user(s) (signup order).`)
    }
  } catch (err) {
    console.warn(`[sync-schema] seqId backfill: ${err?.message || err}`)
  }

  console.log(added > 0 ? `[sync-schema] schema updated — ${added} change(s) applied.` : '[sync-schema] schema is up to date — nothing to add.')
}
