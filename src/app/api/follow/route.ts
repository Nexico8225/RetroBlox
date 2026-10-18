import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser } from '@/lib/auth'

// POST /api/follow — { userId } toggles follow, or { userId, action: 'follow'|'unfollow' }
export async function POST(req: NextRequest) {
  const me = await getUserFromReq(req)
  if (!me) return NextResponse.json({ error: 'Login required' }, { status: 401 })

  const body = await req.json()
  const targetId = String(body.userId || '')
  const target = await db.user.findUnique({ where: { id: targetId } })
  if (!target) return NextResponse.json({ error: 'User not found' }, { status: 404 })
  if (target.id === me.id) return NextResponse.json({ error: "You can't follow yourself!" }, { status: 400 })

  const existing = await db.follow.findUnique({
    where: { followerId_followingId: { followerId: me.id, followingId: target.id } },
  })

  const action = String(body.action || (existing ? 'unfollow' : 'follow'))
  if (action === 'follow' && !existing) {
    await db.follow.create({ data: { followerId: me.id, followingId: target.id } })
  } else if (action === 'unfollow' && existing) {
    await db.follow.delete({ where: { id: existing.id } })
  }

  const followers = await db.follow.count({ where: { followingId: target.id } })
  return NextResponse.json({ following: action === 'follow', followers })
}

// GET /api/follow?userId=... — follower / following lists for a profile
export async function GET(req: NextRequest) {
  const me = await getUserFromReq(req)
  const { searchParams } = new URL(req.url)
  const userId = searchParams.get('userId') || ''
  const user = await db.user.findUnique({ where: { id: userId } })
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  const followerRows = await db.follow.findMany({
    where: { followingId: userId },
    include: { follower: true },
    orderBy: { createdAt: 'desc' },
    take: 60,
  })
  const followingRows = await db.follow.findMany({
    where: { followerId: userId },
    include: { following: true },
    orderBy: { createdAt: 'desc' },
    take: 60,
  })

  const isFollowing = me
    ? !!(await db.follow.findUnique({
        where: { followerId_followingId: { followerId: me.id, followingId: userId } },
      }))
    : false

  return NextResponse.json({
    followers: followerRows.map((f) => publicUser(f.follower)),
    following: followingRows.map((f) => publicUser(f.following)),
    isFollowing,
  })
}
