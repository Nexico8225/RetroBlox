/** Restore the database from a backup: `npm run restore` (latest) or
 *  `npm run restore -- retro-2026-09-10T04-00-00` (specific).
 *  Overwrites db/custom.db with the chosen backup — run only in an emergency. */
import fs from 'fs'
import path from 'path'

function main() {
  const url = process.env.DATABASE_URL || 'file:/home/z/my-project/db/custom.db'
  const dbFile = url.replace(/^file:/, '')
  const backupDir = path.join(path.dirname(dbFile), 'backups')
  if (!fs.existsSync(backupDir)) {
    console.error('No backups directory at', backupDir)
    process.exit(1)
  }

  const wanted = process.argv[2] // optional: partial name like a timestamp
  const all = fs
    .readdirSync(backupDir)
    .filter((f) => f.startsWith('retro-') && f.endsWith('.db'))
    .sort()
  if (!all.length) {
    console.error('No backup files found.')
    process.exit(1)
  }

  const chosen = wanted ? all.find((f) => f.includes(wanted)) : all[all.length - 1]
  if (!chosen) {
    console.error('No backup matches:', wanted, '\nAvailable:', all.join('\n'))
    process.exit(1)
  }

  // safety: copy the current (possibly broken) db aside before overwriting
  if (fs.existsSync(dbFile)) {
    const broken = dbFile + '.before-restore'
    fs.copyFileSync(dbFile, broken)
    console.log('Current db preserved as:', broken)
  }

  fs.copyFileSync(path.join(backupDir, chosen), dbFile)
  console.log('RESTORED database from:', chosen)
}

main()
