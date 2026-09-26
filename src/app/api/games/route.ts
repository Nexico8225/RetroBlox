import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq } from '@/lib/auth'
import { saveUpload } from '@/lib/uploads'
import { Prisma } from '@prisma/client'

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const q = searchParams.get('q')?.trim() || ''
  const genre = searchParams.get('genre') || ''
  const sort = searchParams.get('sort') || 'popular' // popular | recommended | trending | recent | updated | downloads | topRated | gems
  const creatorId = searchParams.get('creatorId') || ''
  const list = searchParams.get('list') || '' // played | downloaded — "your games" rails
  const limit = Math.min(parseInt(searchParams.get('limit') || '60'), 100)

  const viewer = await getUserFromReq(req)

  /* "Games You've Played" / "Your Downloaded Games" rails on the home page */
  if (list === 'played' || list === 'downloaded') {
    if (!viewer) return NextResponse.json({ games: [] })
    const gameInclude = {
      include: {
        creator: { select: { id: true, username: true, avatarUrl: true } },
        likes: true,
        _count: { select: { comments: true, favorites: true } },
      },
    }
    const games = list === 'played'
      ? (await db.gamePlay.findMany({
          where: { userId: viewer.id },
          orderBy: { lastPlayedAt: 'desc' },
          take: limit,
          include: { game: gameInclude },
        })).filter((r) => r.game).map((r) => ({ ...mapGameLite(r.game), extra: `Played ${r.playCount}x` }))
      : (await db.gameDownload.findMany({
          where: { userId: viewer.id },
          orderBy: { lastAt: 'desc' },
          take: limit,
          include: { game: gameInclude },
        })).filter((r) => r.game).map((r) => ({ ...mapGameLite(r.game), extra: `Downloaded ${r.count}x` }))
    return NextResponse.json({ games })
  }

  const where: Prisma.GameWhereInput = {}
  if (q) {
    // SQLite contains is case-sensitive; cover common casings across
    // name + description + creator — a real search, not just titles
    const variants = Array.from(new Set([
      q,
      q.toLowerCase(),
      q.charAt(0).toUpperCase() + q.slice(1).toLowerCase(),
      q.toUpperCase(),
    ]))
    where.OR = variants.flatMap((v) => [
      { name: { contains: v } },
      { description: { contains: v } },
      { creator: { is: { username: { contains: v } } } },
    ])
  }
  if (genre && genre !== 'All Genres') where.genre = genre
  if (creatorId) where.creatorId = creatorId
  if (sort === 'gems') where.gem = true

  const orderBy: Prisma.GameOrderByWithRelationInput[] =
    sort === 'recent'
      ? [{ createdAt: 'desc' }]
      : sort === 'updated'
        ? [{ updatedAt: 'desc' }]
        : sort === 'downloads'
          ? [{ downloads: 'desc' }]
          : [{ downloads: 'desc' }, { createdAt: 'desc' }]

  // ranked fetches pull extra rows so the JS-side scoring has a real pool
  const fetchLimit = sort === 'recommended' || sort === 'trending' ? 100 : limit

  const games = await db.game.findMany({
    where,
    orderBy,
    take: fetchLimit,
    include: {
      creator: { select: { id: true, username: true, avatarUrl: true } },
      likes: true,
      _count: { select: { comments: true, favorites: true } },
    },
  })

  const mapped = games.map((g) => mapGameLite(g))

  /* YouTube-style discovery scoring — computed over the whole pool:
     - RECOMMENDED: what to watch next — rating leads, engagement (downloads,
       likes, views) and a gentle freshness nudge follow
     - TRENDING: velocity — engagement per day since upload, so a game from
       yesterday with real play beats an old giant */
  const daysOld = (iso: string) => Math.max(0.5, (Date.now() - new Date(iso).getTime()) / 86400000)
  const recommendedScore = (g: ReturnType<typeof mapGameLite>) =>
    (g.rating ?? 50) * 0.6 +
    Math.log10(10 + g.downloads) * 8 +
    Math.log10(10 + g.likes) * 6 +
    Math.log10(10 + g.commentCount + g.favoriteCount) * 4 +
    Math.max(0, 12 - daysOld(g.updatedAt as unknown as string) / 7)
  const trendingScore = (g: ReturnType<typeof mapGameLite>) =>
    (g.likes * 3 + g.downloads + (g.rating ?? 50) * 0.2) / Math.pow(daysOld(g.createdAt as unknown as string), 0.7)

  let sorted = mapped
  if (sort === 'topRated') {
    sorted = [...mapped].sort((a, b) => (b.rating ?? 0) - (a.rating ?? 0))
  } else if (sort === 'recommended') {
    sorted = [...mapped].sort((a, b) => recommendedScore(b) - recommendedScore(a))
  } else if (sort === 'trending') {
    sorted = [...mapped].sort((a, b) => trendingScore(b) - trendingScore(a))
  } else if (sort === 'popular') {
    // popular = weighted mix of rating & downloads
    sorted = [...mapped].sort((a, b) => {
      const score = (x: typeof a) => (x.rating ?? 50) * Math.log10(10 + x.downloads)
      return score(b) - score(a)
    })
  }

  return NextResponse.json({ games: sorted.slice(0, limit) })
}

