import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

const SLUG_RE = /^[A-Za-z0-9][A-Za-z0-9_]{2,20}$/

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
  let memberIds: string[] = []
  try { memberIds = JSON.parse(s.memberIds || '[]') } catch { /* ignore */ }
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

// GET /api/subs — every player-created r/ community
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  const subs = await db.sub.findMany({
    include: {
      creator: { select: { id: true, username: true, avatarUrl: true, role: true } },
      _count: { select: { postIds: true } },
    },
    orderBy: { createdAt: 'desc' },
  })
  return NextResponse.json({ subs: subs.map((s) => shapeSub(s, me?.id)) })
}

// POST /api/subs — create your own r/ community (multipart: slug, name, description, icon, banner, color)
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const slugRaw = String(form.get('slug') || '').trim()
  const slug = slugRaw.toLowerCase()
  const name = String(form.get('name') || '').trim() || slugRaw
  const description = String(form.get('description') || '').trim().slice(0, 500)
  const color = String(form.get('color') || '').trim()

  if (!SLUG_RE.test(slug)) {
    return NextResponse.json(
      { error: 'Community names are 3-21 characters: letters, numbers, underscore (no spaces).' },
      { status: 400 }
    )
  }
  if (name.length > 40) {
    return NextResponse.json({ error: 'Display name is too long (max 40).' }, { status: 400 })
  }

  // reserved names that already exist as default r/ lounge categories
  const RESERVED = ['all', 'general', 'memes', 'help', 'finds', 'offtopic', 'videos', 'retrolabs', 'announcements', 'admin']
  if (RESERVED.includes(slug)) {
    return NextResponse.json({ error: `r/${slug} already exists — pick another name.` }, { status: 409 })
  }

  const existing = await db.sub.findUnique({ where: { slug } })
  if (existing) {
    return NextResponse.json({ error: `r/${slug} already exists — pick another name.` }, { status: 409 })
  }

  let iconFileId: string | null = null
  const icon = form.get('icon')
  if (icon instanceof File && icon.size > 0) {
    if (!icon.type.startsWith('image/')) {
      return NextResponse.json({ error: 'Icon must be an image.' }, { status: 400 })
    }
    if (icon.size > 2 * 1024 * 1024) {
      return NextResponse.json({ error: 'Icon too large (max 2MB).' }, { status: 400 })
    }
    const saved = await saveUpload(icon, user.id)
    iconFileId = saved.id
  }

  let bannerFileId: string | null = null
  const banner = form.get('banner')
  if (banner instanceof File && banner.size > 0) {
    if (!banner.type.startsWith('image/')) {
      return NextResponse.json({ error: 'Banner must be an image.' }, { status: 400 })
    }
    if (banner.size > 6 * 1024 * 1024) {
      return NextResponse.json({ error: 'Banner too large (max 6MB).' }, { status: 400 })
    }
    const saved = await saveUpload(banner, user.id)
    bannerFileId = saved.id
  }

  const sub = await db.sub.create({
    data: {
      slug,
      name,
      description,
      iconFileId,
      bannerFileId,
      color: /^#[0-9a-fA-F]{6}$/.test(color) ? color : '#0d69ac',
      memberIds: JSON.stringify([user.id]), // creator joins automatically
      creatorId: user.id,
    },
  })

  return NextResponse.json({ sub: { id: sub.id, slug: sub.slug, name: sub.name } })
}
