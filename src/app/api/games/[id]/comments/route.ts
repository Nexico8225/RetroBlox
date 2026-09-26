import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  // multipart: text + optional image/video/audio attachment
  const form = await req.formData()
  const text = String(form.get('text') || '').trim()
  if (!text || text.length > 500) {
    return NextResponse.json({ error: 'Comment must be 1-500 characters.' }, { status: 400 })
  }

  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })

  // optional reply-to: replies always attach to a TOP-LEVEL comment (if the
  // parent is itself a reply, we thread under its parent instead) — this
  // keeps every thread one level deep and easy to read
  const parentRaw = form.get('parentId')
  let parentId: string | null = null
  if (typeof parentRaw === 'string' && parentRaw) {
    const parent = await db.comment.findUnique({
      where: { id: parentRaw },
      select: { id: true, gameId: true, parentId: true },
    })
    if (!parent || parent.gameId !== id) {
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

  // Steam-style review fields: recommendation thumbs + optional 0-5 stars
  const recRaw = form.get('rec')
  const ratingRaw = form.get('rating')
  let rec: number | null = null
  if (recRaw === '1' || recRaw === '0') rec = parseInt(recRaw)
  let rating: number | null = null
  if (ratingRaw !== null && ratingRaw !== '') {
    const n = Math.round(parseFloat(String(ratingRaw)))
    if (!isNaN(n) && n >= 0 && n <= 5) rating = n
  }

  const comment = await db.comment.create({
    data: { text, userId: user.id, gameId: id, mediaFileId, mediaType, mediaName, rec, rating, parentId },
    include: { user: { select: { id: true, username: true, avatarUrl: true, lastSeen: true, createdAt: true } } },
  })

  return NextResponse.json({ comment: { ...comment, user: publicUser(comment.user) } })
}
