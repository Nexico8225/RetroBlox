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
// COLUMN PATCHES — hand-written escape hatch for anything the auto-healer
// can't express (renames, backfills). The AUTO-HEALER below now covers the
// common case by itself: every column that exists in schema.prisma but is
// missing from the live table is ALTERed in automatically — no manual list
// to forget, which is exactly how a "missing column" 500 slips into prod.
// ---------------------------------------------------------------------------
const COLUMN_PATCHES = [
  { table: 'InventoryEntry', column: 'serial', ddl: 'ALTER TABLE InventoryEntry ADD COLUMN serial INTEGER' },
  // market pitches + UGC-on-offers (web-market-2)
  { table: 'UgcListing', column: 'title', ddl: "ALTER TABLE UgcListing ADD COLUMN title TEXT NOT NULL DEFAULT ''" },
  { table: 'UgcListing', column: 'description', ddl: "ALTER TABLE UgcListing ADD COLUMN description TEXT NOT NULL DEFAULT ''" },
  { table: 'UgcOffer', column: 'offerItemIdsJson', ddl: "ALTER TABLE UgcOffer ADD COLUMN offerItemIdsJson TEXT NOT NULL DEFAULT '[]'" },
]

// ---------------------------------------------------------------------------
// AUTO-HEALER — turn each CREATE TABLE from the prisma diff into
//   { table: "Notification", columns: [{ name: "id", def: '"id" TEXT NOT NULL PRIMARY KEY' }, ...] }
// so any column the live database is missing can be ALTERed in on its own.
// ---------------------------------------------------------------------------
const DEFAULT_FOR_TYPE = (ddl) => {
  const up = ddl.toUpperCase()
  if (/\bTEXT\b/.test(up)) return "DEFAULT ''"
  if (/\bDATETIME\b/.test(up)) return 'DEFAULT CURRENT_TIMESTAMP'
  return 'DEFAULT 0' // INTEGER / BOOLEAN / REAL — zero is a sane start for all of them
}

function parseCreateTable(ddl) {
  const name = ddl.match(/^CREATE TABLE (?:IF NOT EXISTS )?"?(\w+)"?/i)?.[1]
  if (!name) return null
  const open = ddl.indexOf('(')
  const body = ddl.slice(open + 1, ddl.lastIndexOf(')'))
  // split on top-level commas only (DEFAULT ('a','b') style values keep their commas)
  const parts = []
  let depth = 0, cur = ''
  for (const ch of body) {
    if (ch === '(') depth++
    if (ch === ')') depth--
    if (ch === ',' && depth === 0) { parts.push(cur); cur = '' } else cur += ch
  }
  if (cur.trim()) parts.push(cur)
  const columns = []
  for (const raw of parts) {
    const def = raw.trim().replace(/,+$/, '')
    if (!def) continue
    const first = def.toUpperCase()
    if (first.startsWith('CONSTRAINT') || first.startsWith('PRIMARY KEY') || first.startsWith('FOREIGN KEY') || first.startsWith('UNIQUE (') || first.startsWith('UNIQUE(') || first.startsWith('CHECK')) continue
    const colName = def.match(/^"([^"]+)"/)?.[1] || def.match(/^\s*(\w+)/)?.[1]
    if (!colName) continue
    columns.push({ name: colName, def })
  }
  return { name, columns }
}

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
  // 1. missing TABLES first (columns and indexes both need their home)
  for (const ddl of creates) {
    try {
      await client.execute(ddl)
      applied++
      const name = ddl.match(/^CREATE (?:TABLE IF NOT EXISTS |TABLE )"?(\w+)"?/i)?.[1] || ddl.slice(0, 60)
      console.log(`[sync-schema]   + ensured: ${name}`)
    } catch (e) {
      console.error(`[sync-schema]   ! skipped a statement: ${e?.message || e}`)
    }
  }

  // 2. missing COLUMNS — the auto-healer: compare every table's live columns
  //    (PRAGMA table_info) against the schema.prisma CREATE TABLE bodies and
  //    ALTER in anything absent. This is what makes "added a field, forgot to
  //    list it here" bugs impossible: the schema file itself is the checklist.
  const parsed = creates.map(parseCreateTable).filter(Boolean)
  for (const t of parsed) {
    let liveCols = []
    try {
      const info = await client.execute(`PRAGMA table_info("${t.name}")`)
      liveCols = info.rows.map((r) => String(r.name))
    } catch { continue /* table vanished mid-run — next deploy will retry */ }
    const missing = t.columns.filter((c) => !liveCols.includes(c.name))
    for (const col of missing) {
      // try the exact schema definition first; fall back to a defaulted,
      // constraint-free version when SQLite refuses (NOT NULL on a table
      // that already has rows, or inline PRIMARY KEY / UNIQUE which ALTER
      // cannot add)
      const attempts = [col.def, `${col.def} ${DEFAULT_FOR_TYPE(col.def)}`, `"${col.name}" ${DEFAULT_FOR_TYPE(col.def)}`]
      let ok = false
      for (const attempt of [...new Set(attempts)]) {
        try {
          await client.execute(`ALTER TABLE "${t.name}" ADD COLUMN ${attempt}`)
          applied++
          console.log(`[sync-schema]   + column: ${t.name}.${col.name}`)
          ok = true
          break
        } catch { /* next attempt */ }
      }
      if (!ok) console.error(`[sync-schema]   ! could not add column ${t.name}.${col.name} — will retry next deploy`)
    }
  }

  // 2b. the hand-listed patches (kept for cases the heuristic can't express)
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

  // 3. missing INDEXES last — a fresh unique index may target a column that
  //    step 2 just added
  for (const ddl of indexes) {
    try {
      await client.execute(ddl)
      applied++
      const name = ddl.match(/^CREATE (?:UNIQUE )?(?:INDEX IF NOT EXISTS |INDEX )"?(\w+)"?/i)?.[1] || ddl.slice(0, 60)
      console.log(`[sync-schema]   + ensured: ${name}`)
    } catch (e) {
      console.error(`[sync-schema]   ! skipped a statement: ${e?.message || e}`)
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
