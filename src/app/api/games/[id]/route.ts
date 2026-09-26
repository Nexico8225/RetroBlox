import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'

async function gameDetail(id: string, viewerId: string | null) {
  const g = await db.game.findUnique({
    where: { id },
    include: {
      creator: { select: { id: true, username: true, avatarUrl: true, role: true, createdAt: true, lastSeen: true } },
      group: { select: { id: true, name: true } },
      likes: true,
      favorites: true,
      comments: {
        include: { user: { select: { id: true, username: true, avatarUrl: true, role: true, lastSeen: true } } },
        orderBy: { createdAt: 'desc' },
      },
    },
  })
  if (!g) return null
  const likes = g.likes.filter((l) => l.value === 1).length
  const dislikes = g.likes.filter((l) => l.value === -1).length
  const isOwner = viewerId === g.creatorId

  // Steam-style media gallery [{fileId, type: "video"|"image", name}]
  let media: { fileId: string; type: string; name: string }[] = []
  try {
    media = JSON.parse(g.mediaJson || '[]')
  } catch { /* keep [] */ }

  // Steam-style review stats (from reviews that carry a recommendation)
  const reviews = g.comments
  const rated = reviews.filter((c) => c.rec === 1 || c.rec === 0)
  const recCount = rated.filter((c) => c.rec === 1).length
  const starred = reviews.filter((c) => typeof c.rating === 'number')
  const avgRating = starred.length > 0
    ? Math.round((starred.reduce((s, c) => s + (c.rating || 0), 0) / starred.length) * 10) / 10
    : null
  const positivePct = rated.length > 0 ? Math.round((recCount / rated.length) * 100) : null

  // Steam-style playtime stats for this game ("12.4 hrs played by 8 players")
  const playAgg = await db.gamePlay.aggregate({
    where: { gameId: id },
    _sum: { seconds: true, playCount: true },
    _count: true,
  })
  const playtime = {
    totalSeconds: playAgg._sum.seconds || 0,
    players: playAgg._count || 0,
    sessions: playAgg._sum.playCount || 0,
    avgSeconds: playAgg._count > 0 ? Math.round((playAgg._sum.seconds || 0) / playAgg._count) : 0,
  }

  return {
    id: g.id,
    name: g.name,
    description: g.description,
    genre: g.genre,
    subgenre: g.subgenre,
    engine: g.engine,
    maturity: g.maturity,
    iconUrl: g.iconUrl,
    thumbnailUrl: g.thumbnailUrl,
    fileId: g.fileId,
    fileName: g.fileName,
    sourceFileId: g.sourceFileId,
    sourceFileName: g.sourceFileName,
    hasFile: !!g.fileId,
    downloads: g.downloads,
    views: g.views,
    gem: g.gem,
    media,
    group: g.group,
    createdAt: g.createdAt,
    updatedAt: g.updatedAt,
    creator: g.creator,
    likes,
    dislikes,
    rating: likes + dislikes > 0 ? Math.round((likes / (likes + dislikes)) * 100) : null,
    reviewStats: {
      avgRating, // 0-5, one decimal, or null
      positivePct, // % of reviews that recommend, or null
      reviewCount: rated.length,
      recCount,
      notRecCount: rated.length - recCount,
    },
    playtime,
    favorites: g.favorites.length,
    comments: g.comments,
    myLike: viewerId ? (g.likes.find((l) => l.userId === viewerId)?.value ?? 0) : 0,
    myFavorite: viewerId ? g.favorites.some((f) => f.userId === viewerId) : false,
    isOwner,
  }
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  const detail = await gameDetail(id, user?.id || null)
  if (!detail) return NextResponse.json({ error: 'Game not found' }, { status: 404 })
  return NextResponse.json({ game: detail })
}

// Update game: replace build file / source code / add media (updates "Updated" timestamp) or edit text fields
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })
  if (game.creatorId !== user.id) return NextResponse.json({ error: 'Not your game!' }, { status: 403 })

  const form = await req.formData()
  const data: Record<string, unknown> = { updatedAt: new Date() }

  const description = form.get('description')
  if (typeof description === 'string' && description.trim()) data.description = description.trim()

  const genre = form.get('genre')
  if (typeof genre === 'string' && genre) data.genre = genre
  const subgenre = form.get('subgenre')
  if (typeof subgenre === 'string') data.subgenre = subgenre.trim()

  const gameFile = form.get('gameFile')
  if (gameFile instanceof File && gameFile.size > 0) {
    if (gameFile.size > 60 * 1024 * 1024) return NextResponse.json({ error: 'Game file too large (max 60MB).' }, { status: 400 })
    const saved = await saveUpload(gameFile, user.id)
    data.fileId = saved.id
    data.fileName = gameFile.name
  }

  const sourceFile = form.get('sourceFile')
  if (sourceFile instanceof File && sourceFile.size > 0) {
    if (sourceFile.size > 40 * 1024 * 1024) return NextResponse.json({ error: 'Source archive too large (max 40MB).' }, { status: 400 })
    const saved = await saveUpload(sourceFile, user.id)
    data.sourceFileId = saved.id
    data.sourceFileName = sourceFile.name
  }

  // append new media to the Steam-style gallery
  let current: { fileId: string; type: string; name: string }[] = []
  try {
    current = JSON.parse(game.mediaJson || '[]')
  } catch { /* keep [] */ }
  let added = false
  for (const entry of form.getAll('media')) {
    if (!(entry instanceof File) || entry.size === 0) continue
    if (current.length >= 8) return NextResponse.json({ error: 'Max 8 media items.' }, { status: 400 })
    const isVideo = entry.type.startsWith('video/')
    const isImage = entry.type.startsWith('image/')
    if (!isVideo && !isImage) return NextResponse.json({ error: 'Media must be videos or images.' }, { status: 400 })
    const maxMB = isVideo ? 100 : 8
    if (entry.size > maxMB * 1024 * 1024) {
      return NextResponse.json({ error: `"${entry.name}" is too large (max ${maxMB}MB).` }, { status: 400 })
    }
    const m = await saveUpload(entry, user.id)
    current.push({ fileId: m.id, type: isVideo ? 'video' : 'image', name: entry.name })
    added = true
  }
  if (added) data.mediaJson = JSON.stringify(current)

  // owner can also remove one media item by fileId
  const removeMedia = form.get('removeMediaFileId')
  if (typeof removeMedia === 'string' && removeMedia) {
    current = current.filter((m) => m.fileId !== removeMedia)
    data.mediaJson = JSON.stringify(current)
  }

  await db.game.update({ where: { id }, data: data as never })
  return NextResponse.json({ ok: true })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const user = await getUserFromReq(req)
  if (!user) return NextResponse.json({ error: 'Login required' }, { status: 401 })
  const game = await db.game.findUnique({ where: { id } })
  if (!game) return NextResponse.json({ error: 'Game not found' }, { status: 404 })
  // the creator can delete their own game; an admin can delete ANY game
  if (game.creatorId !== user.id && user.role !== 'admin') {
    return NextResponse.json({ error: 'Not your game!' }, { status: 403 })
  }
  await db.game.delete({ where: { id } })
  return NextResponse.json({ ok: true, deletedBy: user.role === 'admin' && game.creatorId !== user.id ? 'admin' : 'owner' })
}
