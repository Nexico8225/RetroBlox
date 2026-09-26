'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, fmtDate, fmtCount, timeAgo, flash } from '@/lib/store'
import { FxToolbar, FxText } from '@/lib/textfx'
import { Avatar } from './Shell'
import { mediaRender } from './ChatView'
import { RetroVideoPlayer } from './RetroVideoPlayer'

/* ============ RetroBlox Videos — as close as YouTube, but 2006 ============ */

export interface VideoSummary {
  id: string
  title: string
  description: string
  fileId: string
  fileName: string | null
  thumbFileId: string | null
  views: number
  likes: number
  dislikes: number
  myVote: number
  commentCount: number
  createdAt: string
  author: { id: string; username: string; avatarUrl: string | null; online: boolean; role: string }
}

/* Retro TV fallback thumbnail + red play badge (YouTube-style) */
export function VideoThumb({ video, tall = false }: { video: { thumbFileId?: string | null; title: string }; tall?: boolean }) {
  const [err, setErr] = useState(false)
  const fallback = `data:image/svg+xml;utf8,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="480" height="270"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2c3a4d"/><stop offset="1" stop-color="#16202c"/></linearGradient></defs><rect width="480" height="270" fill="url(#g)"/><rect x="0" y="210" width="480" height="60" fill="#1f2d3d"/><circle cx="240" cy="126" r="46" fill="#e1231a" stroke="#ffffff" stroke-width="5"/><path d="M226 104 L226 148 L266 126 Z" fill="#ffffff"/><rect x="18" y="238" width="60" height="8" rx="4" fill="#3d5266"/><rect x="402" y="238" width="60" height="8" rx="4" fill="#3d5266"/></svg>`
  )}`
  return (
    <div
      style={{
        position: 'relative',
        width: '100%',
        aspectRatio: tall ? '16/9' : '16/9',
        overflow: 'hidden',
        background: '#16202c',
        border: '1px solid #16202c',
      }}
    >
      <img
        src={err || !video.thumbFileId ? fallback : `/api/files/${video.thumbFileId}`}
        alt={video.title}
        onError={() => setErr(true)}
        style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
      />
      <span
        aria-hidden="true"
        style={{
          position: 'absolute',
          inset: 0,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <span
          style={{
            width: 44,
            height: 44,
            borderRadius: '50%',
            background: 'rgba(225,35,26,.88)',
            border: '3px solid #fff',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <svg width="18" height="18" viewBox="0 0 20 20">
            <path d="M6 3 L6 17 L17 10 Z" fill="#fff" />
          </svg>
        </span>
      </span>
    </div>
  )
}

/* ------------ Video card (browse grid / strips / sidebar) ------------ */

export function VideoCard({ video, compact = false }: { video: VideoSummary; compact?: boolean }) {
  if (compact) {
    return (
      <Link
        href={`/videos/${video.id}`}
        className="rb-clickable"
        style={{ display: 'flex', gap: 8, textDecoration: 'none', padding: 5, background: '#fff', border: '1px solid #d5dde5', borderRadius: 3 }}
        aria-label={`Watch ${video.title}`}
      >
        <span style={{ width: 120, flexShrink: 0 }}>
          <VideoThumb video={video} />
        </span>
        <span style={{ flex: 1, minWidth: 0 }}>
          <span
            style={{
              display: '-webkit-box',
              WebkitLineClamp: 2,
              WebkitBoxOrient: 'vertical',
              overflow: 'hidden',
              fontSize: 11,
              color: '#0d69ac',
              lineHeight: 1.35,
            }}
          >
            {video.title}
          </span>
          <span style={{ display: 'block', fontSize: 10, color: '#5a6b7b', marginTop: 3 }}>{video.author.username}</span>
          <span style={{ display: 'block', fontSize: 9, color: '#7b8896', marginTop: 1 }}>
            {fmtCount(video.views)} views · {timeAgo(video.createdAt)}
          </span>
        </span>
      </Link>
    )
  }

  return (
    <Link
      href={`/videos/${video.id}`}
      className="rb-clickable"
      style={{
        textAlign: 'left',
        background: '#fff',
        border: '1px solid #a8b6c2',
        borderRadius: 3,
        padding: 5,
        boxShadow: '1px 1px 0 rgba(0,0,0,.12)',
        display: 'flex',
        flexDirection: 'column',
        gap: 5,
        textDecoration: 'none',
        transition: 'transform 90ms, box-shadow 90ms, border-color 90ms',
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.borderColor = '#e1231a'
        e.currentTarget.style.transform = 'translateY(-2px)'
        e.currentTarget.style.boxShadow = '2px 3px 0 rgba(0,0,0,.16)'
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.borderColor = '#a8b6c2'
        e.currentTarget.style.transform = 'none'
        e.currentTarget.style.boxShadow = '1px 1px 0 rgba(0,0,0,.12)'
      }}
      aria-label={`Watch ${video.title}`}
    >
      <VideoThumb video={video} />
      <div
        style={{
          fontSize: 11,
          color: '#0d69ac',
          lineHeight: 1.35,
          display: '-webkit-box',
          WebkitLineClamp: 2,
          WebkitBoxOrient: 'vertical',
          overflow: 'hidden',
          minHeight: 30,
        }}
      >
        {video.title}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <Avatar user={video.author} size={20} rounded="50%" />
        <span style={{ fontSize: 10, color: '#5a6b7b', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {video.author.username}
        </span>
      </div>
      <div style={{ fontSize: 10, color: '#7b8896' }}>
        {fmtCount(video.views)} views · {timeAgo(video.createdAt)}
      </div>
    </Link>
  )
}

/* ============ /videos — browse ============ */

const SORTS = [
  { key: 'new', label: 'Newest' },
  { key: 'viewed', label: 'Most Viewed' },
  { key: 'liked', label: 'Top Liked' },
]

export function VideosBrowserView({ q, sort, embedded = false }: { q: string; sort: string; embedded?: boolean }) {
  const router = useRouter()
  const { user } = useRetro()
  const [data, setData] = useState<{ videos: VideoSummary[]; key: string } | null>(null)
  const [search, setSearch] = useState(q)

  const key = `${sort}|${q}`
  const loading = !data || data.key !== key
  const videos = data?.key === key ? data.videos : []

  useEffect(() => {
    let cancelled = false
    const params = new URLSearchParams({ sort, limit: '48' })
    if (q) params.set('q', q)
    api<{ videos: VideoSummary[] }>(`/api/videos?${params}`)
      .then((r) => !cancelled && setData({ videos: r.videos, key }))
      .catch(() => !cancelled && setData({ videos: [], key }))
    return () => {
      cancelled = true
    }
  }, [sort, q, key])

  function pushParams(next: { q?: string; sort?: string }) {
    const p = new URLSearchParams()
    const nq = next.q ?? q
    const ns = next.sort ?? sort
    if (nq) p.set('q', nq)
    if (ns && ns !== 'new') p.set('sort', ns)
    // inside the community tab the videos share the community URL space
    router.push(`${embedded ? '/community?tab=videos' : '/videos'}${p.toString() ? `&${p}` : ''}`)
  }

  return (
    <div>
      {embedded ? (
        /* compact search bar when living inside the Community tab */
        <div className="rb-box" style={{ padding: '8px 10px', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 12, color: '#a02018' }}>▶ Player videos</span>
          <form
            onSubmit={(e) => {
              e.preventDefault()
              pushParams({ q: search.trim() })
            }}
            style={{ display: 'flex', flex: 1, minWidth: 140, maxWidth: 300 }}
          >
            <input
              className="rb-input"
              type="search"
              placeholder="Search videos..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ flex: 1, minWidth: 0, borderRadius: '3px 0 0 3px', fontSize: 11 }}
              aria-label="Search videos"
            />
            <button className="rb-btn" type="submit" style={{ borderRadius: '0 3px 3px 0', borderLeft: 'none', fontSize: 11 }}>
              Go
            </button>
          </form>
          {user && (
            <Link className="rb-btn rb-btn-red" href="/community/new?video=1" style={{ textDecoration: 'none', fontSize: 10, padding: '3px 10px', whiteSpace: 'nowrap' }}>
              + Post a Video
            </Link>
          )}
        </div>
      ) : (
      /* hero strip — broadcast yourself, blocky style */
      <div
        className="rb-box"
        style={{
          marginBottom: 12,
          overflow: 'hidden',
          background: 'linear-gradient(180deg,#22303f,#16202c)',
          border: '1px solid #0d1824',
        }}
      >
        <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
          <span
            style={{
              width: 46,
              height: 46,
              borderRadius: 8,
              background: '#e1231a',
              border: '2px solid #fff',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
            }}
          >
            <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
              <path d="M6 3 L6 17 L17 10 Z" fill="#fff" />
            </svg>
          </span>
          <div style={{ flex: 1, minWidth: 180 }}>
            <div style={{ fontSize: 17, color: '#fff', letterSpacing: '-0.5px' }}>RetroBlox Videos</div>
            <div style={{ fontSize: 10, color: '#9fb4c7' }}>Broadcast yourself — upload gameplay, trailers and blocky movies.</div>
          </div>
          <form
            onSubmit={(e) => {
              e.preventDefault()
              pushParams({ q: search.trim() })
            }}
            style={{ display: 'flex', flex: 1, minWidth: 160, maxWidth: 320 }}
          >
            <input
              className="rb-input"
              type="search"
              placeholder="Search videos..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ flex: 1, minWidth: 0, borderRadius: '3px 0 0 3px', fontSize: 11 }}
              aria-label="Search videos"
            />
            <button className="rb-btn" type="submit" style={{ borderRadius: '0 3px 3px 0', borderLeft: 'none', fontSize: 11 }}>
              Search
            </button>
          </form>
          {user && (
            <Link className="rb-btn rb-btn-red" href="/community/new?video=1" style={{ textDecoration: 'none', display: 'inline-block', whiteSpace: 'nowrap' }}>
              + Post a Video
            </Link>
          )}
        </div>
      </div>
      )}

      {/* sort tabs */}
      <div className="rb-box" style={{ padding: '6px 10px', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <span style={{ fontSize: 11, color: '#24425f' }}>Sort by:</span>
        {SORTS.map((s) => (
          <button
            key={s.key}
            onClick={() => pushParams({ sort: s.key })}
            style={{
              fontSize: 11,
              padding: '3px 10px',
              border: '1px solid',
              borderRadius: 3,
              cursor: 'pointer',
              background: sort === s.key ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : '#f4f8fb',
              color: sort === s.key ? '#fff' : '#1c4e7c',
              borderColor: sort === s.key ? '#17456f' : '#b9c6d2',
            }}
          >
            {s.label}
          </button>
        ))}
        <span style={{ marginLeft: 'auto', fontSize: 10, color: '#7b8896' }}>
          {loading ? '...' : `${videos.length} video${videos.length === 1 ? '' : 's'}${q ? ` for "${q}"` : ''}`}
        </span>
      </div>

      {/* grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(210px, 1fr))', gap: 10 }}>
        {loading
          ? Array.from({ length: 8 }).map((_, i) => <div key={i} className="rb-box" style={{ height: 170, background: '#f0f4f8' }} />)
          : videos.map((v) => <VideoCard key={v.id} video={v} />)}
      </div>

      {!loading && videos.length === 0 && (
        <div className="rb-box" style={{ padding: 30, textAlign: 'center', color: '#5a6b7b' }}>
          <div style={{ fontSize: 14, marginBottom: 4 }}>{q ? `No videos match "${q}".` : 'No videos yet.'}</div>
          <div style={{ fontSize: 11, marginBottom: 12 }}>The stage is empty — post the very first video through the community!</div>
          <Link className="rb-btn rb-btn-red" href="/community/new?video=1" style={{ display: 'inline-block', textDecoration: 'none' }}>
            Post a Video
          </Link>
        </div>
      )}
    </div>
  )
}

/* ============ /videos/[id] — watch page ============ */

interface VComment {
  id: string
  text: string
  parentId?: string | null
  authorId: string
  mediaFileId: string | null
  mediaType: string | null
  mediaName: string | null
  createdAt: string
  author: { id: string; username: string; avatarUrl: string | null; role: string }
}

export function VideoWatchView({ id }: { id: string }) {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const [video, setVideo] = useState<VideoSummary | null>(null)
  const [authorJoined, setAuthorJoined] = useState<string | null>(null)
  const [related, setRelated] = useState<VideoSummary[]>([])
  const [isOwner, setIsOwner] = useState(false)
  const [isAdmin, setIsAdmin] = useState(false)
  const [isFollowing, setIsFollowing] = useState(false)
  const [comments, setComments] = useState<VComment[]>([])
  const [commentText, setCommentText] = useState('')
  const commentTaRef = useRef<HTMLTextAreaElement>(null)
  const replyTaRef = useRef<HTMLTextAreaElement>(null)
  const [commentFile, setCommentFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  /* replies: which comment is the reply box open under + the draft text */
  const [replyTo, setReplyTo] = useState<string | null>(null)
  const [replyText, setReplyText] = useState('')
  const [postingReply, setPostingReply] = useState(false)
  const commentFileRef = useRef<HTMLInputElement>(null)

  const load = useCallback(async () => {
    try {
      const [detail, cl] = await Promise.all([
        api<{
          video: VideoSummary
          authorJoined: string
          isOwner: boolean
          isAdmin: boolean
          related: VideoSummary[]
        }>(`/api/videos/${id}`),
        api<{ comments: VComment[] }>(`/api/videos/${id}/comments`),
      ])
      setVideo(detail.video)
      setAuthorJoined(detail.authorJoined)
      setIsOwner(detail.isOwner)
      setIsAdmin(detail.isAdmin)
      setRelated(detail.related)
      setComments(cl.comments)
      setError('')
      if (user && !detail.isOwner) {
        api<{ isFollowing: boolean }>(`/api/follow?userId=${detail.video.author.id}`)
          .then((f) => setIsFollowing(f.isFollowing))
          .catch(() => {})
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Video not found')
    }
  }, [id, user])

  useEffect(() => {
    load()
  }, [load])

  useEffect(() => {
    if (video) document.title = `${video.title} - RetroBlox Videos`
  }, [video])

  /* count one view per session per video (YouTube-ish) */
  useEffect(() => {
    if (!video) return
    const k = `rb_viewed_${id}`
    if (sessionStorage.getItem(k)) return
    sessionStorage.setItem(k, '1')
    api<{ views: number }>(`/api/videos/${id}/view`, { method: 'POST' })
      .then((r) => setVideo((v) => (v ? { ...v, views: r.views } : v)))
      .catch(() => {})
  }, [id, video?.id])

  async function vote(v: 1 | -1) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!video) return
    try {
      const next = video.myVote === v ? 0 : v
      const res = await api<{ likes: number; dislikes: number; myVote: number }>(`/api/videos/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ vote: next }),
      })
      setVideo({ ...video, likes: res.likes, dislikes: res.dislikes, myVote: res.myVote })
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed')
    }
  }

  async function toggleFollow() {
    if (!video) return
    try {
      const res = await api<{ following: boolean }>(`/api/follow?userId=${video.author.id}`, {
        method: 'POST',
        body: JSON.stringify({ userId: video.author.id }),
      })
      setIsFollowing(res.following)
      flash(setToast, res.following ? `Following ${video.author.username}!` : 'Unfollowed.')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed')
    }
  }

  async function postComment() {
    if (!commentText.trim()) return
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('text', commentText.trim())
      if (commentFile) fd.append('file', commentFile)
      const res = await api<{ comment: VComment }>(`/api/videos/${id}/comments`, { method: 'POST', body: fd })
      setComments((cs) => [...cs, res.comment])
      setCommentText('')
      setCommentFile(null)
      setVideo((v) => (v ? { ...v, commentCount: v.commentCount + 1 } : v))
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to comment')
    } finally {
      setBusy(false)
    }
  }

  async function delComment(cid: string) {
    try {
      await api(`/api/videos/${id}/comments/${cid}`, { method: 'DELETE' })
      let removed = 0
      setComments((cs) => cs.filter((c) => {
        const gone = c.id === cid || c.parentId === cid
        if (gone) removed++
        return !gone
      }))
      setVideo((v) => (v ? { ...v, commentCount: Math.max(0, v.commentCount - removed) } : v))
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed')
    }
  }

  async function postReply(parentId: string) {
    if (!replyText.trim()) return
    setPostingReply(true)
    try {
      const fd = new FormData()
      fd.append('text', replyText.trim())
      fd.append('parentId', parentId)
      const res = await api<{ comment: VComment }>(`/api/videos/${id}/comments`, { method: 'POST', body: fd })
      setComments((cs) => [...cs, res.comment])
      setReplyTo(null)
      setReplyText('')
      setVideo((v) => (v ? { ...v, commentCount: v.commentCount + 1 } : v))
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to reply')
    } finally {
      setPostingReply(false)
    }
  }

  async function delVideo() {
    if (!confirm('Delete this video for good?')) return
    try {
      await api(`/api/videos/${id}`, { method: 'DELETE' })
      flash(setToast, 'Video deleted.')
      router.push(isOwner ? `/users/${user?.id}` : '/videos')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed')
    }
  }

  if (error) {
    return (
      <div className="rb-box" style={{ padding: 36, textAlign: 'center', color: '#a81a13' }}>
        {error}
        <div style={{ marginTop: 12 }}>
          <Link className="rb-btn" href="/videos" style={{ textDecoration: 'none', display: 'inline-block' }}>
            Back to Videos
          </Link>
        </div>
      </div>
    )
  }

  if (!video) {
    return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading video...</div>
  }

  const canDelete = isOwner || isAdmin

  return (
    <div>
      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
        {/* main column */}
        <div style={{ flex: '1 1 460px', minWidth: 0 }}>
          <div className="rb-box" style={{ padding: 0, background: '#000', border: '1px solid #0d1824', overflow: 'hidden' }}>
            <RetroVideoPlayer
              src={`/api/files/${video.fileId}`}
              poster={video.thumbFileId ? `/api/files/${video.thumbFileId}` : undefined}
              title={video.title}
            />
          </div>

          <div className="rb-box" style={{ marginTop: 10, padding: 12 }}>
            <h1 style={{ fontSize: 17, color: '#1c2733', margin: 0, lineHeight: 1.35 }}><FxText text={video.title} /></h1>
            <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 4 }}>
              {fmtCount(video.views)} views · Uploaded {fmtDate(video.createdAt)} ({timeAgo(video.createdAt)})
            </div>

            {/* like / dislike bar — YouTube style */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
              <button
                className="rb-btn"
                onClick={() => vote(1)}
                style={{
                  fontSize: 11,
                  background: video.myVote === 1 ? 'linear-gradient(180deg,#dff0dc,#c4e2bd)' : '#f4f8fb',
                  borderColor: video.myVote === 1 ? '#4c9e34' : '#b9c6d2',
                }}
                aria-label="Like this video"
              >
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                  <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true">
                    <path d="M2 7h3v8H2zM6 15h6.5a2 2 0 002-2v-.5l1-4A1.6 1.6 0 0014 6.5h-4l.7-3.2A1.5 1.5 0 009.3 1.5L6 6.5z" fill="#4c9e34" />
                  </svg>
                  {video.likes}
                </span>
              </button>
              <button
                className="rb-btn"
                onClick={() => vote(-1)}
                style={{
                  fontSize: 11,
                  background: video.myVote === -1 ? '#fbe3e0' : '#f4f8fb',
                  borderColor: video.myVote === -1 ? '#c0392b' : '#b9c6d2',
                }}
                aria-label="Dislike this video"
              >
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                  <svg width="12" height="12" viewBox="0 0 16 16" style={{ transform: 'rotate(180deg)' }} aria-hidden="true">
                    <path d="M2 7h3v8H2zM6 15h6.5a2 2 0 002-2v-.5l1-4A1.6 1.6 0 0014 6.5h-4l.7-3.2A1.5 1.5 0 009.3 1.5L6 6.5z" fill="#b04a42" />
                  </svg>
                  {video.dislikes}
                </span>
              </button>
              <span style={{ fontSize: 10, color: '#7b8896', marginLeft: 'auto' }}>
                {video.commentCount} comment{video.commentCount === 1 ? '' : 's'}
              </span>
            </div>
          </div>

          {/* author card — follow + date created */}
          <div className="rb-box" style={{ marginTop: 10, padding: 12, display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
            <Link href={`/users/${video.author.id}`} style={{ display: 'inline-flex', flexShrink: 0 }} aria-label={`${video.author.username}'s profile`}>
              <Avatar user={video.author} size={48} rounded="50%" />
            </Link>
            <div style={{ flex: 1, minWidth: 140 }}>
              <Link href={`/users/${video.author.id}`} className="rb-link" style={{ fontSize: 13, display: 'inline-block' }}>
                {video.author.username}
              </Link>
              {video.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
              <div style={{ fontSize: 10, color: '#7b8896', marginTop: 2 }}>Joined {authorJoined ? fmtDate(authorJoined) : '...'}</div>
            </div>
            {!isOwner && user && (
              <button
                className="rb-btn"
                onClick={toggleFollow}
                style={
                  isFollowing
                    ? { borderColor: '#9aa6b1', color: '#5a6b7b' }
                    : { background: 'linear-gradient(180deg,#8ec9ff,#3f7ad1)', borderColor: '#2b5cab', color: '#fff' }
                }
              >
                {isFollowing ? 'Following ✓' : '+ Follow'}
              </button>
            )}
            {canDelete && (
              <button className="rb-btn rb-btn-red" onClick={delVideo} title={isAdmin && !isOwner ? 'Admin delete' : 'Delete your video'}>
                Delete Video
              </button>
            )}
          </div>

          {/* description */}
          <div className="rb-box" style={{ marginTop: 10, padding: 12 }}>
            <div style={{ fontSize: 11, color: '#24425f', marginBottom: 5 }}>Description</div>
            <div style={{ fontSize: 12, color: '#2c3e50', lineHeight: 1.6, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
              {video.description || 'No description.'}
            </div>
          </div>

          {/* comments */}
          <div className="rb-box" style={{ marginTop: 10 }}>
            <div className="rb-panel-head">
              <span>Comments ({comments.length})</span>
              <span style={{ fontSize: 10, color: '#5a6b7b' }}>be nice, stay blocky</span>
            </div>
            <div style={{ padding: 12, display: 'grid', gap: 10 }}>
              {user ? (
                <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                  <Avatar user={user} size={32} rounded="50%" />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <textarea
                      ref={commentTaRef}
                      className="rb-textarea"
                      value={commentText}
                      onChange={(e) => setCommentText(e.target.value)}
                      rows={2}
                      maxLength={500}
                      placeholder="Add a comment..."
                      style={{ width: '100%' }}
                      aria-label="Write a comment"
                    />
                    <FxToolbar taRef={commentTaRef} value={commentText} onChange={setCommentText} />
                    {commentFile && (
                      <div className="rb-chat-attach-chip" style={{ marginTop: 6 }}>
                        <span>{commentFile.name.length > 28 ? `${commentFile.name.slice(0, 28)}...` : commentFile.name}</span>
                        <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }} onClick={() => setCommentFile(null)}>
                          remove
                        </button>
                      </div>
                    )}
                    <div style={{ display: 'flex', gap: 6, marginTop: 6, flexWrap: 'wrap' }}>
                      <button className="rb-btn rb-btn-green" onClick={postComment} disabled={busy || !commentText.trim()} style={{ fontSize: 11 }}>
                        {busy ? 'Posting...' : 'Comment'}
                      </button>
                      <button
                        type="button"
                        className="rb-btn"
                        style={{ fontSize: 10 }}
                        title="Attach an image"
                        onClick={() => {
                          if (commentFileRef.current) {
                            commentFileRef.current.accept = 'image/*'
                            commentFileRef.current.click()
                          }
                        }}
                      >
                        + Image
                      </button>
                      <button
                        type="button"
                        className="rb-btn"
                        style={{ fontSize: 10 }}
                        title="Attach a video or audio clip"
                        onClick={() => {
                          if (commentFileRef.current) {
                            commentFileRef.current.accept = 'video/*,audio/*'
                            commentFileRef.current.click()
                          }
                        }}
                      >
                        + Media
                      </button>
                      <input
                        ref={commentFileRef}
                        type="file"
                        style={{ display: 'none' }}
                        onChange={(e) => {
                          const f = e.target.files?.[0]
                          if (f) setCommentFile(f)
                          e.target.value = ''
                        }}
                      />
                    </div>
                  </div>
                </div>
              ) : (
                <div style={{ fontSize: 11, color: '#5a6b7b' }}>
                  <Link href="/login" className="rb-link">Log in</Link> to join the comments.
                </div>
              )}

              {comments.length === 0 && <div style={{ fontSize: 11, color: '#7b8896', padding: '6px 0' }}>No comments yet — say something first!</div>}

              {/* threads: top-level comments with their replies nested under them */}
              {comments.filter((c) => !c.parentId).map((c) => {
                const replies = comments.filter((r) => r.parentId === c.id)
                const replyOpen = replyTo === c.id
                return (
                  <div key={c.id} style={{ borderTop: '1px solid #eef2f6', paddingTop: 10 }}>
                    <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                      <Link href={`/users/${c.author.id}`} style={{ flexShrink: 0 }} aria-label={`${c.author.username}'s profile`}>
                        <Avatar user={c.author} size={32} rounded="50%" />
                      </Link>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 11 }}>
                          <Link href={`/users/${c.author.id}`} className="rb-link" style={{ color: '#0d69ac' }}>
                            {c.author.username}
                          </Link>
                          {c.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                          <span style={{ color: '#7b8896', marginLeft: 6 }}>{timeAgo(c.createdAt)}</span>
                        </div>
                        <div style={{ fontSize: 12, color: '#2c3e50', lineHeight: 1.55, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}><FxText text={c.text} /></div>
                        {mediaRender(c.mediaFileId, c.mediaType, c.mediaName)}
                        {user && (
                          <button
                            type="button"
                            className="rb-link"
                            style={{ background: 'none', border: 'none', padding: 0, fontSize: 10, marginTop: 3 }}
                            onClick={() => {
                              setReplyTo(replyOpen ? null : c.id)
                              setReplyText('')
                            }}
                            aria-expanded={replyOpen}
                          >
                            ↩ Reply{replies.length ? ` (${replies.length})` : ''}
                          </button>
                        )}
                      </div>
                      {(user?.id === c.authorId || isAdmin) && (
                        <button className="rb-btn" style={{ fontSize: 9, padding: '2px 7px', flexShrink: 0 }} onClick={() => delComment(c.id)} title="Delete comment">
                          Delete
                        </button>
                      )}
                    </div>

                    {/* replies */}
                    {replies.length > 0 && (
                      <div style={{ marginLeft: 40, marginTop: 8, display: 'grid', gap: 8 }}>
                        {replies.map((r) => (
                          <div key={r.id} style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                            <Link href={`/users/${r.author.id}`} style={{ flexShrink: 0 }} aria-label={`${r.author.username}'s profile`}>
                              <Avatar user={r.author} size={24} rounded="50%" />
                            </Link>
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <div style={{ fontSize: 11 }}>
                                <Link href={`/users/${r.author.id}`} className="rb-link" style={{ color: '#0d69ac' }}>
                                  {r.author.username}
                                </Link>
                                {r.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                                <span style={{ color: '#7b8896', marginLeft: 6 }}>{timeAgo(r.createdAt)}</span>
                              </div>
                              <div style={{ fontSize: 12, color: '#2c3e50', lineHeight: 1.55, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}><FxText text={r.text} /></div>
                              {mediaRender(r.mediaFileId, r.mediaType, r.mediaName)}
                            </div>
                            {(user?.id === r.authorId || isAdmin) && (
                              <button className="rb-btn" style={{ fontSize: 9, padding: '2px 7px', flexShrink: 0 }} onClick={() => delComment(r.id)} title="Delete reply">
                                Delete
                              </button>
                            )}
                          </div>
                        ))}
                      </div>
                    )}

                    {/* inline reply composer */}
                    {replyOpen && user && (
                      <div style={{ marginLeft: 40, marginTop: 8, display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                        <Avatar user={user} size={24} rounded="50%" />
                        <div style={{ flex: 1 }}>
                          <textarea
                            ref={replyTaRef}
                            className="rb-textarea"
                            value={replyText}
                            onChange={(e) => setReplyText(e.target.value)}
                            rows={2}
                            maxLength={500}
                            placeholder={`Replying to ${c.author.username}...`}
                            style={{ width: '100%' }}
                            aria-label="Write a reply"
                            autoFocus
                          />
                          <FxToolbar taRef={replyTaRef} value={replyText} onChange={setReplyText} />
                          <div style={{ display: 'flex', gap: 6, marginTop: 5 }}>
                            <button className="rb-btn rb-btn-green" style={{ fontSize: 10 }} disabled={postingReply || !replyText.trim()} onClick={() => postReply(c.id)}>
                              {postingReply ? 'Posting...' : 'Reply'}
                            </button>
                            <button className="rb-btn" style={{ fontSize: 10 }} onClick={() => { setReplyTo(null); setReplyText('') }}>
                              Cancel
                            </button>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          </div>
        </div>

        {/* related sidebar */}
        <div style={{ flex: '0 1 300px', minWidth: 240, width: '100%' }}>
          <div className="rb-box">
            <div className="rb-panel-head">
              <span>More Videos</span>
              <Link className="rb-link" style={{ fontSize: 11 }} href="/videos">
                Browse &rarr;
              </Link>
            </div>
            <div style={{ padding: 8, display: 'grid', gap: 8 }}>
              {related.length === 0 && <div style={{ fontSize: 10, color: '#7b8896', padding: 4 }}>Nothing else here yet.</div>}
              {related.map((v) => (
                <VideoCard key={v.id} video={v} compact />
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
