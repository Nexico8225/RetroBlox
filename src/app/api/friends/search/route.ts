import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getUserFromReq, publicUser, isOnline } from '@/lib/auth'

function getSimilarityScore(username: string, query: string): number {
  const u = username.toLowerCase()
  const q = query.toLowerCase()
  if (u === q) return 1000
  if (u.startsWith(q)) return 600 - (u.length - q.length)
  if (u.includes(q)) return 400 - u.indexOf(q) * 10 - (u.length - q.length)

  // Subsequence matching for typos & close names
  let matchCount = 0
  let lastIdx = -1
  for (const ch of q) {
    const idx = u.indexOf(ch, lastIdx + 1)
    if (idx !== -1) {
      matchCount++
      lastIdx = idx
    }
  }
  const ratio = matchCount / Math.max(q.length, 1)
  if (ratio >= 0.5) {
    return 100 + Math.round(ratio * 150) - Math.abs(u.length - q.length) * 2
  }
  return 0
}

export async function GET(req: NextRequest) {
  const viewer = await getUserFromReq(req)
  const q = req.nextUrl.searchParams.get('q')?.trim() || ''

  if (!q) {
    return NextResponse.json({ results: [] })
  }

  // Find candidate users by partial match or take top recent
  const users = await db.user.findMany({
    where: {
      OR: [
        { username: { contains: q } },
        { usernameLower: { contains: q.toLowerCase() } },
      ],
    },
    take: 40,
    select: {
      id: true,
      username: true,
      seqId: true,
      avatarUrl: true,
      bio: true,
      lastSeen: true,
      createdAt: true,
    },
  })

  // Also check if any users with similar characters exist if candidate count is small
  let allCandidates = [...users]
  if (allCandidates.length < 8 && q.length >= 3) {
    const firstChars = q.slice(0, 2)
    const extra = await db.user.findMany({
      where: {
        username: { contains: firstChars },
        NOT: { id: { in: allCandidates.map((u) => u.id) } },
      },
      take: 20,
      select: {
        id: true,
        username: true,
        seqId: true,
        avatarUrl: true,
        bio: true,
        lastSeen: true,
        createdAt: true,
      },
    })
    allCandidates.push(...extra)
  }

  // Score each candidate
  const scored = allCandidates
    .map((u) => ({
      user: u,
      score: getSimilarityScore(u.username, q),
    }))
    .filter((s) => s.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 20)

  // Retrieve friendship states for viewer
  const candidateIds = scored.map((s) => s.user.id)
  const friendships = viewer && candidateIds.length > 0
    ? await db.friendship.findMany({
        where: {
          OR: [
            { requesterId: viewer.id, addresseeId: { in: candidateIds } },
            { requesterId: { in: candidateIds }, addresseeId: viewer.id },
          ],
        },
      })
    : []

  const results = scored.map(({ user, score }) => {
    let friendState: 'none' | 'friends' | 'request_sent' | 'request_received' = 'none'
    let friendshipId: string | null = null

    if (viewer) {
      const f = friendships.find(
        (row) =>
          (row.requesterId === viewer.id && row.addresseeId === user.id) ||
          (row.requesterId === user.id && row.addresseeId === viewer.id)
      )
      if (f) {
        friendshipId = f.id
        if (f.status === 'accepted') {
          friendState = 'friends'
        } else if (f.requesterId === viewer.id) {
          friendState = 'request_sent'
        } else {
          friendState = 'request_received'
        }
      }
    }

    return {
      id: user.id,
      username: user.username,
      seqId: user.seqId,
      avatarUrl: user.avatarUrl,
      bio: user.bio,
      online: isOnline(user.lastSeen),
      score,
      isMe: viewer?.id === user.id,
      friendState,
      friendshipId,
    }
  })

  return NextResponse.json({ results })
}
