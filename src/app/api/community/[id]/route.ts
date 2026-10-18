import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'
import { parseIds } from '@/lib/stats'
import { saveUpload } from '@/lib/uploads'

// GET /api/community/[id]
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)

  const post = await db.communityPost.findUnique({
    where: { id },
    include: {
      author: { select: { id: true, username: true, avatarUrl: true, role: true, createdAt: true } },
      sub: { select: { id: true, slug: true, name: true, color: true, iconFileId: true } },
      comments: {
        include: { author: { select: { id: true, username: true, avatarUrl: true, role: true, lastSeen: true } } },
        orderBy: { createdAt: 'asc' },
      },
    },
  })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })

  const ups = parseIds(post.upIds)
  const downs = parseIds(post.downIds)

  return NextResponse.json({
    post: {
      id: post.id,
      title: post.title,
      body: post.body,
      flair: post.flair,
      sub: post.sub,
      mediaFileId: post.mediaFileId,
      mediaType: post.mediaType,
      mediaName: post.mediaName,
      videoId: post.videoId,
      author: post.author,
      createdAt: post.createdAt,
      ups: ups.length,
      downs: downs.length,
      score: ups.length - downs.length,
      myVote: me ? (ups.includes(me.id) ? 1 : downs.includes(me.id) ? -1 : 0) : 0,
      comments: post.comments.map((c) => {
        const cl = parseIds(c.likeIds)
        return {
          ...c,
          likes: cl.length,
          myLike: me ? cl.includes(me.id) : false,
        }
      }),
    },
  })
}

// POST /api/community/[id] — comment (multipart: text + optional image/video attachment)
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const text = String(form.get('text') || '').trim()
  if (!text || text.length > 2000) {
    return NextResponse.json({ error: 'Comment must be 1-2000 characters.' }, { status: 400 })
  }

  const post = await db.communityPost.findUnique({ where: { id }, select: { id: true } })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })

  // optional reply-to: replies always attach to a TOP-LEVEL comment (if the
  // parent is itself a reply, we thread under its parent instead) — one
  // level deep, always readable
  const parentRaw = form.get('parentId')
  let parentId: string | null = null
  if (typeof parentRaw === 'string' && parentRaw) {
    const parent = await db.communityComment.findUnique({
      where: { id: parentRaw },
      select: { id: true, postId: true, parentId: true },
    })
    if (!parent || parent.postId !== id) {
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
    if (!isImage && !isVideo) {
      return NextResponse.json({ error: 'Comments can hold an image or a video.' }, { status: 400 })
    }
    const maxMB = isVideo ? 40 : 8
    if (file.size > maxMB * 1024 * 1024) {
      return NextResponse.json({ error: `${file.name} is too large (max ${maxMB}MB).` }, { status: 400 })
    }
    const saved = await saveUpload(file, user.id)
    mediaFileId = saved.id
    mediaType = isVideo ? 'video' : 'image'
    mediaName = file.name
  }

  const comment = await db.communityComment.create({
    data: { text, postId: id, authorId: user.id, mediaFileId, mediaType, mediaName, parentId },
    include: { author: { select: { id: true, username: true, avatarUrl: true, role: true, lastSeen: true } } },
  })

  return NextResponse.json({ comment: { ...comment, likes: 0, myLike: false, author: publicUser(comment.author) } })
}

// PATCH /api/community/[id] — vote: { value: 1 | -1 | 0 }
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = await req.json()
  const value = Number(body.value)
  if (![1, -1, 0].includes(value)) return NextResponse.json({ error: 'Invalid vote' }, { status: 400 })

  const post = await db.communityPost.findUnique({ where: { id } })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })

  const ups = parseIds(post.upIds)
  const downs = parseIds(post.downIds)

  const upHas = ups.includes(user.id)
  const downHas = downs.includes(user.id)

  let nextUps = ups
  let nextDowns = downs
  let myVote = 0

  if (value === 0 || (value === 1 && upHas) || (value === -1 && downHas)) {
    // toggle off
    nextUps = ups.filter((x) => x !== user.id)
    nextDowns = downs.filter((x) => x !== user.id)
  } else if (value === 1) {
    nextUps = [...ups, user.id]
    nextDowns = downs.filter((x) => x !== user.id)
    myVote = 1
  } else {
    nextDowns = [...downs, user.id]
    nextUps = ups.filter((x) => x !== user.id)
    myVote = -1
  }

  await db.communityPost.update({
    where: { id },
    data: { upIds: JSON.stringify(nextUps), downIds: JSON.stringify(nextDowns) },
  })

  return NextResponse.json({ ups: nextUps.length, downs: nextDowns.length, score: nextUps.length - nextDowns.length, myVote })
}

// DELETE /api/community/[id] — author or admin
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const post = await db.communityPost.findUnique({ where: { id } })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })
  if (post.authorId !== user.id && user.role !== 'admin') {
    return NextResponse.json({ error: 'Not your post!' }, { status: 403 })
  }

  await db.communityPost.delete({ where: { id } })
  return NextResponse.json({ ok: true })
}
