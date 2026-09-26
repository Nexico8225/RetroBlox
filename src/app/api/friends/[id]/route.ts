import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'

// POST { action: "accept" | "decline" | "remove" | "cancel" }
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const friendship = await db.friendship.findUnique({ where: { id } })
  if (!friendship) return NextResponse.json({ error: 'Friendship not found' }, { status: 404 })
  if (friendship.requesterId !== me.id && friendship.addresseeId !== me.id) {
    return NextResponse.json({ error: 'Not your friendship' }, { status: 403 })
  }

  const body = await req.json()
  const action = String(body.action || '')

  if (action === 'accept') {
    if (friendship.addresseeId !== me.id) {
      return NextResponse.json({ error: 'Only the recipient can accept' }, { status: 403 })
    }
    await db.friendship.update({ where: { id }, data: { status: 'accepted' } })
    return NextResponse.json({ ok: true })
  }

  if (action === 'decline' || action === 'remove' || action === 'cancel') {
    await db.friendship.delete({ where: { id } })
    return NextResponse.json({ ok: true })
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
