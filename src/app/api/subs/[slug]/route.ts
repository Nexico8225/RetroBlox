import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { parseIds } from '@/lib/stats'

// shared shape (kept in sync with /api/subs)
function shapeSub(
  s: {
    id: string
    slug: string
    name: string
    description: string
    iconFileId: string | null
    bannerFileId: string | null
    color: string
    memberIds: string
    creator: { id: string; username: string; avatarUrl: string | null; role: string }
    createdAt: Date
    _count?: { postIds: number }
  },
  meId?: string | null
) {
  const memberIds = parseIds(s.memberIds)
  return {
    id: s.id,
    slug: s.slug,
    name: s.name,
    description: s.description,
    iconFileId: s.iconFileId,
    bannerFileId: s.bannerFileId,
    color: s.color,
    members: memberIds.length,
    posts: s._count?.postIds ?? 0,
    creator: s.creator,
    createdAt: s.createdAt,
    joined: meId ? memberIds.includes(meId) : false,
  }
}

async function findSub(slug: string) {
  return db.sub.findUnique({
    where: { slug: slug.toLowerCase() },
    include: {
      creator: { select: { id: true, username: true, avatarUrl: true, role: true } },
      _count: { select: { postIds: true } },
    },
  })
}

// GET /api/subs/[slug] — community detail
export async function GET(req: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params
  const me = await getUserFromReq(req)
  const sub = await findSub(slug)
  if (!sub) return NextResponse.json({ error: 'Community not found' }, { status: 404 })
  return NextResponse.json({ sub: shapeSub(sub, me?.id) })
}

// PATCH /api/subs/[slug] — join / leave (toggle)
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const sub = await db.sub.findUnique({ where: { slug: slug.toLowerCase() } })
  if (!sub) return NextResponse.json({ error: 'Community not found' }, { status: 404 })

  const memberIds = parseIds(sub.memberIds)
  const joined = memberIds.includes(user.id)
  const next = joined ? memberIds.filter((id) => id !== user.id) : [...memberIds, user.id]

  await db.sub.update({ where: { id: sub.id }, data: { memberIds: JSON.stringify(next) } })
  return NextResponse.json({ joined: !joined, members: next.length })
}

// DELETE /api/subs/[slug] — creator or admin only
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const sub = await db.sub.findUnique({ where: { slug: slug.toLowerCase() } })
  if (!sub) return NextResponse.json({ error: 'Community not found' }, { status: 404 })
  if (sub.creatorId !== user.id && user.role !== 'admin') {
    return NextResponse.json({ error: 'Only the creator (or an admin) can delete this community.' }, { status: 403 })
  }

  await db.sub.delete({ where: { id: sub.id } })
  return NextResponse.json({ ok: true })
}
