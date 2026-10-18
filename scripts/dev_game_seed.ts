/**
 * LOCAL E2E seed for the web-synced Godot player probe.
 * Creates two LOCAL test accounts (localhost dev DB ONLY — never production)
 * and makes sure the baseplate place exists. Usage:
 *   npx tsx scripts/dev_game_seed.ts
 */
import { randomBytes, scryptSync } from 'crypto'
import { createClient } from '@libsql/client'
import { readFileSync } from 'node:fs'

const DB = process.env.LOCAL_DB || 'file:/home/z/my-project/db/custom.db'

function hashPassword(password: string): string {
  const salt = randomBytes(16).toString('hex')
  const hash = scryptSync(password, salt, 64).toString('hex')
  return `${salt}:${hash}`
}

const map = JSON.parse(readFileSync('/home/z/my-project/src/lib/baseplate-map.json', 'utf8'))

async function main() {
  const db = createClient({ url: DB })

  // ---- baseplate place ----
  const existing = await db.execute({
    sql: 'SELECT id FROM Place WHERE slug = ?',
    args: ['baseplate'],
  })
  if (existing.rows.length === 0) {
    await db.execute({
      sql: `INSERT INTO Place (id, slug, name, description, dataJson, maxPlayers, sortOrder, active, createdAt, updatedAt)
            VALUES (substr(lower(hex(randomblob(16))),1,24), 'baseplate', 'Baseplate', 'The classic brick world.', ?, 12, 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      args: [JSON.stringify(map)],
    })
    console.log('seeded baseplate place')
  } else {
    await db.execute({
      sql: 'UPDATE Place SET dataJson = ? WHERE slug = ?',
      args: [JSON.stringify(map), 'baseplate'],
    })
    console.log('baseplate place refreshed')
  }

  // ---- two local probe accounts ----
  for (const name of ['gameprobe1', 'gameprobe2']) {
    const found = await db.execute({
      sql: 'SELECT id FROM User WHERE username = ?',
      args: [name],
    })
    if (found.rows.length === 0) {
      await db.execute({
        sql: `INSERT INTO User (id, username, usernameLower, passwordHash, role, bio, createdAt, lastSeen)
              VALUES (substr(lower(hex(randomblob(16))),1,24), ?, ?, ?, 'user', '', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
        args: [name, name.toLowerCase(), hashPassword('probe123')],
      })
      console.log(`created local account ${name}`)
    } else {
      console.log(`account ${name} exists`)
    }
  }
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err)
  process.exit(1)
})
