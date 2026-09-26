import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { shapeVideo } from '@/lib/videos'

// GET /api/videos/[id] — watch page payload: video + related videos
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)

  const video = await db.video.findUnique({
    where: { id },
    include: {
      author: { select: { id: true, username: true, avatarUrl: true, lastSeen: true, createdAt: true } },
      _count: { select: { comments: true } },
    },
  })
  if (!video) return NextResponse.json({ error: 'Video not found' }, { status: 404 })

  const related = await db.video.findMany({
    where: { id: { not: id } },
    include: {
      author: { select: { id: true, username: true, avatarUrl: true, lastSeen: true } },
      _count: { select: { comments: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 12,
  })

  return NextResponse.json({
    video: shapeVideo(video, me?.id),
    authorJoined: video.author.createdAt,
    isOwner: me?.id === video.authorId,
    isAdmin: me?.role === 'admin',
    related: related.map((v) => shapeVideo(v, me?.id)),
  })
}

// PATCH /api/videos/[id] — { vote: 1 | -1 | 0 } YouTube-style like/dislike toggle
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const video = await db.video.findUnique({ where: { id } })
  if (!video) return NextResponse.json({ error: 'Video not found' }, { status: 404 })

  const body = await req.json().catch(() => ({}))
  const vote = Number(body.vote)
  if (![1, -1, 0].includes(vote)) {
    return NextResponse.json({ error: 'vote must be 1, -1 or 0' }, { status: 400 })
  }

  const ups = JSON.parse(video.upIds || '[]') as string[]
  const downs = JSON.parse(video.downIds || '[]') as string[]
  const up = ups.includes(me.id)
  const down = downs.includes(me.id)

  let nextUps = ups
  let nextDowns = downs
  if (vote === 1) {
    nextUps = up ? ups.filter((x) => x !== me.id) : [...ups, me.id]
    nextDowns = downs.filter((x) => x !== me.id)
  } else if (vote === -1) {
    nextDowns = down ? downs.filter((x) => x !== me.id) : [...downs, me.id]
    nextUps = ups.filter((x) => x !== me.id)
  } else {
    nextUps = ups.filter((x) => x !== me.id)
    nextDowns = downs.filter((x) => x !== me.id)
  }

  await db.video.update({
    where: { id },
    data: { upIds: JSON.stringify(nextUps), downIds: JSON.stringify(nextDowns) },
  })

  return NextResponse.json({
    likes: nextUps.length,
    dislikes: nextDowns.length,
    myVote: vote === 1 ? (up ? 0 : 1) : vote === -1 ? (down ? 0 : -1) : 0,
  })
}

// DELETE /api/videos/[id] — author or admin
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const video = await db.video.findUnique({ where: { id } })
  if (!video) return NextResponse.json({ error: 'Video not found' }, { status: 404 })
  if (video.authorId !== me.id && me.role !== 'admin') {
    return NextResponse.json({ error: 'You can only delete your own videos.' }, { status: 403 })
  }

  await db.video.delete({ where: { id } })
  return NextResponse.json({ ok: true })
}
