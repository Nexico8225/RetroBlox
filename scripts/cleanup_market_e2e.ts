/* Remove the market e2e test users + their items from the LOCAL dev DB.
 * Prisma cascade handles relations (inventory, listings, trades, notifications...). */
import { PrismaClient } from '@prisma/client'

const db = new PrismaClient()

async function main() {
  const patterns = ['mkt_e2e%', 't_dbg%', 'dbg%', 'mx_', 'm3_', 'e2x', 'd_%', 'probe', 'e2ea', 'e2eb', 'bt']
  const users = await db.user.findMany({
    where: { OR: patterns.map((p) => ({ username: { startsWith: p.replace('%', '') } })) },
    select: { id: true, username: true },
  })
  for (const u of users) {
    // their published UGC first (items whose creator is this user)
    const items = await db.avatarItem.findMany({ where: { creatorId: u.id }, select: { id: true, assetId: true } })
    for (const it of items) await db.avatarItem.delete({ where: { id: it.id } })
    await db.user.delete({ where: { id: u.id } })
    console.log('removed', u.username, `(${items.length} item(s))`)
  }
  console.log(`cleanup done — ${users.length} test user(s) removed`)
}

main().catch((e) => { console.error(e); process.exit(1) }).finally(() => db.$disconnect())
