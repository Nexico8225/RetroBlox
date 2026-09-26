import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

// GET /api/videos/[id]/comments — newest last
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const comments = await db.videoComment.findMany({
    where: { videoId: id },
    include: { author: { select: { id: true, username: true, avatarUrl: true, lastSeen: true, role: true } } },
    orderBy: { createdAt: 'asc' },
    take: 200,
  })
  return NextResponse.json({
    comments: comments.map((c) => ({ ...c, author: publicUser(c.author) })),
  })
}

// POST /api/videos/[id]/comments — text + optional image/video/audio attachment
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const video = await db.video.findUnique({ where: { id }, select: { id: true } })
  if (!video) return NextResponse.json({ error: 'Video not found' }, { status: 404 })

  const form = await req.formData()
  const text = String(form.get('text') || '').trim()
  if (!text || text.length > 500) {
    return NextResponse.json({ error: 'Comment must be 1-500 characters.' }, { status: 400 })
  }

  // optional reply-to: replies always attach to a TOP-LEVEL comment (if the
  // parent is itself a reply, we thread under its parent instead) — one
  // level deep, always readable
  const parentRaw = form.get('parentId')
  let parentId: string | null = null
  if (typeof parentRaw === 'string' && parentRaw) {
    const parent = await db.videoComment.findUnique({
      where: { id: parentRaw },
      select: { id: true, videoId: true, parentId: true },
    })
    if (!parent || parent.videoId !== id) {
      return NextResponse.json({ error: 'The comment you replied to is gone.' }, { status: 400 })
    }
    parentId = parent.parentId || parent.id
  }

  let mediaFileId: string | null = null
  let mediaType: string | null = null
  let mediaName: string | null = null
  const file = form.get('file')
  if (file instanceof File && file.size > 0) {
    const isImage = file.type.startsWith('image/')
    const isVideo = file.type.startsWith('video/')
    const isAudio = file.type.startsWith('audio/')
    if (!isImage && !isVideo && !isAudio) {
      return NextResponse.json({ error: 'Comments can hold images, videos or audio.' }, { status: 400 })
    }
    const maxMB = isVideo ? 40 : isAudio ? 15 : 8
    if (file.size > maxMB * 1024 * 1024) {
      return NextResponse.json({ error: `Attachment too large (max ${maxMB}MB).` }, { status: 400 })
    }
    const saved = await saveUpload(file, user.id)
    mediaFileId = saved.id
    mediaType = isImage ? 'image' : isVideo ? 'video' : 'audio'
    mediaName = file.name
  }

  const comment = await db.videoComment.create({
    data: { text, videoId: id, authorId: user.id, mediaFileId, mediaType, mediaName, parentId },
    include: { author: { select: { id: true, username: true, avatarUrl: true, lastSeen: true, role: true } } },
  })

  return NextResponse.json({ comment: { ...comment, author: publicUser(comment.author) } })
}
