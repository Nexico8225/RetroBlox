import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'
import { parseIds } from '@/lib/stats'

// GET /api/labs/[id] — topic + replies (counts one view)
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const me = await getUserFromReq(req)

  const post = await db.labPost.findUnique({
    where: { id },
    include: {
      author: { select: { id: true, username: true, avatarUrl: true, role: true, createdAt: true, lastSeen: true } },
      replies: {
        include: { author: { select: { id: true, username: true, avatarUrl: true, role: true, lastSeen: true } } },
        orderBy: { createdAt: 'asc' },
      },
    },
  })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })

  // fire-and-forget view bump
  await db.labPost.update({ where: { id }, data: { views: { increment: 1 } } })

  const likeIds = parseIds(post.likeIds)
  const downIds = parseIds(post.downIds)
  const myVote = me ? (likeIds.includes(me.id) ? 1 : downIds.includes(me.id) ? -1 : 0) : 0
  return NextResponse.json({
    post: {
      ...post,
      views: post.views + 1,
      ups: likeIds.length,
      downs: downIds.length,
      score: likeIds.length - downIds.length,
      likes: likeIds.length, // back-compat
      myVote,
      myLike: myVote === 1, // back-compat
      replies: post.replies.map((r) => {
        const rl = parseIds(r.likeIds)
        return { ...r, likes: rl.length, myLike: me ? rl.includes(me.id) : false }
      }),
    },
  })
}

// PATCH /api/labs/[id] — JSON body:
//   { vote: 1 }    → upvote   (toggles off if already upvoted)
//   { vote: -1 }   → downvote (toggles off if already downvoted; cancels an upvote)
//   { vote: 0 }    → clear my vote
//   { title?, body?, videoUrl? } → edit the post (author or admin only, sets editedAt)
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { id } = await params

  const post = await db.labPost.findUnique({ where: { id } })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })

  // ---- parse the (optional) JSON body safely ----
  let payload: { vote?: unknown; title?: unknown; body?: unknown; videoUrl?: unknown } = {}
  try {
    const raw = await req.text()
    if (raw) payload = JSON.parse(raw)
  } catch {
    return NextResponse.json({ error: 'Bad request body.' }, { status: 400 })
  }

  // ---- edit mode ----
  const wantsEdit = payload.title !== undefined || payload.body !== undefined || payload.videoUrl !== undefined
  if (wantsEdit) {
    if (post.authorId !== me.id && me.role !== 'admin') {
      return NextResponse.json({ error: 'Only the author can edit this post.' }, { status: 403 })
    }
    const data: { title?: string; body?: string; videoUrl?: string | null; editedAt: Date } = { editedAt: new Date() }

    if (payload.title !== undefined) {
      const title = String(payload.title).trim()
      if (title.length < 5 || title.length > 120) {
        return NextResponse.json({ error: 'Title must be 5-120 characters.' }, { status: 400 })
      }
      data.title = title
    }
    if (payload.body !== undefined) {
      const body = String(payload.body).trim().slice(0, 20000)
      data.body = body
    }
    if (payload.videoUrl !== undefined) {
      const raw = String(payload.videoUrl).trim()
      if (raw) {
        try {
          const u = new URL(raw)
          if (!['http:', 'https:'].includes(u.protocol)) throw new Error('bad protocol')
          data.videoUrl = raw
        } catch {
          return NextResponse.json({ error: 'That video link does not look right.' }, { status: 400 })
        }
      } else {
        data.videoUrl = null
      }
    }

    const updated = await db.labPost.update({ where: { id }, data })
    const likeIds = parseIds(updated.likeIds)
    const downIds = parseIds(updated.downIds)
    return NextResponse.json({
      ok: true,
      post: {
        title: updated.title,
        body: updated.body,
        videoUrl: updated.videoUrl,
        editedAt: updated.editedAt,
        ups: likeIds.length,
        downs: downIds.length,
        score: likeIds.length - downIds.length,
        myVote: me ? (likeIds.includes(me.id) ? 1 : downIds.includes(me.id) ? -1 : 0) : 0,
      },
    })
  }

  // ---- vote mode (default when no edit fields) ----
  const voteRaw = payload.vote === undefined ? 1 : payload.vote // legacy no-body PATCH = upvote
  const vote = Number(voteRaw)
  if (![-1, 0, 1].includes(vote)) {
    return NextResponse.json({ error: 'vote must be -1, 0 or 1.' }, { status: 400 })
  }

  const ups = parseIds(post.likeIds)
  const downs = parseIds(post.downIds)
  const hadUp = ups.includes(me.id)
  const hadDown = downs.includes(me.id)

  // remove me from both lists, then apply the new vote
  const nextUps = ups.filter((x) => x !== me.id)
  const nextDowns = downs.filter((x) => x !== me.id)
  if (vote === 1 && !hadUp) nextUps.push(me.id)
  if (vote === -1 && !hadDown) nextDowns.push(me.id)

  await db.labPost.update({ where: { id }, data: { likeIds: JSON.stringify(nextUps), downIds: JSON.stringify(nextDowns) } })

  return NextResponse.json({
    ups: nextUps.length,
    downs: nextDowns.length,
    score: nextUps.length - nextDowns.length,
    myVote: vote === 1 && !hadUp ? 1 : vote === -1 && !hadDown ? -1 : 0,
  })
}

// POST /api/labs/[id] — reply: { text }
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = await req.json()
  const text = String(body.text || '').trim()
  if (!text || text.length > 2000) {
    return NextResponse.json({ error: 'Reply must be 1-2000 characters.' }, { status: 400 })
  }

  const post = await db.labPost.findUnique({ where: { id }, select: { id: true } })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })

  const reply = await db.labReply.create({
    data: { text, postId: id, authorId: user.id },
    include: { author: { select: { id: true, username: true, avatarUrl: true, role: true, lastSeen: true } } },
  })

  return NextResponse.json({ reply: { ...reply, author: publicUser(reply.author) } })
}

// DELETE /api/labs/[id] — author or admin
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const post = await db.labPost.findUnique({ where: { id } })
  if (!post) return NextResponse.json({ error: 'Post not found' }, { status: 404 })
  if (post.authorId !== user.id && user.role !== 'admin') {
    return NextResponse.json({ error: 'Not your post!' }, { status: 403 })
  }

  await db.labPost.delete({ where: { id } })
  return NextResponse.json({ ok: true })
}
