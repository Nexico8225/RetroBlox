/* Creates / refreshes the RetroBlox administrator account:
   username: Nexico8225   password: Nexico.2014   role: admin
   Safe to re-run (upsert). */
import { PrismaClient } from '@prisma/client'
import { hashPassword } from '../src/lib/auth'

const db = new PrismaClient()

async function main() {
  const passwordHash = hashPassword('Nexico.2014')
  const admin = await db.user.upsert({
    where: { username: 'Nexico8225' },
    update: { passwordHash, role: 'admin', bio: 'RetroBlox Administrator. Keep it fun, keep it friendly — report broken games and I will take a look!' },
    create: {
      username: 'Nexico8225',
      passwordHash,
      role: 'admin',
      gender: 'male',
      bio: 'RetroBlox Administrator. Keep it fun, keep it friendly — report broken games and I will take a look!',
    },
  })
  console.log('Admin ready:', admin.username, 'role =', admin.role, 'id =', admin.id)

  // make sure every other account stays a normal user
  await db.user.updateMany({ where: { role: 'admin', id: { not: admin.id } }, data: { role: 'user' } })
}

main()
  .catch((e) => {
    console.error(e)
    process.exit(1)
  })
  .finally(() => db.$disconnect())
