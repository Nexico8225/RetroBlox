import { publicUser } from './auth'

/** Shared shape for video rows sent to the client. */
export function shapeVideo(
  v: {
    id: string
    title: string
    description: string
    fileId: string
    fileName: string | null
    thumbFileId: string | null
    postId?: string | null
    upIds: string
    downIds: string
    views: number
    createdAt: Date
    author: { id: string; username: string; avatarUrl: string | null; lastSeen: Date }
    _count?: { comments: number }
  },
  meId?: string | null
) {
  const ups = JSON.parse(v.upIds || '[]') as string[]
  const downs = JSON.parse(v.downIds || '[]') as string[]
  return {
    id: v.id,
    title: v.title,
    description: v.description,
    fileId: v.fileId,
    fileName: v.fileName,
    thumbFileId: v.thumbFileId,
    postId: v.postId ?? null,
    views: v.views,
    likes: ups.length,
    dislikes: downs.length,
    myVote: meId ? (ups.includes(meId) ? 1 : downs.includes(meId) ? -1 : 0) : 0,
    commentCount: v._count?.comments ?? 0,
    createdAt: v.createdAt,
    author: publicUser(v.author),
  }
}
