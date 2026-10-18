/** Manual safety backup: `npm run backup`
 *  Saves db/custom.db -> db/backups/retro-<timestamp>.db (keeps newest 40).
 *  NEVER deletes user data — only copies. */
import fs from 'fs'
import path from 'path'

const KEEP = 40

function main() {
  const url = process.env.DATABASE_URL || 'file:/home/z/my-project/db/custom.db'
  const dbFile = url.replace(/^file:/, '')
  if (!fs.existsSync(dbFile)) {
    console.error('No database found at', dbFile)
    process.exit(1)
  }
  const backupDir = path.join(path.dirname(dbFile), 'backups')
  if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir, { recursive: true })

  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
  const dest = path.join(backupDir, `retro-${stamp}.db`)
  fs.copyFileSync(dbFile, dest)
  console.log('Backup saved:', dest, `(${Math.round(fs.statSync(dest).size / 1024)} KB)`)

  const all = fs.readdirSync(backupDir).filter((f) => f.startsWith('retro-') && f.endsWith('.db')).sort()
  while (all.length > KEEP) {
    const old = all.shift()
    if (old) fs.unlinkSync(path.join(backupDir, old))
  }
  console.log(`Backups kept: ${Math.min(all.length, KEEP)}/${KEEP}`)
}

main()
