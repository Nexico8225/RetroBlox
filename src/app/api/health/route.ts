import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export const dynamic = 'force-dynamic'

/* ------------------------------------------------------------------
   /api/health — the ZERO-TERMINAL doctor.
   Open this page in your browser on the deployed site and it tells
   you, in plain English, exactly what is (or isn't) set up:
   database connected? tables created? any users registered? which
   env vars are present? No logs, no terminal, no guessing.

   Secrets are NEVER printed — only booleans and masked hosts.
------------------------------------------------------------------ */

type Check = {
  label: string
  ok: boolean
  detail: string
  tip?: string
}

function maskDbUrl(raw: string): string {
  // libsql://host/db?authToken=SECRET  ->  libsql://host/db (token hidden)
  try {
    return raw.replace(/([?&])authToken=[^&]+/g, '$1authToken=***')
  } catch {
    return '(unparseable)'
  }
}

async function mainChecks(): Promise<Check[]> {
  const checks: Check[] = []
  const raw = process.env.DATABASE_URL || ''
  const mode = raw.startsWith('libsql:')
    ? 'libsql (Turso cloud)'
    : raw.startsWith('file:')
      ? 'file (local SQLite)'
      : raw
        ? 'unknown'
        : 'MISSING'

  // ---- 1. DATABASE_URL present? -------------------------------------
  checks.push({
    label: 'DATABASE_URL',
    ok: Boolean(raw),
    detail: raw ? `${mode} — ${maskDbUrl(raw)}` : 'Not set at all!',
    tip: raw
      ? undefined
      : 'Add DATABASE_URL on Vercel: Settings → Environment Variables. Format: libsql://your-db-user.turso.io?authToken=YOUR_TOKEN',
  })

  // ---- 2. auth token available? -------------------------------------
  const tokenInUrl = /[?&]authToken=[^&]+/.test(raw)
  const tokenStandalone = Boolean(process.env.LIBSQL_AUTH_TOKEN || process.env.TURSO_AUTH_TOKEN)
  if (raw.startsWith('libsql:')) {
    checks.push({
      label: 'Database auth token',
      ok: tokenInUrl || tokenStandalone,
      detail: tokenInUrl
        ? 'Found inside DATABASE_URL (?authToken=…).'
        : tokenStandalone
          ? 'Found in LIBSQL_AUTH_TOKEN / TURSO_AUTH_TOKEN.'
          : 'No token anywhere!',
      tip:
        tokenInUrl || tokenStandalone
          ? undefined
          : 'Append ?authToken=YOUR_TOKEN to the DATABASE_URL value (or add LIBSQL_AUTH_TOKEN).',
    })
  }

  // ---- 3. can we actually talk to the database? ---------------------
  let tables = -1
  let users = -1
  let dbError = ''
  try {
    const rows = (await db.$queryRawUnsafe(
      "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table'"
    )) as Array<{ n: number | bigint }>
    tables = Number(rows?.[0]?.n ?? -1)
  } catch (e) {
    dbError = e instanceof Error ? e.message : String(e)
  }
  if (tables >= 0) {
    try {
      users = await db.user.count()
    } catch (e) {
      dbError = e instanceof Error ? e.message : String(e)
    }
  }

  const connected = tables >= 0 && users >= 0
  checks.push({
    label: 'Database connection',
    ok: connected,
    detail: connected
      ? `Connected! ${tables} tables found, ${users} user${users === 1 ? '' : 's'} registered.`
      : `FAILED — ${dbError.slice(0, 220)}`,
    tip: connected
      ? undefined
      : tables === 0
        ? 'The database is reachable but EMPTY (0 tables). Your build did not run scripts/sync-schema.mjs — make sure package.json build script and scripts/sync-schema.mjs exist on GitHub, then redeploy.'
        : 'Check the DATABASE_URL value and the auth token (a trailing space, quotes, or a truncated token all break it). Then redeploy.',
  })

  if (connected && users === 0) {
    checks.push({
      label: 'Owner account',
      ok: false,
      detail: 'The database has 0 users — nobody has signed up yet.',
      tip: 'Sign up on the site NOW: the FIRST account on a fresh database automatically becomes the owner-admin.',
    })
  }

  // ---- 4. AUTH_SECRET ----------------------------------------------
  const secret = process.env.AUTH_SECRET || ''
  checks.push({
    label: 'AUTH_SECRET',
    ok: Boolean(secret),
    detail: secret
      ? `Set (${secret.length} chars — value hidden).`
      : 'Not set — sessions use a built-in fallback (works, but weaker).',
    tip: secret ? undefined : 'Add AUTH_SECRET (any long random text) and redeploy.',
  })

  // ---- 5. Stripe ----------------------------------------------------
  const mode2 = (process.env.PAYMENTS_MODE || 'test').toLowerCase() === 'live' ? 'live' : 'test'
  const sk =
    mode2 === 'live' ? Boolean(process.env.STRIPE_LIVE_SECRET_KEY) : Boolean(process.env.STRIPE_SECRET_KEY)
  const wh =
    mode2 === 'live'
      ? Boolean(process.env.STRIPE_LIVE_WEBHOOK_SECRET)
      : Boolean(process.env.STRIPE_WEBHOOK_SECRET)
  checks.push({
    label: `Stripe (${mode2} mode)`,
    ok: sk,
    detail: sk
      ? wh
        ? 'Secret key + webhook secret both set (values hidden).'
        : 'Secret key set, WEBHOOK secret missing — real payments would charge but never credit Tix!'
      : 'No secret key — the Test Bank pretends purchases instead.',
    tip: wh ? undefined : 'Add STRIPE_WEBHOOK_SECRET from your Stripe webhook endpoint, then redeploy.',
  })

  return checks
}

