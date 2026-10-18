import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

// GET /api/chat/[userId] — full thread with ANY member (marks incoming as read)
export async function GET(req: NextRequest, { params }: { params: Promise<{ userId: string }> }) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { userId } = await params

  const friend = await db.user.findUnique({ where: { id: userId } })
  if (!friend) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  // open DMs — you can message anyone on RetroBlox (that's how you nudge
  // someone to accept your friend request). Report/block lives at the
  // platform level, not here.

  // mark their messages as read
  await db.chatMessage.updateMany({
    where: { senderId: userId, recipientId: me.id, readAt: null },
    data: { readAt: new Date() },
  })

  const messages = await db.chatMessage.findMany({
    where: { OR: [{ senderId: me.id, recipientId: userId }, { senderId: userId, recipientId: me.id }] },
    orderBy: { createdAt: 'asc' },
    take: 300,
  })

  return NextResponse.json({
    friend: publicUser(friend),
    messages: messages.map((m) => ({
      id: m.id,
      text: m.text,
      fileId: m.fileId,
      fileType: m.fileType,
      fileName: m.fileName,
      fromMe: m.senderId === me.id,
      createdAt: m.createdAt,
    })),
  })
}

// POST /api/chat/[userId] — send a message (multipart: text + optional file image/video/audio/gif)
export async function POST(req: NextRequest, { params }: { params: Promise<{ userId: string }> }) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const { userId } = await params
  if (userId === me.id) return NextResponse.json({ error: 'Cannot chat with yourself!' }, { status: 400 })

  // open DMs — message any member (friends, pending requests, strangers)
  const target = await db.user.findUnique({ where: { id: userId } })
  if (!target) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  // accept JSON (text-only) or multipart (text + file attachment)
  const contentType = req.headers.get('content-type') || ''
  let text = ''
  let file: File | null = null
  if (contentType.includes('multipart/form-data')) {
    const form = await req.formData()
    text = String(form.get('text') || '').trim().slice(0, 2000)
    const f = form.get('file')
    if (f instanceof File && f.size > 0) file = f
  } else {
    const body = await req.json()
    text = String(body.text || '').trim().slice(0, 2000)
  }

  let fileId: string | null = null
  let fileType: string | null = null
  let fileName: string | null = null
  if (file) {
    const isImage = file.type.startsWith('image/') // includes gif
    const isVideo = file.type.startsWith('video/')
    const isAudio = file.type.startsWith('audio/')
    if (!isImage && !isVideo && !isAudio) {
      return NextResponse.json({ error: 'Only images, GIFs, videos and audio can be attached.' }, { status: 400 })
    }
    const maxMB = isVideo ? 40 : isAudio ? 15 : 10
    if (file.size > maxMB * 1024 * 1024) {
      return NextResponse.json({ error: `File too large (max ${maxMB}MB).` }, { status: 400 })
    }
    const saved = await saveUpload(file, me.id)
    fileId = saved.id
    fileType = isImage ? 'image' : isVideo ? 'video' : 'audio'
    fileName = file.name
  }

  if (!text && !fileId) {
    return NextResponse.json({ error: 'Write something or attach a picture!' }, { status: 400 })
  }

  const msg = await db.chatMessage.create({
    data: { senderId: me.id, recipientId: userId, text, fileId, fileType, fileName },
  })

  return NextResponse.json({
    message: {
      id: msg.id,
      text: msg.text,
      fileId: msg.fileId,
      fileType: msg.fileType,
      fileName: msg.fileName,
      fromMe: true,
      createdAt: msg.createdAt,
    },
  })
}
