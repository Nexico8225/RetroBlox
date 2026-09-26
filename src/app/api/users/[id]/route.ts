import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser, isOnline } from '@/lib/auth'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const viewer = await getUserFromReq(req)

  const user = await db.user.findUnique({
    where: { id },
    include: {
      games: {
        orderBy: { createdAt: 'desc' },
        include: { likes: true, _count: { select: { comments: true, favorites: true } } },
      },
      memberships: {
        include: { group: { select: { id: true, name: true, iconUrl: true } } },
        orderBy: { joinedAt: 'asc' },
      },
      favorites: { include: { game: { include: { creator: { select: { id: true, username: true, avatarUrl: true } }, likes: true, _count: { select: { comments: true, favorites: true } } } } }, orderBy: { id: 'desc' } },
      videos: {
        include: {
          _count: { select: { comments: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: 24,
      },
      requestsSent: { where: { status: 'accepted' }, select: { addresseeId: true } },
      requestsRecv: { where: { status: 'accepted' }, select: { requesterId: true } },
    },
  })
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  // friendship state between viewer and this user
  let friendState: 'none' | 'friends' | 'request_sent' | 'request_received' = 'none'
  let friendshipId: string | null = null
  if (viewer && viewer.id !== user.id) {
    const f1 = await db.friendship.findUnique({
      where: { requesterId_addresseeId: { requesterId: viewer.id, addresseeId: user.id } },
    })
    const f2 = await db.friendship.findUnique({
      where: { requesterId_addresseeId: { requesterId: user.id, addresseeId: viewer.id } },
    })
    if (f1) {
      friendState = f1.status === 'accepted' ? 'friends' : 'request_sent'
      friendshipId = f1.id
    } else if (f2) {
      friendState = f2.status === 'accepted' ? 'friends' : 'request_received'
      friendshipId = f2.id
    }
  }

  const isMe = viewer?.id === user.id

  // friends are public — you can see who someone is friends with and how many they have
  const friendIds = [...user.requestsSent.map((f) => f.addresseeId), ...user.requestsRecv.map((f) => f.requesterId)]
  const friendUsers = friendIds.length > 0
    ? await db.user.findMany({ where: { id: { in: friendIds } } })
    : []
  const friends = friendUsers
    .map((f) => publicUser(f))
    .sort((a, b) => Number(b.online) - Number(a.online))

  // follows
  const [followersCount, followingCount, followRow, gamesPlayed, playAgg] = await Promise.all([
    db.follow.count({ where: { followingId: user.id } }),
    db.follow.count({ where: { followerId: user.id } }),
    viewer
      ? db.follow.findUnique({ where: { followerId_followingId: { followerId: viewer.id, followingId: user.id } } })
      : Promise.resolve(null),
    db.gamePlay.count({ where: { userId: user.id } }),
    db.gamePlay.aggregate({ where: { userId: user.id }, _sum: { seconds: true } }),
  ])
  const totalPlaySeconds = playAgg._sum.seconds || 0

  const mapGame = (g: NonNullable<typeof user>['games'][number], creatorOverride?: { id: string; username: string; avatarUrl: string | null }) => {
    const likes = g.likes.filter((l) => l.value === 1).length
    const dislikes = g.likes.filter((l) => l.value === -1).length
    return {
      id: g.id,
      name: g.name,
      iconUrl: g.iconUrl,
      thumbnailUrl: g.thumbnailUrl,
      genre: g.genre,
      subgenre: g.subgenre,
      engine: g.engine,
      maturity: g.maturity,
      downloads: g.downloads,
      createdAt: g.createdAt,
      updatedAt: g.updatedAt,
      creator: creatorOverride || { id: user.id, username: user.username, avatarUrl: user.avatarUrl },
      likes,
      dislikes,
      rating: likes + dislikes > 0 ? Math.round((likes / (likes + dislikes)) * 100) : null,
      commentCount: g._count.comments,
      favoriteCount: g._count.favorites,
    }
  }

  const games = user.games.map((g) => mapGame(g))
  const favoriteGames = user.favorites
    .filter((f) => f.game)
    .map((f) => mapGame(f.game, { id: f.game.creator.id, username: f.game.creator.username, avatarUrl: f.game.creator.avatarUrl }))

  const videos = user.videos.map((v) => {
    const ups = JSON.parse(v.upIds || '[]') as string[]
    return {
      id: v.id,
      title: v.title,
      thumbFileId: v.thumbFileId,
      views: v.views,
      likes: ups.length,
      commentCount: v._count.comments,
      createdAt: v.createdAt,
    }
  })

  return NextResponse.json({
    user: {
      ...publicUser(user),
      online: isOnline(user.lastSeen) || isMe,
      birthday: user.birthday,
      gender: user.gender,
    },
    games,
    favoriteGames,
    videos,
    friends,
    followersCount,
    followingCount,
    gamesPlayed,
    totalPlaySeconds,
    isFollowing: !!followRow,
    groups: user.memberships.map((m) => ({
      id: m.group.id,
      name: m.group.name,
      iconUrl: m.group.iconUrl,
      role: m.role,
    })),
    friendState,
    friendshipId,
    isMe,
  })
}
