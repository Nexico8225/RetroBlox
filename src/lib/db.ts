import { PrismaClient } from '@prisma/client'
import fs from 'fs'
import path from 'path'
import { PrismaLibSQL } from '@prisma/adapter-libsql'

/**
 * RUNTIME DATABASE RESOLUTION — three modes, picked per deployment:
 *
 *  1. REMOTE (libsql:) — DATABASE_URL starts with libsql:// → Turso/libSQL.
 *     The database lives in the cloud and WRITES WORK on serverless hosts.
 *     (Vercel/Netlify lambdas have read-only disks: the bundled SQLite file
 *     could be read but never written — that is what broke the wallet
 *     credit, signups and uploads there.) The auth token comes from
 *     LIBSQL_AUTH_TOKEN (or TURSO_AUTH_TOKEN).
 *  2. LOCAL FILE (file:) — DATABASE_URL points at a file that exists → use
 *     it (sandbox dev, self-hosted boxes, `npm start` on a normal host).
 *  3. PROBE — no usable DATABASE_URL → probe well-known paths relative to
 *     process.cwd(), which covers serverless bundles that ship
 *     db/custom.db via outputFileTracingIncludes. Reads work there; writes
 *     depend on the host filesystem.
 */
function resolveDatasourceUrl(): string {
  const env = process.env.DATABASE_URL

  // future remote providers (postgres:// etc.) — pass through untouched
  if (env && !env.startsWith('file:') && !env.startsWith('libsql:')) return env

  if (env && env.startsWith('file:')) {
    const raw = env.replace(/^file:/, '')
    const abs = path.isAbsolute(raw) ? raw : path.resolve(process.cwd(), raw)
    if (fs.existsSync(abs)) return env
  }

  const cwd = process.cwd()
  const candidates = [
    path.join(cwd, 'db', 'custom.db'), // project root / traced lambda bundle
    path.join(cwd, '..', 'db', 'custom.db'), // nested function dirs
    path.join(cwd, 'custom.db'), // last resort: cwd IS the db dir
  ]
  const found = candidates.find((c) => fs.existsSync(c))
  return 'file:' + (found ?? path.join(cwd, 'db', 'custom.db'))
}

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

function createClient(): PrismaClient {
  // REMOTE Turso/libSQL — adapter mode (writes work everywhere).
  if (process.env.DATABASE_URL?.startsWith('libsql:')) {
    const url = process.env.DATABASE_URL
    // The token can live INSIDE the URL (?authToken=... — the one-line
    // format the Turso dashboard hands you) or in separate env vars.
    // Reading it out of the URL and passing it explicitly works for both.
    const fromUrl = url.match(/[?&]authToken=([^&]+)/)?.[1]
    const authToken =
      fromUrl || process.env.LIBSQL_AUTH_TOKEN || process.env.TURSO_AUTH_TOKEN
    const adapter = new PrismaLibSQL({
      url,
      ...(authToken ? { authToken } : {}),
    })
    return new PrismaClient({ log: ['error'], adapter })
  }

  // LOCAL FILE — bundled / dev / self-hosted SQLite.
  return new PrismaClient({
    log: ['error'],
    datasourceUrl: resolveDatasourceUrl(),
  })
}

export const db = globalForPrisma.prisma ?? createClient()

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = db
