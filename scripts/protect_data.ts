/** DATA PREFLIGHT — run before/after any update: `npm run protect`
 *
 *  1. Saves a fresh backup of the database.
 *  2. Prints a full inventory of player data (so you can SEE nothing was lost).
 *  3. Makes sure the admin account exists (creates it if missing).
 *
 *  This script NEVER deletes anything. Updates must be additive-only from v10 on.
 */
import fs from 'fs'
import path from 'path'
import { randomBytes, scryptSync } from 'crypto'
import { PrismaClient } from '@prisma/client'

const db = new PrismaClient()
const ADMIN = { username: 'Nexico8225', password: 'Nexico.2014' }

// mirrors src/lib/auth.ts exactly (salt:hash, scrypt 64)
function hashPassword(password: string): string {
  const salt = randomBytes(16).toString('hex')
  const hash = scryptSync(password, salt, 64).toString('hex')
  return `${salt}:${hash}`
}

async function main() {
  const url = process.env.DATABASE_URL || 'file:/home/z/my-project/db/custom.db'
  const dbFile = url.replace(/^file:/, '')

  // 1. backup first
  if (fs.existsSync(dbFile)) {
    const backupDir = path.join(path.dirname(dbFile), 'backups')
    if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir, { recursive: true })
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
    const dest = path.join(backupDir, `retro-${stamp}.db`)
    fs.copyFileSync(dbFile, dest)
    console.log('[protect] backup saved:', dest)
  }

  // 2. inventory
  const users = await db.user.findMany({ select: { username: true, role: true } })
  console.log('\n===== RETROBLOX DATA INVENTORY =====')
  console.log(`accounts      : ${users.length}${users.length ? ' -> ' + users.map((u) => u.username).join(', ') : ''}`)
  console.log(`games         : ${await db.game.count()}`)
  console.log(`videos        : ${await db.video.count()}`)
  console.log(`community posts: ${await db.communityPost.count()}`)
  console.log(`labs posts    : ${await db.labPost.count()}`)
  console.log(`subs          : ${await db.sub.count()}`)
  console.log(`groups        : ${await db.group.count()}`)
  console.log(`chats         : ${await db.chatMessage.count()}`)
  console.log(`friendships   : ${await db.friendship.count()}`)
  console.log(`follows       : ${await db.follow.count()}`)
  console.log('====================================\n')

  // 3. ensure the admin exists (create-only, never delete)
  const admin = await db.user.findFirst({ where: { usernameLower: ADMIN.username.toLowerCase() } })
  if (!admin) {
    const passwordHash = hashPassword(ADMIN.password)
    await db.user.create({
      data: {
        username: ADMIN.username,
        usernameLower: ADMIN.username.toLowerCase(),
        passwordHash,
        role: 'admin',
        bio: 'RetroBlox admin.',
      },
    })
    console.log('[protect] admin account was missing — recreated:', ADMIN.username)
  } else {
    console.log('[protect] admin account OK:', admin.username)
  }

  await db.$disconnect()
}

main().catch((e) => {
  console.error('[protect] failed:', e)
  process.exit(1)
})