function mapGameLite(g: {
  id: string
  name: string
  genre: string
  subgenre: string
  engine: string
  maturity: string
  iconUrl: string | null
  thumbnailUrl: string | null
  downloads: number
  gem: boolean
  createdAt: Date
  updatedAt: Date
  creator: { id: string; username: string; avatarUrl: string | null }
  likes: { value: number }[]
  _count: { comments: number; favorites: number }
}) {
  const likes = g.likes.filter((l) => l.value === 1).length
  const dislikes = g.likes.filter((l) => l.value === -1).length
  return {
    id: g.id,
    name: g.name,
    genre: g.genre,
    subgenre: g.subgenre,
    engine: g.engine,
    maturity: g.maturity,
    iconUrl: g.iconUrl,
    thumbnailUrl: g.thumbnailUrl,
    downloads: g.downloads,
    gem: g.gem,
    createdAt: g.createdAt,
    updatedAt: g.updatedAt,
    creator: g.creator,
    likes,
    dislikes,
    rating: likes + dislikes > 0 ? Math.round((likes / (likes + dislikes)) * 100) : null,
    commentCount: g._count.comments,
    favoriteCount: g._count.favorites,
  }
}

export async function POST(req: NextRequest) {
  const user = await getUserFromReq(req)
  if (!user) {
    return NextResponse.json({ error: 'You must be logged in to publish a game!' }, { status: 401 })
  }

  try {
    const form = await req.formData()
    const name = String(form.get('name') || '').trim()
    const description = String(form.get('description') || '').trim()
    const genre = String(form.get('genre') || 'Adventure')
    const subgenre = String(form.get('subgenre') || '').trim()
    const engine = String(form.get('engine') || 'Other')
    const maturity = String(form.get('maturity') || 'Minimal')

    if (name.length < 3 || name.length > 60) {
      return NextResponse.json({ error: 'Game name must be 3-60 characters.' }, { status: 400 })
    }

    const gameFile = form.get('gameFile')
    if (!(gameFile instanceof File) || gameFile.size === 0) {
      return NextResponse.json({ error: 'Please attach your game build file (.zip, .exe, .apk, etc.)' }, { status: 400 })
    }
    if (gameFile.size > 60 * 1024 * 1024) {
      return NextResponse.json({ error: 'Game file is too large (max 60MB).' }, { status: 400 })
    }

    const icon = form.get('icon')
    const thumbnail = form.get('thumbnail')
    let iconUrl: string | null = null
    let thumbnailUrl: string | null = null
    if (icon instanceof File && icon.size > 0) {
      if (icon.size > 2 * 1024 * 1024) return NextResponse.json({ error: 'Icon too large (max 2MB).' }, { status: 400 })
      iconUrl = await fileToDataUrl(icon)
    }
    if (thumbnail instanceof File && thumbnail.size > 0) {
      if (thumbnail.size > 3 * 1024 * 1024) return NextResponse.json({ error: 'Thumbnail too large (max 3MB).' }, { status: 400 })
      thumbnailUrl = await fileToDataUrl(thumbnail)
    }

    const saved = await saveUpload(gameFile, user.id)

    // optional: publish straight into one of my groups
    const groupIdRaw = String(form.get('groupId') || '')
    let groupId: string | null = null
    if (groupIdRaw) {
      const membership = await db.groupMember.findUnique({
        where: { groupId_userId: { groupId: groupIdRaw, userId: user.id } },
      })
      if (membership) groupId = groupIdRaw
    }

    let sourceFileId: string | null = null
    let sourceFileName: string | null = null
    const sourceFile = form.get('sourceFile')
    if (sourceFile instanceof File && sourceFile.size > 0) {
      if (sourceFile.size > 40 * 1024 * 1024) {
        return NextResponse.json({ error: 'Source code archive too large (max 40MB).' }, { status: 400 })
      }
      const src = await saveUpload(sourceFile, user.id)
      sourceFileId = src.id
      sourceFileName = sourceFile.name
    }

    // Steam-style media gallery: videos + images shown on the game page
    const media: { fileId: string; type: string; name: string }[] = []
    for (const entry of form.getAll('media')) {
      if (!(entry instanceof File) || entry.size === 0) continue
      if (media.length >= 8) return NextResponse.json({ error: 'Max 8 media items (videos + screenshots).' }, { status: 400 })
      const isVideo = entry.type.startsWith('video/')
      const isImage = entry.type.startsWith('image/')
      if (!isVideo && !isImage) {
        return NextResponse.json({ error: 'Game media must be videos or images.' }, { status: 400 })
      }
      const maxMB = isVideo ? 100 : 8
      if (entry.size > maxMB * 1024 * 1024) {
        return NextResponse.json({ error: `"${entry.name}" is too large (max ${maxMB}MB).` }, { status: 400 })
      }
      const m = await saveUpload(entry, user.id)
      media.push({ fileId: m.id, type: isVideo ? 'video' : 'image', name: entry.name })
    }

    const game = await db.game.create({
      data: {
        name,
        description,
        genre,
        subgenre,
        engine,
        maturity,
        iconUrl,
        thumbnailUrl,
        fileId: saved.id,
        fileName: gameFile.name,
        sourceFileId,
        sourceFileName,
        mediaJson: JSON.stringify(media),
        groupId,
        creatorId: user.id,
      },
    })

    return NextResponse.json({ game: { id: game.id, name: game.name } })
  } catch (e) {
    console.error('publish error', e)
    return NextResponse.json({ error: 'Failed to publish game. Try again.' }, { status: 500 })
  }
}

async function fileToDataUrl(file: File): Promise<string> {
  const buf = Buffer.from(await file.arrayBuffer())
  return `data:${file.type || 'image/png'};base64,${buf.toString('base64')}`
}
