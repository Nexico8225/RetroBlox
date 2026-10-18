import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

// GET /api/community?sort=hot|new|top&flair=memes&sub=slug&q=search
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const sort = searchParams.get('sort') || 'hot'
  const flair = searchParams.get('flair') || ''
  const subSlug = searchParams.get('sub') || ''
  const q = (searchParams.get('q') || '').trim().toLowerCase()
  const limit = Math.min(parseInt(searchParams.get('limit') || '50'), 100)

  const sub = subSlug
    ? await db.sub.findUnique({ where: { slug: subSlug.toLowerCase() }, select: { id: true } })
    : null
  if (subSlug && !sub) {
    return NextResponse.json({ posts: [], sub: null })
  }

  const posts = await db.communityPost.findMany({
    where: {
      ...(flair ? { flair } : {}),
      ...(sub ? { subId: sub.id } : {}),
    },
    include: {
      author: { select: { id: true, username: true, avatarUrl: true, role: true } },
      sub: { select: { id: true, slug: true, name: true, color: true, iconFileId: true } },
      _count: { select: { comments: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })

  const mapped = posts.map((p) => {
    let upIds: string[] = []
    let downIds: string[] = []
    try { upIds = JSON.parse(p.upIds || '[]') } catch { /* ignore */ }
    try { downIds = JSON.parse(p.downIds || '[]') } catch { /* ignore */ }
    const ups = upIds.length
    const downs = downIds.length
    const score = ups - downs
    const ageHours = Math.max(0.5, (Date.now() - new Date(p.createdAt).getTime()) / 3600000)
    return {
      id: p.id,
      title: p.title,
      body: p.body,
      flair: p.flair,
      sub: p.sub,
      mediaFileId: p.mediaFileId,
      mediaType: p.mediaType,
      mediaName: p.mediaName,
      videoId: p.videoId,
      author: p.author,
      createdAt: p.createdAt,
      ups,
      downs,
      score,
      myVote: 0, // filled below when logged in
      commentCount: p._count.comments,
      hot: score / Math.pow(ageHours + 2, 1.4),
    }
  })

  // case-insensitive search over title + body (JS-side, SQLite contains is case-sensitive)
  const searched = q
    ? mapped.filter(
        (p) =>
          p.title.toLowerCase().includes(q) ||
          p.body.toLowerCase().includes(q) ||
          p.author.username.toLowerCase().includes(q) ||
          (p.sub?.slug || '').toLowerCase().includes(q)
      )
    : mapped

  let sorted = searched
  if (sort === 'hot') sorted = [...searched].sort((a, b) => b.hot - a.hot)
  else if (sort === 'top') sorted = [...searched].sort((a, b) => b.score - a.score)

  // fill my vote if logged in
  const me = await getUserFromReq(req)
  if (me) {
    for (const p of sorted) {
      const full = posts.find((x) => x.id === p.id)
      if (full) {
        let upIds: string[] = []
        let downIds: string[] = []
        try { upIds = JSON.parse(full.upIds || '[]') } catch { /* ignore */ }
        try { downIds = JSON.parse(full.downIds || '[]') } catch { /* ignore */ }
        p.myVote = upIds.includes(me.id) ? 1 : downIds.includes(me.id) ? -1 : 0
      }
    }
  }

  return NextResponse.json({ posts: sorted.slice(0, limit) })
}

// POST /api/community — new post (multipart: title, body, flair, subSlug, mediaFile image/video)
// Attaching a VIDEO also publishes it to the Videos tab (/videos) with its own watch page.
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const title = String(form.get('title') || '').trim()
  const postBody = String(form.get('body') || '').trim().slice(0, 10000)
  const flairRaw = String(form.get('flair') || '')
  const flair = ['General', 'Memes', 'Help', 'Finds', 'Off-Topic'].includes(flairRaw) ? flairRaw : 'General'
  const subSlug = String(form.get('subSlug') || '').trim().toLowerCase()

  if (title.length < 5 || title.length > 120) {
    return NextResponse.json({ error: 'Title must be 5-120 characters.' }, { status: 400 })
  }

  // player-created r/ community (optional)
  let subId: string | null = null
  if (subSlug) {
    const sub = await db.sub.findUnique({ where: { slug: subSlug }, select: { id: true } })
    if (!sub) {
      return NextResponse.json({ error: 'That community does not exist.' }, { status: 400 })
    }
    subId = sub.id
  }

  // optional image / video upload (reddit-style: pictures + clips, no links)
  let mediaFileId: string | null = null
  let mediaType: string | null = null
  let mediaName: string | null = null
  const file = form.get('mediaFile')
  if (file instanceof File && file.size > 0) {
    const isImage = file.type.startsWith('image/')
    const isVideo = file.type.startsWith('video/')
    if (!isImage && !isVideo) {
      return NextResponse.json({ error: 'Posts can hold an image or a video (GIFs count as images!).' }, { status: 400 })
    }
    const maxMB = isVideo ? 100 : 8
    if (file.size > maxMB * 1024 * 1024) {
      return NextResponse.json({ error: `${file.name} is too large (max ${maxMB}MB).` }, { status: 400 })
    }
    const saved = await saveUpload(file, user.id)
    mediaFileId = saved.id
    mediaType = isVideo ? 'video' : 'image'
    mediaName = file.name
  }

  if (!postBody && !mediaFileId) {
    return NextResponse.json({ error: 'Write something or attach a picture / video!' }, { status: 400 })
  }

  const post = await db.communityPost.create({
    data: { title, body: postBody, flair, subId, mediaFileId, mediaType, mediaName, authorId: user.id, upIds: JSON.stringify([user.id]) },
  })

  // a post with a video is ALSO a video — it gets a watch page on /videos/[id]
  let videoId: string | null = null
  if (mediaType === 'video' && mediaFileId) {
    const video = await db.video.create({
      data: {
        title,
        description: postBody.slice(0, 2000),
        fileId: mediaFileId,
        fileName: mediaName,
        postId: post.id,
        authorId: user.id,
      },
    })
    videoId = video.id
    await db.communityPost.update({ where: { id: post.id }, data: { videoId } })
  }

  return NextResponse.json({ post: { id: post.id, title: post.title, videoId } })
}
