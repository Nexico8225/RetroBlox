import { NextResponse } from 'next/server'
import { db } from '@/lib/db'

// Public site stats for the sidebar counter box.
export async function GET() {
  const [games, users, dl, groupCount, labCount, communityCount, videoCount] = await Promise.all([
    db.game.count(),
    db.user.count(),
    db.game.aggregate({ _sum: { downloads: true } }),
    db.group.count(),
    db.labPost.count(),
    db.communityPost.count(),
    db.video.count(),
  ])
  return NextResponse.json({
    games,
    users,
    downloads: dl._sum.downloads || 0,
    groups: groupCount,
    labs: labCount,
    community: communityCount,
    videos: videoCount,
  })
}
