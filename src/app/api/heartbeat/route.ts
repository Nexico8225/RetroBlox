import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ ok: false }, { status: 401 })
  await db.user.update({ where: { id: user.id }, data: { lastSeen: new Date() } })
  return NextResponse.json({ ok: true })
}
