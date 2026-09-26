import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

// GET /api/groups — the group directory
export async function GET() {
  const groups = await db.group.findMany({
    include: {
      owner: { select: { id: true, username: true, avatarUrl: true } },
      _count: { select: { members: true, games: true } },
    },
    orderBy: { createdAt: 'desc' },
  })
  return NextResponse.json({
    groups: groups.map((g) => ({
      id: g.id,
      name: g.name,
      description: g.description,
      iconUrl: g.iconUrl,
      owner: g.owner,
      memberCount: g._count.members,
      gameCount: g._count.games,
      createdAt: g.createdAt,
    })),
  })
}

// POST /api/groups — create a group (you become the owner)
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const name = String(form.get('name') || '').trim()
  const description = String(form.get('description') || '').trim().slice(0, 1000)
  const icon = form.get('icon')

  if (name.length < 3 || name.length > 40) {
    return NextResponse.json({ error: 'Group name must be 3-40 characters.' }, { status: 400 })
  }

  const taken = await db.group.findFirst({ where: { name } })
  if (taken) return NextResponse.json({ error: 'A group with that name already exists!' }, { status: 409 })

  let iconUrl: string | null = null
  if (icon instanceof File && icon.size > 0) {
    if (icon.size > 2 * 1024 * 1024) return NextResponse.json({ error: 'Icon too large (max 2MB).' }, { status: 400 })
    const buf = Buffer.from(await icon.arrayBuffer())
    iconUrl = `data:${icon.type || 'image/png'};base64,${buf.toString('base64')}`
  }

  const group = await db.group.create({
    data: {
      name,
      description,
      iconUrl,
      ownerId: user.id,
      members: { create: { userId: user.id, role: 'owner' } },
    },
  })

  return NextResponse.json({ group: { id: group.id, name: group.name } })
}
