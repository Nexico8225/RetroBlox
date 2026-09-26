/**
 * DATA PROTECTION — runs automatically on EVERY server boot (dev + production).
 *
 * Why this exists: the owner lost accounts/games/posts every time the site was
 * updated. From v10 on, updating the site must NEVER destroy player data.
 *
 * What this does, in order:
 *  1. If the database file is MISSING but a backup exists -> restore the newest
 *     backup automatically (data resurrection after a bad deploy).
 *  2. If the database exists -> save a timestamped safety backup (throttled to
 *     one per 30 minutes, keeps the newest 40) so there is always a recent
 *     snapshot to fall back on.
 *
 * It NEVER deletes user data. It only ever copies.
 *
 * NOTE: node builtins are fetched with process.getBuiltinModule (Node 22+)
 * instead of import statements so the Edge Runtime compile of this file never
 * sees (or warns about) node modules.
 */

const KEEP_BACKUPS = 40
const MIN_GAP_MS = 30 * 60 * 1000 // one auto-backup per 30 min, max

type Fs = typeof import('fs')
type Path = typeof import('path')

function nodeBuiltins(): { fs: Fs; path: Path } | null {
  try {
    const proc = process as unknown as {
      getBuiltinModule?: (id: string) => unknown
    }
    if (typeof proc.getBuiltinModule !== 'function') return null
    const fs = proc.getBuiltinModule('fs') as Fs | undefined
    const path = proc.getBuiltinModule('path') as Path | undefined
    if (!fs || !path) return null
    return { fs, path }
  } catch {
    return null
  }
}

function dbPaths(path: Path): { dbFile: string; backupDir: string } | null {
  const url = process.env.DATABASE_URL || 'file:/home/z/my-project/db/custom.db'
  if (!url.startsWith('file:')) return null
  let dbFile = url.slice('file:'.length)
  if (!path.isAbsolute(dbFile)) {
    // prisma resolves relative paths against the schema dir
    dbFile = path.join('/home/z/my-project/prisma', dbFile)
  }
  const backupDir = path.join(path.dirname(dbFile), 'backups')
  return { dbFile, backupDir }
}

function newestBackup(fs: Fs, backupDir: string): string | null {
  try {
    if (!fs.existsSync(backupDir)) return null
    const files = fs
      .readdirSync(backupDir)
      .filter((f) => f.startsWith('retro-') && f.endsWith('.db'))
      .map((f) => backupDir + '/' + f)
      .filter((f) => {
        try {
          return fs.statSync(f).size > 0
        } catch {
          return false
        }
      })
      .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)
    return files[0] || null
  } catch {
    return null
  }
}

function saveBackup(fs: Fs, dbFile: string, backupDir: string) {
  if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir, { recursive: true })

  // throttle: skip if the newest backup is fresh enough
  const latest = newestBackup(fs, backupDir)
  if (latest) {
    const age = Date.now() - fs.statSync(latest).mtimeMs
    if (age < MIN_GAP_MS) {
      console.log(`[retro-data] backup skipped (last one ${Math.round(age / 60000)} min ago)`)
      return
    }
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
  const dest = backupDir + '/retro-' + stamp + '.db'
  fs.copyFileSync(dbFile, dest)
  console.log(`[retro-data] safety backup saved: ${dest} (${Math.round(fs.statSync(dest).size / 1024)} KB)`)

  // prune: keep only the newest KEEP_BACKUPS
  const all = fs
    .readdirSync(backupDir)
    .filter((f) => f.startsWith('retro-') && f.endsWith('.db'))
    .sort()
  while (all.length > KEEP_BACKUPS) {
    const oldest = all.shift()
    if (oldest) {
      try {
        fs.unlinkSync(backupDir + '/' + oldest)
      } catch {
        /* ignore */
      }
    }
  }
}

export async function register() {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return
  try {
    const builtins = nodeBuiltins()
    if (!builtins) {
      console.log('[retro-data] node builtins unavailable here — boot backup skipped')
      return
    }
    const { fs, path } = builtins
    const p = dbPaths(path)
    if (!p) return
    const { dbFile, backupDir } = p

    if (!fs.existsSync(dbFile)) {
      const latest = newestBackup(fs, backupDir)
      if (latest) {
        fs.copyFileSync(latest, dbFile)
        console.log(`[retro-data] DATABASE WAS MISSING — restored from backup: ${latest}`)
      } else {
        console.log('[retro-data] no database and no backup yet — a fresh one will be created')
      }
      return
    }

    saveBackup(fs, dbFile, backupDir)
  } catch (err) {
    // never let data protection break the site booting
    console.error('[retro-data] protection step failed (site still boots):', err)
  }
}
