/**
 * dbdiag — the database's built-in doctor + paramedic.
 *
 * TWO jobs, both born from one painful lesson: the owner deploys with
 * zero terminals and cannot read stack traces, so every failure must
 * diagnose ITSELF in plain English (and heal what can be healed).
 *
 * 1. ensureTables() — PARAMEDIC. If the cloud database is reachable but
 *    EMPTY (0 tables — sync-schema never ran, fresh Turso, whatever),
 *    create all 34 tables right now from the build-time DDL snapshot.
 *    Idempotent (IF NOT EXISTS everywhere) and only ever touches a
 *    database that has ZERO tables, so real data can never be harmed.
 *    Never throws — worst case it returns ok:false with the reason.
 *
 * 2. diagnoseDb() — DOCTOR. Returns one plain-English sentence naming
 *    the exact problem: env var missing, token missing, host unreachable,
 *    or "actually the database is fine, look at the runtime logs".
 *    Login/signup paste this straight into the error banner so the
 *    owner sees the cause on the very screen that failed.
 */
import { SCHEMA_DDL } from './generated-ddl'

type EnsureResult = { ok: boolean; tableCount: number; error?: string }

const globalForDbdiag = globalThis as unknown as {
  __rbEnsureTables?: Promise<EnsureResult>
}

export async function ensureTables(): Promise<EnsureResult> {
  const url = process.env.DATABASE_URL || ''
  // self-healing only applies to cloud databases — local file DBs are
  // managed by prisma db push / the sandbox, never touched from here
  if (!url.startsWith('libsql:')) {
    return { ok: false, tableCount: 0, error: 'not a cloud database URL' }
  }

  if (!globalForDbdiag.__rbEnsureTables) {
    globalForDbdiag.__rbEnsureTables = (async () => {
      try {
        const { createClient } = await import('@libsql/client')
        const fromUrl = url.match(/[?&]authToken=([^&]+)/)?.[1]
        const authToken =
          fromUrl || process.env.LIBSQL_AUTH_TOKEN || process.env.TURSO_AUTH_TOKEN
        const client = createClient({
          url,
          ...(authToken ? { authToken } : {}),
        })

        const before = await client.execute(
          "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
        )
        const tableCount = Number(before.rows[0]?.n ?? 0)
        if (tableCount > 0) {
          return { ok: true, tableCount }
        }

        // empty cloud database — heal it with the build-time DDL snapshot
        await client.executeMultiple(SCHEMA_DDL)
        const after = await client.execute(
          "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'"
        )
        const healed = Number(after.rows[0]?.n ?? 0)
        console.log(
          `[dbdiag] SELF-HEALED: cloud database was empty — created ${healed} tables at runtime.`
        )
        return { ok: true, tableCount: healed }
      } catch (e) {
        // do NOT cache the failure forever — let the next request retry
        globalForDbdiag.__rbEnsureTables = undefined
        const msg = e instanceof Error ? e.message : String(e)
        return { ok: false, tableCount: 0, error: msg }
      }
    })()
  }

  return globalForDbdiag.__rbEnsureTables
}

export async function diagnoseDb(): Promise<string> {
  const url = process.env.DATABASE_URL || ''

  if (!url) {
    return (
      'Reason found: DATABASE_URL is not set on this deployment. ' +
      'Vercel env vars are per-project — a project freshly connected to GitHub starts empty. ' +
      'Add DATABASE_URL (plus AUTH_SECRET, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET) under Settings → Environment Variables, then Redeploy.'
    )
  }

  if (!url.startsWith('libsql:')) {
    return (
      `Reason found: DATABASE_URL is not a cloud database URL (it starts with "${url.slice(0, 24)}…"). ` +
      'On Vercel it must be your Turso URL joined with its token, like libsql://your-host.turso.io?authToken=YOUR_TOKEN — one line, no quotes, no spaces.'
    )
  }

  const host = url.split('?')[0].replace(/^libsql:\/\//, '')
  const token =
    url.match(/[?&]authToken=([^&]+)/)?.[1] ||
    process.env.LIBSQL_AUTH_TOKEN ||
    process.env.TURSO_AUTH_TOKEN

  if (!token) {
    return (
      `Reason found: DATABASE_URL points at ${host} but the auth token is missing. ` +
      'Create a token in the Turso dashboard (your database → Tokens) and append it to the URL: ?authToken=YOUR_TOKEN — then Redeploy.'
    )
  }

  const r = await ensureTables()
  if (!r.ok) {
    return (
      `Reason found: the server cannot reach ${host} (${r.error}). ` +
      'Check the host spelling, create a fresh token in the Turso dashboard if the old one was revoked, and confirm the database still exists — then Redeploy.'
    )
  }
  if (r.tableCount === 0) {
    return (
      `Reason found: connected to ${host}, but it has 0 tables and healing failed. ` +
      'Make sure scripts/sync-schema.mjs and src/lib/generated-ddl.ts are in the GitHub repo, then Redeploy.'
    )
  }
  return (
    `Surprise: the database ${host} is connected and has ${r.tableCount} tables. ` +
    'The database is fine — open the Vercel dashboard → your deployment → Runtime Logs to see the real error, and tell Super Z what it says.'
  )
}