export async function GET(req: NextRequest) {
  const checks = await mainChecks()
  const allOk = checks.every((c) => c.ok)

  // browsed directly in a browser? render a friendly card instead of JSON
  const wantsHtml = (req.headers.get('accept') || '').includes('text/html')
  if (!wantsHtml) {
    return NextResponse.json({ ok: allOk, checks })
  }

  const rows = checks
    .map(
      (c) => `
      <div style="border:1.5px solid ${c.ok ? '#b9d8a0' : '#e2a7a0'};border-left:6px solid ${c.ok ? '#4d9b2b' : '#e2231a'};border-radius:10px;padding:14px 16px;margin:10px 0;background:${c.ok ? '#f4faf0' : '#fdf3f2'}">
        <div style="font-size:16px;color:#33291a;"><span style="font-size:18px">${c.ok ? 'OK' : 'PROBLEM'}</span> &nbsp;${c.label}</div>
        <div style="font-size:14px;color:#5c4f3a;margin-top:4px;">${c.detail.replace(/</g, '&lt;')}</div>
        ${c.tip ? `<div style="font-size:14px;color:#7a5a12;margin-top:6px;">Fix: ${c.tip.replace(/</g, '&lt;')}</div>` : ''}
      </div>`
    )
    .join('')

  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>RetroBlox Health Check</title></head>
  <body style="margin:0;background:#f6efdc;font-family:Verdana,Tahoma,sans-serif;padding:24px 14px;">
    <div style="max-width:640px;margin:0 auto;">
      <div style="font-size:24px;color:#33291a;margin-bottom:2px;">RetroBlox Health Check</div>
      <div style="font-size:15px;color:${allOk ? '#337616' : '#b3160f'};margin-bottom:14px;">${
        allOk ? 'Everything looks good — the site is healthy!' : 'Some things need attention below.'
      }</div>
      ${rows}
      <div style="font-size:12px;color:#8b7a5f;margin-top:10px;">After fixing anything on Vercel: Settings change → Deployments → Redeploy, then refresh this page.</div>
    </div>
  </body></html>`
  return new NextResponse(html, { headers: { 'content-type': 'text/html; charset=utf-8' } })
}
