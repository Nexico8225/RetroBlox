import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

export const LAB_BOARDS = ['Tutorials', 'Source Code', 'Showcase', 'Help'] as const

// GET /api/labs?board=Tutorials&q=search&limit=50 — topic list
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const board = searchParams.get('board') || ''
  const q = (searchParams.get('q') || '').trim().toLowerCase()
  const limit = Math.min(parseInt(searchParams.get('limit') || '50'), 100)

  const posts = await db.labPost.findMany({
    where: board ? { board } : undefined,
    include: {
      author: { select: { id: true, username: true, avatarUrl: true, role: true } },
      _count: { select: { replies: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })

  // case-insensitive search over title + body + author (SQLite contains is case-sensitive)
  const searched = q
    ? posts.filter(
        (p) =>
          p.title.toLowerCase().includes(q) ||
          p.body.toLowerCase().includes(q) ||
          p.author.username.toLowerCase().includes(q) ||
          p.board.toLowerCase().includes(q)
      )
    : posts

  return NextResponse.json({
    posts: searched.slice(0, limit).map((p) => ({
      id: p.id,
      board: p.board,
      title: p.title,
      // short plain-text excerpt for the feed card (fx tags stripped)
      excerpt: p.body
        .replace(/\[(\/?[a-zA-Z]+)\]/g, '')
        .slice(0, 220),
      videoUrl: p.videoUrl,
      mediaJson: p.mediaJson,
      codeFileId: p.codeFileId,
      codeFileName: p.codeFileName,
      likeIds: p.likeIds,
      downIds: p.downIds,
      editedAt: p.editedAt,
      views: p.views,
      author: p.author,
      createdAt: p.createdAt,
      replyCount: p._count.replies,
    })),
  })
}

// POST /api/labs — create a topic (multipart: title, board, body, videoUrl, codeFile)
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const title = String(form.get('title') || '').trim()
  const board = String(form.get('board') || '').trim()
  const body = String(form.get('body') || '').trim().slice(0, 20000)
  const videoUrlRaw = String(form.get('videoUrl') || '').trim()

  if (title.length < 5 || title.length > 120) {
    return NextResponse.json({ error: 'Title must be 5-120 characters.' }, { status: 400 })
  }
  if (!(LAB_BOARDS as readonly string[]).includes(board)) {
    return NextResponse.json({ error: 'Pick a board for your post.' }, { status: 400 })
  }

  let videoUrl: string | null = null
  if (videoUrlRaw) {
    try {
      const u = new URL(videoUrlRaw)
      if (!['http:', 'https:'].includes(u.protocol)) throw new Error('bad protocol')
      videoUrl = videoUrlRaw
    } catch {
      return NextResponse.json({ error: 'That video link does not look right.' }, { status: 400 })
    }
  }

  let codeFileId: string | null = null
  let codeFileName: string | null = null
  const codeFile = form.get('codeFile')
  if (codeFile instanceof File && codeFile.size > 0) {
    if (codeFile.size > 40 * 1024 * 1024) {
      return NextResponse.json({ error: 'Source archive too large (max 40MB).' }, { status: 400 })
    }
    const saved = await saveUpload(codeFile, user.id)
    codeFileId = saved.id
    codeFileName = codeFile.name
  }

  // uploaded media: up to 3 images + 1 video file
  const media: { fileId: string; type: 'image' | 'video'; name: string }[] = []
  const mediaFiles = form.getAll('mediaFile').filter((f): f is File => f instanceof File && f.size > 0)
  for (const mf of mediaFiles) {
    if (media.length >= 4) break
    const isImage = mf.type.startsWith('image/')
    const isVideo = mf.type.startsWith('video/')
    if (!isImage && !isVideo) continue
    const maxMB = isVideo ? 40 : 8
    if (mf.size > maxMB * 1024 * 1024) {
      return NextResponse.json({ error: `${mf.name} is too large (max ${maxMB}MB).` }, { status: 400 })
    }
    const saved = await saveUpload(mf, user.id)
    media.push({ fileId: saved.id, type: isVideo ? 'video' : 'image', name: mf.name })
  }

  const post = await db.labPost.create({
    data: { board, title, body, videoUrl, codeFileId, codeFileName, mediaJson: JSON.stringify(media), authorId: user.id },
  })

  return NextResponse.json({ post: { id: post.id, title: post.title } })
}
