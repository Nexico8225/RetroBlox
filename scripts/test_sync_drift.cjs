/**
 * Simulates the LIVE Turso database having drifted behind schema.prisma:
 *   - Notification table exists but WITHOUT link / dataJson  (the /api/notifications 500 bug)
 *   - User without robuxBalance
 *   - UgcOffer without robux, UgcTrade without robuxFrom/robuxTo
 * then runs sync-schema against it (SYNC_SCHEMA_URL) and verifies the
 * auto-healer adds every missing column WITHOUT touching existing rows.
 * Idempotency: a second run must change nothing.
 */
const { createClient } = require('@libsql/client')
const { execSync } = require('node:child_process')
const fs = require('node:fs')

const FILE = 'db/sync-drift-test.db'
try { fs.unlinkSync(FILE) } catch {}
try { fs.unlinkSync(FILE + '-wal') } catch {}
try { fs.unlinkSync(FILE + '-shm') } catch {}

async function main() {
  const c = createClient({ url: `file:${FILE}` })

  // ---- build the "old live" schema (deliberately behind) ------------------
  await c.executeMultiple(`
    CREATE TABLE "User" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "username" TEXT NOT NULL,
      "passwordHash" TEXT NOT NULL,
      "rbxBalance" INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE "Notification" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "userId" TEXT NOT NULL,
      "type" TEXT NOT NULL,
      "title" TEXT NOT NULL,
      "body" TEXT NOT NULL DEFAULT '',
      "readAt" DATETIME,
      "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE "UgcOffer" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "listingId" TEXT NOT NULL,
      "buyerId" TEXT NOT NULL,
      "amount" INTEGER NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending'
    );
    CREATE TABLE "UgcTrade" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "fromUserId" TEXT NOT NULL,
      "toUserId" TEXT NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending',
      "giveItemIds" TEXT NOT NULL DEFAULT '[]',
      "takeItemIds" TEXT NOT NULL DEFAULT '[]',
      "tixFrom" INTEGER NOT NULL DEFAULT 0,
      "tixTo" INTEGER NOT NULL DEFAULT 0
    );
    INSERT INTO "User" ("id","username","passwordHash","rbxBalance") VALUES ('u1','oldplayer','x',4200);
    INSERT INTO "Notification" ("id","userId","type","title") VALUES ('n1','u1','friend_request','old friend req');
    INSERT INTO "UgcOffer" ("id","listingId","buyerId","amount") VALUES ('o1','l1','u1',500);
    INSERT INTO "UgcTrade" ("id","fromUserId","toUserId","status") VALUES ('t1','u1','u2','pending');
  `)
  console.log('[test] drifted fixture built (old column sets + 4 rows of data)')

  // ---- run the sync the way Vercel build does -----------------------------
  const out = execSync('node scripts/sync-schema.mjs', {
    encoding: 'utf8',
    env: { ...process.env, SYNC_SCHEMA_URL: `file:${FILE}` },
  })
  console.log(out)

  const fail = (msg) => { console.error(`[test] FAIL: ${msg}`); process.exit(1) }

  const cols = async (t) => (await c.execute(`PRAGMA table_info("${t}")`)).rows.map((r) => String(r.name))
  // Notification needed its link + dataJson (the prod 500) — and everything else current
  let ok = true
  for (const need of ['link', 'dataJson']) if (!(await cols('Notification')).includes(need)) { ok = false; console.error(`Notification missing ${need}`) }
  if (!(await cols('User')).includes('robuxBalance')) { ok = false; console.error('User missing robuxBalance') }
  if (!(await cols('UgcOffer')).includes('robux')) { ok = false; console.error('UgcOffer missing robux') }
  for (const need of ['robuxFrom', 'robuxTo']) if (!(await cols('UgcTrade')).includes(need)) { ok = false; console.error(`UgcTrade missing ${need}`) }
  if (!ok) fail('auto-healer did not add every missing column')
  console.log('[test] PASS: every missing column was added by the auto-healer')

  // ---- data survived ------------------------------------------------------
  const u = await c.execute(`SELECT rbxBalance, username FROM "User" WHERE id='u1'`)
  if (Number(u.rows[0].rbxBalance) !== 4200 || u.rows[0].username !== 'oldplayer') fail('existing row data was touched!')
  const n = await c.execute(`SELECT title, body FROM "Notification" WHERE id='n1'`)
  if (n.rows[0].title !== 'old friend req') fail('notification row was touched!')
  // new NOT NULL-with-default columns read as their defaults on old rows
  const o = await c.execute(`SELECT robux FROM "UgcOffer" WHERE id='o1'`)
  if (Number(o.rows[0].robux) !== 0) fail('new robux column should read 0 for old rows')
  console.log('[test] PASS: old rows intact, new columns read defaults')

  // ---- idempotent second run ---------------------------------------------
  const out2 = execSync('node scripts/sync-schema.mjs', {
    encoding: 'utf8',
    env: { ...process.env, SYNC_SCHEMA_URL: `file:${FILE}` },
  })
  if (!/up to date|ensured/.test(out2)) fail('second run behaved unexpectedly: ' + out2)
  console.log('[test] PASS: second run is a safe no-op')

  console.log('[test] ALL CHECKS PASSED ✅')
}

main().catch((e) => { console.error('[test] ERROR', e); process.exit(1) })
