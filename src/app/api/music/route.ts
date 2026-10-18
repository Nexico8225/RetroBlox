import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

/** GET /api/music?q=<search> — the track library (newest first) */
export async function GET(req: NextRequest) {
  const q = (new URL(req.url).searchParams.get('q') || '').trim()

  const tracks = await db.musicTrack.findMany({
    where: {
      deletedAt: null,
      ...(q
        ? {
            OR: [
              { title: { contains: q } },
              { creator: { is: { username: { contains: q } } } },
            ],
          }
        : {}),
    },
    include: { creator: { select: { id: true, username: true, avatarUrl: true } } },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })

  return NextResponse.json({
    tracks: tracks.map((t) => ({
      id: t.id,
      title: t.title,
      url: `/api/files/${t.fileId}`,
      fileName: t.fileName,
      plays: t.plays,
      createdAt: t.createdAt,
      creator: t.creator,
    })),
  })
}

/** POST /api/music — upload a track (multipart: title + audio) */
export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const form = await req.formData()
  const title = String(form.get('title') || '').trim()
  const audio = form.get('audio')

  if (title.length < 1 || title.length > 80) {
    return NextResponse.json({ error: 'Title must be 1-80 characters.' }, { status: 400 })
  }
  if (!(audio instanceof File) || audio.size === 0) {
    return NextResponse.json({ error: 'Pick an audio file (MP3 / OGG / WAV).' }, { status: 400 })
  }
  if (audio.size > 8 * 1024 * 1024) {
    return NextResponse.json({ error: 'Audio too large (max 8MB).' }, { status: 400 })
  }
  const mime = (audio.type || '').toLowerCase()
  const nameLower = (audio.name || '').toLowerCase()
  const audioOk =
    mime.startsWith('audio/') ||
    /\.(mp3|ogg|wav|oga|m4a|webm)$/.test(nameLower)
  if (!audioOk) {
    return NextResponse.json({ error: `"${audio.name}" is not an audio file (MP3 / OGG / WAV).` }, { status: 400 })
  }

  const file = await saveUpload(audio, user.id)
  const track = await db.musicTrack.create({
    data: {
      title,
      creatorId: user.id,
      fileId: file.id,
      fileName: audio.name,
    },
    include: { creator: { select: { id: true, username: true, avatarUrl: true } } },
  })

  return NextResponse.json({
    ok: true,
    track: {
      id: track.id,
      title: track.title,
      url: `/api/files/${track.fileId}`,
      fileName: track.fileName,
      plays: track.plays,
      createdAt: track.createdAt,
      creator: track.creator,
    },
  })
}
