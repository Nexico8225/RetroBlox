import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'
import { shapeVideo } from '@/lib/videos'

// GET /api/videos?sort=new|viewed|liked&q=...&authorId=...&limit=..
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  const { searchParams } = new URL(req.url)
  const sort = searchParams.get('sort') || 'new'
  const q = (searchParams.get('q') || '').trim()
  const authorId = searchParams.get('authorId') || ''
  const limit = Math.min(Number(searchParams.get('limit') || 40), 100)

  const videos = await db.video.findMany({
    where: {
      ...(q ? { OR: [{ title: { contains: q } }, { description: { contains: q } }] } : {}),
      ...(authorId ? { authorId } : {}),
    },
    include: {
      author: { select: { id: true, username: true, avatarUrl: true, lastSeen: true } },
      _count: { select: { comments: true } },
    },
    orderBy: sort === 'viewed' ? { views: 'desc' } : { createdAt: 'desc' },
    take: limit,
  })

  let shaped = videos.map((v) => shapeVideo(v, me?.id))
  if (sort === 'liked') {
    shaped = shaped.sort((a, b) => b.likes - a.likes || new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
  }

  return NextResponse.json({ videos: shaped })
}

// POST /api/videos — multipart: video file + title + description + optional thumbnail
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const title = String(form.get('title') || '').trim()
  const description = String(form.get('description') || '').trim()
  const video = form.get('video')

  if (!title || title.length > 100) {
    return NextResponse.json({ error: 'Give your video a title (1-100 characters).' }, { status: 400 })
  }
  if (description.length > 2000) {
    return NextResponse.json({ error: 'Description is too long (max 2000 characters).' }, { status: 400 })
  }
  if (!(video instanceof File) || video.size === 0) {
    return NextResponse.json({ error: 'Pick a video file to upload.' }, { status: 400 })
  }
  if (!video.type.startsWith('video/')) {
    return NextResponse.json({ error: 'That file is not a video. MP4 / WebM / MOV work best.' }, { status: 400 })
  }
  const MAX_VIDEO = 200 * 1024 * 1024
  if (video.size > MAX_VIDEO) {
    return NextResponse.json({ error: 'Video too large (max 200MB).' }, { status: 400 })
  }

  const saved = await saveUpload(video, user.id)

  let thumbFileId: string | null = null
  const thumb = form.get('thumb')
  if (thumb instanceof File && thumb.size > 0) {
    if (!thumb.type.startsWith('image/')) {
      return NextResponse.json({ error: 'Thumbnail must be an image.' }, { status: 400 })
    }
    if (thumb.size > 8 * 1024 * 1024) {
      return NextResponse.json({ error: 'Thumbnail too large (max 8MB).' }, { status: 400 })
    }
    const savedThumb = await saveUpload(thumb, user.id)
    thumbFileId = savedThumb.id
  }

  const created = await db.video.create({
    data: {
      title,
      description,
      fileId: saved.id,
      fileName: video.name,
      thumbFileId,
      authorId: user.id,
    },
  })

  return NextResponse.json({ video: { id: created.id } })
}
