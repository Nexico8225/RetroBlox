'use client'

/* ------------------------------------------------------------------
   THE RETROBLOX COMMUNITY — Reddit + YouTube + X.com in one feed:
   - Reddit: r/ communities (default + PLAYER-CREATED), vote arrows,
     flairs, right rail, hot/new/top
   - YouTube: videos uploaded through posts play right in the feed AND
     land on the Videos tab with their own watch page
   - X.com: view counters, quick action bar, share-the-link button
------------------------------------------------------------------ */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useRetro, api, timeAgo, fmtCount, flash, type RetroUser } from '@/lib/store'
import { FxToolbar, FxText } from '@/lib/textfx'
import { Avatar } from './Shell'
import { mediaRender } from './ChatView'
import { CommunitySidebar, SubIcon, useSubs, type SubT } from './CommunitySubs'
import { RetroVideoPlayer } from './RetroVideoPlayer'
import { VideosBrowserView } from './VideosView'

const FLAIRS = ['General', 'Memes', 'Help', 'Finds', 'Off-Topic'] as const

/* r/ name for each default flair (posts in player communities use r/<slug>) */
export function rName(flair: string): string {
  const map: Record<string, string> = {
    General: 'r/general',
    Memes: 'r/memes',
    Help: 'r/help',
    Finds: 'r/finds',
    'Off-Topic': 'r/offtopic',
  }
  return map[flair] || 'r/general'
}

const FLAIR_STYLE: Record<string, { bg: string; fg: string; border: string }> = {
  General: { bg: '#eef3f8', fg: '#3d566e', border: '#b4c2cf' },
  Memes: { bg: '#fdf3d7', fg: '#8a6d1a', border: '#d9c26a' },
  Help: { bg: '#e8f5e4', fg: '#2c6e31', border: '#9fce93' },
  Finds: { bg: '#e9e4f5', fg: '#5e3f9e', border: '#b9a6e3' },
  'Off-Topic': { bg: '#fbeaea', fg: '#a03a34', border: '#e0a9a5' },
}

function Flair({ name }: { name: string }) {
  const s = FLAIR_STYLE[name] || FLAIR_STYLE.General
  return (
    <span style={{ fontSize: 9, padding: '1px 7px', borderRadius: 8, background: s.bg, color: s.fg, border: `1px solid ${s.border}` }}>
      {name}
    </span>
  )
}

/* the r/ chip that appears on every post — default flair or player community */
function SubChip({ post }: { post: { flair: string; sub?: CommunityPostT['sub'] } }) {
  if (post.sub) {
    return (
      <Link
        href={`/community?r=${encodeURIComponent(`r/${post.sub.slug}`)}`}
        style={{
          display: 'inline-flex', alignItems: 'center', gap: 4, textDecoration: 'none',
        }}
      >
        <SubIcon sub={post.sub} size={14} />
        <span style={{ fontSize: 10, color: '#1c4e7c' }}>r/{post.sub.slug}</span>
      </Link>
    )
  }
  return (
    <Link href={`/community?r=${encodeURIComponent(rName(post.flair))}`} className="rb-link" style={{ fontSize: 10, color: '#1c4e7c' }}>
      {rName(post.flair)}
    </Link>
  )
}

/* ---------------- shared bits ---------------- */

export function VoteArrows({
  ups, downs, score, myVote, onVote, disabled, dark,
}: {
  ups: number
  downs: number
  score: number
  myVote: number
  onVote: (v: number) => void
  disabled?: boolean
  dark?: boolean
}) {
  const arrow = (up: boolean, active: boolean) => (
    <svg width="16" height="12" viewBox="0 0 16 12" aria-hidden="true">
      <path
        d={up ? 'M8 1l6 8H2z' : 'M8 11L2 3h12z'}
        fill={active ? (up ? '#e07b00' : '#5a7b9a') : dark ? '#3d4a5a' : '#c3cdd7'}
        stroke={active ? (up ? '#a35a00' : '#3d566e') : dark ? '#2c3644' : '#a8b6c2'}
        strokeWidth="1"
      />
    </svg>
  )
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, width: 42, flexShrink: 0, paddingTop: 4 }}>
      <button className="rb-clickable" style={{ background: 'none', border: 'none', padding: 2 }} onClick={() => onVote(1)} disabled={disabled} aria-label="Upvote" title="Upvote">
        {arrow(true, myVote === 1)}
      </button>
      <span style={{ fontSize: 13, color: score > 0 ? '#c2570e' : score < 0 ? '#3d566e' : dark ? '#8fa0b3' : '#5a6b7b' }}>{score}</span>
      <button className="rb-clickable" style={{ background: 'none', border: 'none', padding: 2 }} onClick={() => onVote(-1)} disabled={disabled} aria-label="Downvote" title="Downvote">
        {arrow(false, myVote === -1)}
      </button>
      <span style={{ fontSize: 8, color: dark ? '#55647a' : '#a8b6c2' }}>{ups}↑ {downs}↓</span>
    </div>
  )
}

/* X.com-style quick action bar under every feed card */
function ActionBar({
  comments, extra, onComments, href, dark,
}: {
  comments: number
  extra?: React.ReactNode
  onComments?: () => void
  href?: string
  dark?: boolean
}) {
  const { setToast } = useRetro()
  const c = dark ? '#8fa0b3' : '#7b8896'
  const item = {
    display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11, color: c,
    background: 'none', border: 'none', padding: 0, cursor: 'pointer',
  }
  return (
    <div style={{ marginTop: 10, fontSize: 11, color: c, display: 'flex', gap: 18, alignItems: 'center', flexWrap: 'wrap' }}>
      {href ? (
        <Link href={href} className="rb-clickable" style={{ ...item, textDecoration: 'none' }} aria-label="Comments">
          <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><path d="M2 2h12v8H6l-3 3v-3H2z" fill="none" stroke={c} strokeWidth="1.3" /></svg>
          {comments} comment{comments === 1 ? '' : 's'}
        </Link>
      ) : (
        <button type="button" style={item} onClick={onComments} aria-label="Comments">
          <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M2 2h12v8H6l-3 3v-3H2z" fill="none" stroke={c} strokeWidth="1.3" /></svg>
          {comments} comment{comments === 1 ? '' : 's'}
        </button>
      )}
      {extra}
      <button
        type="button"
        style={item}
        onClick={() => {
          const url = href ? `${window.location.origin}${href}` : window.location.href
          navigator.clipboard?.writeText(url).then(
            () => flash(setToast, 'Link copied — share it anywhere!', 2000),
            () => flash(setToast, url, 2600),
          )
        }}
        aria-label="Share — copy link"
        title="Copy link"
      >
        <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M6 10l4-4M5 7L3.5 8.5a2.5 2.5 0 010 3.5l.5.5a2.5 2.5 0 003.5 0L9 11M11 9l1.5-1.5a2.5 2.5 0 000-3.5L12 3.5a2.5 2.5 0 00-3.5 0L7 5" fill="none" stroke={c} strokeWidth="1.3" strokeLinecap="round" /></svg>
        Share
      </button>
    </div>
  )
}

/* ---------------- types ---------------- */

interface CommunityPostT {
  id: string
  title: string
  body: string
  flair: string
  sub?: { id: string; slug: string; name: string; color: string; iconFileId: string | null } | null
  mediaFileId?: string | null
  mediaType?: string | null
  mediaName?: string | null
  videoId?: string | null
  author: { id: string; username: string; avatarUrl: string | null; role: string }
  createdAt: string
  ups: number
  downs: number
  score: number
  myVote: number
  commentCount?: number
  comments?: CommunityCommentT[]
}

interface CommunityCommentT {
  id: string
  text: string
  parentId?: string | null
  createdAt: string
  likeIds?: string
  likes?: number
  myLike?: boolean
  mediaFileId?: string | null
  mediaType?: string | null
  mediaName?: string | null
  author: RetroUser
}

interface VideoT {
  id: string
  title: string
  description: string
  fileId?: string
  thumbFileId?: string | null
  postId?: string | null
  views: number
  likes: number
  dislikes: number
  score?: number
  myVote?: number
  commentCount: number
  author: { id: string; username: string; avatarUrl: string | null }
  createdAt: string
}

type FeedItem = { kind: 'post'; at: number; rank: number; post: CommunityPostT } | { kind: 'video'; at: number; rank: number; video: VideoT }

/* Inline playable video (YouTube-style, right in the feed) */
function FeedVideoPlayer({ video }: { video: VideoT }) {
  const [playing, setPlaying] = useState(false)
  if (!playing) {
    return (
      <button
        type="button"
        className="rb-clickable"
        onClick={() => setPlaying(true)}
        aria-label={`Play ${video.title}`}
        style={{ display: 'block', width: '100%', maxWidth: 520, padding: 0, border: '1px solid #c3cdd7', borderRadius: 6, overflow: 'hidden', background: '#000', cursor: 'pointer', position: 'relative', marginTop: 8 }}
      >
        {video.thumbFileId ? (
          <img src={`/api/files/${video.thumbFileId}`} alt={video.title} style={{ display: 'block', width: '100%', aspectRatio: '16/9', objectFit: 'cover' }} />
        ) : (
          <div style={{ width: '100%', aspectRatio: '16/9', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'linear-gradient(160deg,#12233a,#1c3a5c)' }}>
            <span style={{ fontFamily: "'Courier New', monospace", color: '#7fd4ff', fontSize: 12 }}>▶ RETROBLOX VIDEO</span>
          </div>
        )}
        <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }} aria-hidden="true">
          <span style={{ width: 52, height: 38, background: 'rgba(200,28,20,.92)', borderRadius: 9, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 10px rgba(0,0,0,.5)' }}>
            <svg width="18" height="18" viewBox="0 0 16 16"><path d="M4 2.5l9 5.5-9 5.5z" fill="#fff" /></svg>
          </span>
        </span>
      </button>
    )
  }
  return (
    <div style={{ maxWidth: 640 }}>
      <RetroVideoPlayer src={`/api/files/${video.fileId || ''}`} poster={video.thumbFileId ? `/api/files/${video.thumbFileId}` : undefined} title={video.title} autoPlay />
    </div>
  )
}

/* small inline video chip for post-attached videos: plays right here too */
function FeedVideoMini({ id, name }: { id: string; name?: string | null }) {
  const [playing, setPlaying] = useState(false)
  if (playing) {
    return (
      <div style={{ marginTop: 8, maxWidth: 480 }}>
        <RetroVideoPlayer src={`/api/files/${id}`} title={name || 'Attached video'} autoPlay />
      </div>
    )
  }
  return (
    <button
      type="button"
      className="rb-clickable"
      onClick={() => setPlaying(true)}
      style={{ marginTop: 8, display: 'inline-flex', alignItems: 'center', gap: 7, fontSize: 10, color: '#24425f', border: '1px solid #c3cdd7', borderRadius: 5, padding: '7px 12px', background: '#f4f8fb', cursor: 'pointer' }}
      aria-label="Play attached video"
    >
      <span style={{ width: 26, height: 19, background: '#c81c14', borderRadius: 4, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <svg width="9" height="9" viewBox="0 0 16 16"><path d="M4 2.5l9 5.5-9 5.5z" fill="#fff" /></svg>
      </span>
      Watch video right here {name ? `· ${name.slice(0, 24)}` : ''}
    </button>
  )
}

/* ================= Community feed (/community) ================= */

export function CommunityView() {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const search = useSearchParams()
  const r = search.get('r') || 'r/all'
  const q = search.get('q') || ''
  const tab = search.get('tab') === 'videos' ? 'videos' : 'posts'
  const [posts, setPosts] = useState<CommunityPostT[]>([])
  const [videos, setVideos] = useState<VideoT[]>([])
  const [sort, setSort] = useState<'hot' | 'new' | 'top'>('hot')
  const [loading, setLoading] = useState(true)
  const [searchBox, setSearchBox] = useState(q)
  const { subs } = useSubs()

  const activeSlug = r.startsWith('r/') && !['r/all', 'r/videos'].includes(r) ? r.slice(2) : ''
  const activeSub = subs.find((s) => s.slug === activeSlug)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const isCustomSub = r.startsWith('r/') && !['r/all', 'r/videos', 'r/general', 'r/memes', 'r/help', 'r/finds', 'r/offtopic'].includes(r)
      const params = new URLSearchParams({ sort })
      if (q) params.set('q', q)
      let postsPromise: Promise<{ posts: CommunityPostT[] }>
      if (isCustomSub) {
        params.set('sub', r.slice(2))
        postsPromise = api<{ posts: CommunityPostT[] }>(`/api/community?${params}`)
      } else {
        const flair = ['r/general', 'r/memes', 'r/help', 'r/finds', 'r/offtopic'].includes(r) ? r.slice(2) : ''
        if (flair) params.set('flair', flair)
        postsPromise = api<{ posts: CommunityPostT[] }>(`/api/community?${params}`)
      }
      // videos mix into r/all and r/videos (and search results)
      const wantVideos = ['r/all', 'r/videos'].includes(r) || (q !== '' && !isCustomSub)
      const [pRes, vRes] = await Promise.all([
        postsPromise,
        wantVideos ? api<{ videos: VideoT[] }>('/api/videos?limit=30') : Promise.resolve({ videos: [] as VideoT[] }),
      ])
      // when searching, keep only videos whose title/description/author match too
      const needle = q.trim().toLowerCase()
      const matchedVideos = needle
        ? vRes.videos.filter(
            (v) =>
              v.title.toLowerCase().includes(needle) ||
              v.description.toLowerCase().includes(needle) ||
              v.author.username.toLowerCase().includes(needle),
          )
        : vRes.videos
      setPosts(pRes.posts)
      setVideos(matchedVideos)
    } catch {
      setPosts([])
      setVideos([])
    } finally {
      setLoading(false)
    }
  }, [sort, r, q])

  useEffect(() => {
    load()
  }, [load])

  useEffect(() => {
    setSearchBox(q)
  }, [q])

  const feed: FeedItem[] = useMemo(() => {
    const items: FeedItem[] = []
    for (const p of posts) items.push({ kind: 'post', at: new Date(p.createdAt).getTime(), rank: p.score, post: p })
    for (const v of videos) {
      // a video that was uploaded through a post in THIS feed is already shown
      // inside its post card — don't render the same clip twice
      if (v.postId && posts.some((p) => p.id === v.postId && p.mediaFileId)) continue
      const score = (v.likes || 0) - (v.dislikes || 0)
      items.push({ kind: 'video', at: new Date(v.createdAt).getTime(), rank: score, video: { ...v, score } })
    }
    if (sort === 'new') items.sort((a, b) => b.at - a.at)
    else if (sort === 'top') items.sort((a, b) => b.rank - a.rank)
    else {
      const hot = (it: FeedItem) => it.rank / Math.pow((Date.now() - it.at) / 3600000 + 2, 1.4)
      items.sort((a, b) => hot(b) - hot(a))
    }
    return items
  }, [posts, videos, sort])

  const trending = useMemo(
    () =>
      [...posts]
        .sort((a, b) => b.score - a.score)
        .slice(0, 4)
        .map((p) => ({ title: p.title, href: `/community/${p.id}`, score: p.score })),
    [posts],
  )

  function pushFilter(next: { r?: string; q?: string }) {
    const p = new URLSearchParams()
    const nr = next.r ?? r
    const nq = next.q ?? q
    if (nr && nr !== 'r/all') p.set('r', nr)
    if (nq) p.set('q', nq)
    if (tab === 'videos') p.set('tab', 'videos')
    router.push(`/community${p.toString() ? `?${p}` : ''}`)
  }

  function switchTab(t: 'posts' | 'videos') {
    const p = new URLSearchParams()
    if (r && r !== 'r/all') p.set('r', r)
    if (q) p.set('q', q)
    if (t === 'videos') p.set('tab', 'videos')
    router.push(`/community${p.toString() ? `?${p}` : ''}`)
  }

  /* the big Posts | Videos switcher — videos live INSIDE the community tab now */
  const tabBar = (
    <div className="rb-box" style={{ padding: 0, overflow: 'hidden' }}>
      <div style={{ display: 'flex' }}>
        <button
          type="button"
          onClick={() => switchTab('posts')}
          aria-pressed={tab === 'posts'}
          style={{
            flex: 1,
            textAlign: 'center',
            padding: '12px 8px',
            background: tab === 'posts' ? '#e3edf7' : 'transparent',
            border: 'none',
            borderBottom: tab === 'posts' ? '2px solid #2f7bc0' : '2px solid transparent',
            fontSize: 13,
            color: tab === 'posts' ? '#0a4f82' : '#5a6b7b',
            cursor: 'pointer',
          }}
        >
          ▤ Posts
        </button>
        <button
          type="button"
          onClick={() => switchTab('videos')}
          aria-pressed={tab === 'videos'}
          style={{
            flex: 1,
            textAlign: 'center',
            padding: '12px 8px',
            background: tab === 'videos' ? '#f9e5e3' : 'transparent',
            border: 'none',
            borderLeft: '1px solid #e4eaf0',
            borderBottom: tab === 'videos' ? '2px solid #e1231a' : '2px solid transparent',
            fontSize: 13,
            color: tab === 'videos' ? '#a02018' : '#5a6b7b',
            cursor: 'pointer',
          }}
        >
          ▶ Videos
        </button>
      </div>
    </div>
  )

  async function votePost(post: CommunityPostT, value: 1 | -1) {
    if (!user) {
      router.push('/login')
      return
    }
    try {
      const res = await api<{ ups: number; downs: number; score: number; myVote: number }>(`/api/community/${post.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ value }),
      })
      setPosts((ps) => ps.map((p) => (p.id === post.id ? { ...p, ...res } : p)))
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Vote failed', 2200)
    }
  }

  async function voteVideo(video: VideoT, value: 1 | -1) {
    if (!user) {
      router.push('/login')
      return
    }
    try {
      const current = video.myVote || 0
      const next = current === value ? 0 : value
      const res = await api<{ likes: number; dislikes: number; myVote: number }>(`/api/videos/${video.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ vote: next }),
      })
      setVideos((vs) =>
        vs.map((v) => (v.id === video.id ? { ...v, likes: res.likes, dislikes: res.dislikes, myVote: res.myVote, score: res.likes - res.dislikes } : v)),
      )
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Vote failed', 2200)
    }
  }

  const heading =
    r === 'r/all'
      ? 'r/all — the RetroBlox lounge'
      : r === 'r/videos'
        ? 'r/videos — player uploads'
        : activeSub
          ? `r/${activeSub.slug}${activeSub.name !== activeSub.slug ? ` — ${activeSub.name}` : ''}`
          : r

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      {tab === 'videos' ? (
        /* -------- VIDEOS TAB — same tab as the community -------- */
        <div style={{ flex: 1, minWidth: 280, display: 'grid', gap: 14 }}>
          {tabBar}
          <VideosBrowserView q={q} sort="new" embedded />
        </div>
      ) : (
      /* -------- POSTS TAB -------- */
      <div style={{ flex: 1, minWidth: 280, display: 'grid', gap: 14, alignContent: 'start' }}>
        {tabBar}
        {/* reddit-style header bar: title + search + actions */}
        <div className="rb-box" style={{ padding: 0, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '12px 14px', flexWrap: 'wrap' }}>
            <span style={{ fontSize: 15, color: '#1c2733' }}>{heading}</span>
            <form
              onSubmit={(e) => {
                e.preventDefault()
                pushFilter({ q: searchBox.trim() })
              }}
              style={{ display: 'flex', flex: 1, minWidth: 140, maxWidth: 260, marginLeft: 'auto' }}
            >
              <input
                className="rb-input"
                type="search"
                placeholder="Search the lounge..."
                value={searchBox}
                onChange={(e) => setSearchBox(e.target.value)}
                style={{ flex: 1, minWidth: 0, borderRadius: '3px 0 0 3px', fontSize: 11 }}
                aria-label="Search community posts"
              />
              <button className="rb-btn" type="submit" style={{ borderRadius: '0 3px 3px 0', borderLeft: 'none', fontSize: 11 }}>
                Go
              </button>
            </form>
            <Link className="rb-btn rb-btn-green" href="/community/new" style={{ fontSize: 10, padding: '3px 10px', textDecoration: 'none', whiteSpace: 'nowrap' }}>
              + New Post
            </Link>
            <Link className="rb-btn" href="/subs" style={{ fontSize: 10, padding: '3px 10px', textDecoration: 'none', whiteSpace: 'nowrap' }}>
              Communities
            </Link>
          </div>
          <div style={{ display: 'flex', borderTop: '1px solid #e4eaf0', alignItems: 'center', flexWrap: 'wrap' }}>
            {(['hot', 'new', 'top'] as const).map((s) => (
              <button
                key={s}
                type="button"
                className="rb-clickable"
                onClick={() => setSort(s)}
                style={{
                  flex: 1, textAlign: 'center', padding: '10px 6px', background: sort === s ? '#e3edf7' : 'transparent',
                  border: 'none', borderBottom: sort === s ? '2px solid #2f7bc0' : '2px solid transparent',
                  fontSize: 12, color: sort === s ? '#0a4f82' : '#5a6b7b', textTransform: 'capitalize', cursor: 'pointer',
                }}
                aria-pressed={sort === s}
              >
                {s === 'hot' ? '🔥 Hot' : s === 'new' ? '✦ New' : '★ Top'}
              </button>
            ))}
            {(q || r !== 'r/all') && (
              <button
                type="button"
                className="rb-clickable"
                onClick={() => router.push('/community')}
                style={{ fontSize: 10, color: '#a03a34', background: 'none', border: 'none', padding: '4px 10px', cursor: 'pointer' }}
                title="Clear search + filters"
              >
                ✕ clear
              </button>
            )}
          </div>
        </div>

        {loading && (
          <div style={{ display: 'grid', gap: 8 }} aria-label="Loading">
            {[0, 1, 2].map((i) => (
              <div key={i} className="rb-box rb-skeleton" style={{ padding: 14, display: 'flex', gap: 10 }}>
                <span className="rb-skel-block" style={{ width: 36, height: 52 }} />
                <span style={{ flex: 1, display: 'grid', gap: 6 }}>
                  <span className="rb-skel-block" style={{ width: '40%', height: 9 }} />
                  <span className="rb-skel-block" style={{ width: '85%', height: 12 }} />
                  <span className="rb-skel-block" style={{ width: '65%', height: 9 }} />
                </span>
              </div>
            ))}
          </div>
        )}

        {!loading && feed.length === 0 && (
          <div className="rb-box" style={{ padding: '40px 20px', textAlign: 'center', color: '#5a6b7b' }}>
            <div style={{ fontSize: 15, marginBottom: 6 }}>
              {q ? `Nothing matches "${q}"` : `Nothing here yet`}
            </div>
            <div style={{ fontSize: 11, marginBottom: 12 }}>
              {q ? 'Try a different search — or start the conversation yourself!' : `Kick off ${r === 'r/all' ? 'the lounge' : r} with the first post or video!`}
            </div>
            <div style={{ display: 'flex', gap: 8, justifyContent: 'center', flexWrap: 'wrap' }}>
              <Link className="rb-btn rb-btn-green" href="/community/new" style={{ textDecoration: 'none', display: 'inline-block' }}>Write a post</Link>
              <Link className="rb-btn" href="/community/new?video=1" style={{ textDecoration: 'none', display: 'inline-block' }}>Post a video</Link>
            </div>
          </div>
        )}

        {!loading &&
          feed.map((it) =>
            it.kind === 'post' ? (
              /* ---------------- Reddit-style post card ---------------- */
              <div key={it.post.id} className="rb-box rb-feed-card" style={{ padding: '12px 14px', display: 'flex', gap: 12 }}>
                <VoteArrows ups={it.post.ups} downs={it.post.downs} score={it.post.score} myVote={it.post.myVote} onVote={(v) => votePost(it.post, v as 1 | -1)} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 11, color: '#7b8896', marginBottom: 5, display: 'flex', gap: 5, alignItems: 'center', flexWrap: 'wrap' }}>
                    <SubChip post={it.post} />
                    <span>· posted by</span>
                    <Link href={`/users/${it.post.author.id}`} className="rb-link" style={{ fontSize: 11 }}>u/{it.post.author.username}</Link>
                    {it.post.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                    <span>· {timeAgo(it.post.createdAt)}</span>
                  </div>
                  <Link href={`/community/${it.post.id}`} className="rb-link" style={{ fontSize: 15, display: 'block', lineHeight: 1.35 }}>
                    <FxText text={it.post.title} />
                  </Link>
                  {it.post.body && (
                    <div style={{ fontSize: 12, color: '#5a6b7b', marginTop: 5, lineHeight: 1.55, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
                      {it.post.body}
                    </div>
                  )}
                  {it.post.mediaFileId && it.post.mediaType === 'image' && (
                    <img
                      src={`/api/files/${it.post.mediaFileId}`}
                      alt={it.post.mediaName || 'picture'}
                      style={{ marginTop: 6, maxHeight: 260, maxWidth: '100%', border: '1px solid #c3cdd7', borderRadius: 4, display: 'block', objectFit: 'cover' }}
                    />
                  )}
                  {it.post.mediaFileId && it.post.mediaType === 'video' && <FeedVideoMini id={it.post.mediaFileId} name={it.post.mediaName} />}
                  <ActionBar
                    comments={it.post.commentCount ?? 0}
                    href={`/community/${it.post.id}`}
                    extra={
                      <>
                        {it.post.videoId && (
                          <Link href={`/videos/${it.post.videoId}`} className="rb-link" style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10 }}>
                            <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 3.5h10v9H3z" fill="none" stroke="#c81c14" strokeWidth="1.3" /><path d="M6.5 6l3.5 2-3.5 2z" fill="#c81c14" /></svg>
                            watch page
                          </Link>
                        )}
                        <Flair name={it.post.flair} />
                      </>
                    }
                  />
                </div>
              </div>
            ) : (
              /* ---------------- YouTube-in-Reddit video card ---------------- */
              <div key={it.video.id} className="rb-box rb-feed-card" style={{ padding: '12px 14px', display: 'flex', gap: 12 }}>
                <VoteArrows ups={it.video.likes} downs={it.video.dislikes} score={it.video.score || 0} myVote={it.video.myVote || 0} onVote={(v) => voteVideo(it.video, v as 1 | -1)} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 11, color: '#7b8896', marginBottom: 5, display: 'flex', gap: 5, alignItems: 'center', flexWrap: 'wrap' }}>
                    <Link href="/community?r=r%2Fvideos" className="rb-link" style={{ fontSize: 11, color: '#1c4e7c' }}>r/videos</Link>
                    <span>· posted by</span>
                    <Link href={`/users/${it.video.author.id}`} className="rb-link" style={{ fontSize: 11 }}>u/{it.video.author.username}</Link>
                    <span>· {timeAgo(it.video.createdAt)}</span>
                  </div>
                  <Link href={`/videos/${it.video.id}`} className="rb-link" style={{ fontSize: 15, display: 'block', lineHeight: 1.35 }}>
                    {it.video.title}
                  </Link>
                  {it.video.description && (
                    <div style={{ fontSize: 12, color: '#5a6b7b', marginTop: 5, lineHeight: 1.55, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
                      {it.video.description}
                    </div>
                  )}
                  <FeedVideoPlayer video={it.video} />
                  <ActionBar
                    comments={it.video.commentCount}
                    href={`/videos/${it.video.id}`}
                    extra={
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10, color: '#7b8896' }}>
                        <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M1.5 8s2.5-4 6.5-4 6.5 4 6.5 4-2.5 4-6.5 4-6.5-4-6.5-4z" fill="none" stroke="#7b8896" strokeWidth="1.3" /><circle cx="8" cy="8" r="1.7" fill="#7b8896" /></svg>
                        {fmtCount(it.video.views)} views
                      </span>
                    }
                  />
                </div>
              </div>
            ),
          )}
      </div>
      )
      }

      {/* --------------- reddit-style right rail --------------- */}
      <CommunitySidebar active={r} trending={trending} />
    </div>
  )
}

/* ================= New community post (/community/new) ================= */

export function CommunityNewView() {
  const { setToast } = useRetro()
  const router = useRouter()
  const search = useSearchParams()
  const { subs, loaded: subsLoaded } = useSubs()

  const preSub = search.get('sub') || ''
  const hintVideo = search.get('video') === '1'

  const [target, setTarget] = useState<string>(preSub ? `sub:${preSub}` : 'flair:General')
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [mediaFile, setMediaFile] = useState<File | null>(null)
  const [mediaPreview, setMediaPreview] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const mediaRef = useRef<HTMLInputElement>(null)
  const mediaSectionRef = useRef<HTMLDivElement>(null)
  const bodyTaRef = useRef<HTMLTextAreaElement>(null)
  const titleTaRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (hintVideo && mediaSectionRef.current) {
      mediaSectionRef.current.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
  }, [hintVideo])

  const targetFlair = target.startsWith('flair:') ? target.slice(6) : ''
  const targetSubSlug = target.startsWith('sub:') ? target.slice(4) : ''
  const targetSub = subs.find((s) => s.slug === targetSubSlug)
  const postLabel = targetSub ? `r/${targetSub.slug}` : `r/${(targetFlair || 'General').toLowerCase()}`

  async function submit(e?: React.FormEvent) {
    e?.preventDefault()
    setError('')
    if (title.trim().length < 5) {
      setError('Title must be at least 5 characters.')
      return
    }
    if (!body.trim() && !mediaFile) {
      setError('Write something or attach a picture / video!')
      return
    }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('title', title.trim())
      fd.append('body', body.trim())
      if (targetSub) {
        fd.append('subSlug', targetSub.slug)
        fd.append('flair', 'General')
      } else {
        fd.append('flair', targetFlair || 'General')
      }
      if (mediaFile) fd.append('mediaFile', mediaFile)
      const res = await api<{ post: { id: string; videoId: string | null } }>('/api/community', { method: 'POST', body: fd })
      flash(setToast, res.post.videoId ? 'Posted! It also landed on the Videos tab.' : 'Posted!', 2600)
      router.push(`/community/${res.post.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to post')
      setBusy(false)
    }
  }

  const labelStyle = { fontSize: 11, color: '#24425f', display: 'block', marginBottom: 4 }

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      <form className="rb-box" style={{ flex: 1, minWidth: 280, maxWidth: 700, padding: 0 }} onSubmit={submit}>
        <div className="rb-panel-head">
          <span>Create a post in {postLabel}</span>
          <span style={{ fontSize: 10, color: '#5a6b7b' }}>for players, by players</span>
        </div>
        <div style={{ padding: 12, display: 'grid', gap: 11 }}>
          {error && (
            <div role="alert" style={{ background: '#fdebe9', border: '1px solid #e1231a', color: '#a81a13', fontSize: 11, padding: '7px 10px', borderRadius: 3 }}>
              {error}
            </div>
          )}
          <div>
            <label style={labelStyle}>Pick your r/ community</label>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {FLAIRS.map((f) => (
                <button
                  key={f}
                  type="button"
                  onClick={() => setTarget(`flair:${f}`)}
                  className="rb-clickable"
                  style={{
                    fontSize: 11, padding: '4px 12px', borderRadius: 12, cursor: 'pointer',
                    border: `1px solid ${target === `flair:${f}` ? FLAIR_STYLE[f].border : '#c3cdd7'}`,
                    background: target === `flair:${f}` ? FLAIR_STYLE[f].bg : '#fff',
                    color: FLAIR_STYLE[f].fg,
                  }}
                  aria-pressed={target === `flair:${f}`}
                >
                  r/{f.toLowerCase()}
                </button>
              ))}
              {subsLoaded &&
                subs.map((s) => (
                  <button
                    key={s.id}
                    type="button"
                    onClick={() => setTarget(`sub:${s.slug}`)}
                    className="rb-clickable"
                    style={{
                      display: 'inline-flex', alignItems: 'center', gap: 5,
                      fontSize: 11, padding: '3px 12px 3px 4px', borderRadius: 12, cursor: 'pointer',
                      border: `1px solid ${target === `sub:${s.slug}` ? s.color : '#c3cdd7'}`,
                      background: target === `sub:${s.slug}` ? '#e3edf7' : '#fff',
                      color: '#1c4e7c',
                    }}
                    aria-pressed={target === `sub:${s.slug}`}
                  >
                    <SubIcon sub={s} size={18} />
                    r/{s.slug}
                  </button>
                ))}
              <Link
                href="/subs/new"
                className="rb-clickable"
                style={{ fontSize: 11, padding: '4px 12px', borderRadius: 12, border: '1px dashed #b4c2cf', color: '#5a6b7b', textDecoration: 'none', display: 'inline-flex', alignItems: 'center', gap: 4 }}
              >
                + new community
              </Link>
            </div>
          </div>
          <div>
            <label style={labelStyle} htmlFor="cp-title">Title *</label>
            <input id="cp-title" ref={titleTaRef} className="rb-input" style={{ width: '100%' }} value={title} onChange={(e) => setTitle(e.target.value)} maxLength={120} placeholder="Say something nice..." />
            <FxToolbar taRef={titleTaRef} value={title} onChange={setTitle} />
          </div>
          <div>
            <label style={labelStyle} htmlFor="cp-body">Text</label>
            <textarea id="cp-body" ref={bodyTaRef} className="rb-textarea" style={{ width: '100%' }} rows={6} value={body} onChange={(e) => setBody(e.target.value)} maxLength={10000} placeholder="What do you want to tell the lounge?" />
            <FxToolbar taRef={bodyTaRef} value={body} onChange={setBody} />
          </div>
          <div ref={mediaSectionRef}>
            <label style={labelStyle}>Picture / video (optional) — upload it straight away, no links</label>
            <input
              ref={mediaRef}
              type="file"
              accept="image/*,video/*"
              style={{ display: 'none' }}
              onChange={(e) => {
                const f = e.target.files?.[0] || null
                setMediaFile(f)
                setMediaPreview(f && f.type.startsWith('image/') ? URL.createObjectURL(f) : null)
                e.target.value = ''
              }}
            />
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
              <button type="button" className="rb-btn" onClick={() => mediaRef.current?.click()}>
                {mediaFile ? 'Change file' : '+ Upload image or video'}
              </button>
              {mediaFile && (
                <span className="rb-chat-attach-chip">
                  {mediaFile.name.length > 34 ? `${mediaFile.name.slice(0, 34)}...` : mediaFile.name} ({Math.ceil(mediaFile.size / 1024)} KB)
                  <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }} onClick={() => { setMediaFile(null); setMediaPreview(null) }}>
                    remove
                  </button>
                </span>
              )}
            </div>
            {mediaPreview && (
              <img src={mediaPreview} alt="Preview" style={{ marginTop: 8, maxHeight: 220, maxWidth: '100%', border: '1px solid #c3cdd7', borderRadius: 4, display: 'block' }} />
            )}
            {mediaFile && mediaFile.type.startsWith('video/') && (
              <div style={{ fontSize: 10, color: '#2c6e31', marginTop: 5, background: '#e8f5e4', border: '1px solid #9fce93', borderRadius: 4, padding: '5px 8px' }}>
                ▶ Videos up to 100MB — it plays right in the feed AND gets its own watch page on the Videos tab.
              </div>
            )}
            {hintVideo && !mediaFile && (
              <div style={{ fontSize: 10, color: '#24425f', marginTop: 5, background: '#eef3f8', border: '1px solid #b4c2cf', borderRadius: 4, padding: '5px 8px' }}>
                Tip: hit “+ Upload image or video” below and pick your video file — that&apos;s all it takes.
              </div>
            )}
          </div>
          <div>
            <button className="rb-btn rb-btn-green" type="submit" disabled={busy} style={{ fontSize: 13, padding: '9px 22px' }}>
              {busy ? 'Posting...' : `Post to ${postLabel}`}
            </button>
          </div>
        </div>
      </form>
      <CommunitySidebar active={targetSub ? `r/${targetSub.slug}` : targetFlair ? rName(targetFlair) : 'r/all'} />
    </div>
  )
}

/* ================= Community post detail (/community/[id]) ================= */

export function CommunityDetailView({ id }: { id: string }) {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const [post, setPost] = useState<CommunityPostT | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [comment, setComment] = useState('')
  const [commentFile, setCommentFile] = useState<File | null>(null)
  const commentFileRef = useRef<HTMLInputElement>(null)
  const commentTaRef = useRef<HTMLTextAreaElement>(null)
  const replyTaRef = useRef<HTMLTextAreaElement>(null)
  const [busy, setBusy] = useState(false)
  /* replies: which comment is the reply box open under + the draft text */
  const [replyTo, setReplyTo] = useState<string | null>(null)
  const [replyText, setReplyText] = useState('')

  const load = useCallback(async () => {
    try {
      const res = await api<{ post: CommunityPostT }>(`/api/community/${id}`)
      setPost(res.post)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load post')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => {
    load()
  }, [load])

  useEffect(() => {
    if (post) document.title = `${post.title} - RetroBlox`
  }, [post])

  async function vote(value: 1 | -1) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!post) return
    try {
      const res = await api<{ ups: number; downs: number; score: number; myVote: number }>(`/api/community/${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ value }),
      })
      setPost({ ...post, ...res })
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Vote failed', 2200)
    }
  }

  async function sendComment() {
    if (!comment.trim() && !commentFile) return
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('text', comment.trim())
      if (commentFile) fd.append('file', commentFile)
      const res = await api<{ comment: CommunityCommentT }>(`/api/community/${id}`, {
        method: 'POST',
        body: fd,
      })
      if (post) setPost({ ...post, comments: [...(post.comments || []), res.comment], commentCount: (post.commentCount || 0) + 1 })
      setComment('')
      setCommentFile(null)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to comment', 2400)
    } finally {
      setBusy(false)
    }
  }

  async function likeComment(commentId: string) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!post) return
    try {
      const res = await api<{ likes: number; myLike: boolean }>(`/api/community/comment/${commentId}`, { method: 'PATCH' })
      setPost({
        ...post,
        comments: (post.comments || []).map((c) => (c.id === commentId ? { ...c, likes: res.likes, myLike: res.myLike } : c)),
      })
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    }
  }

  async function deleteComment(commentId: string) {
    if (!post) return
    try {
      await api(`/api/community/comment/${commentId}`, { method: 'DELETE' })
      setPost({ ...post, comments: (post.comments || []).filter((c) => c.id !== commentId && c.parentId !== commentId) })
      flash(setToast, 'Comment deleted.', 2000)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    }
  }

  async function postReply(parentId: string) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!post || !replyText.trim()) return
    try {
      const fd = new FormData()
      fd.append('text', replyText.trim())
      fd.append('parentId', parentId)
      const res = await api<{ comment: CommunityCommentT }>(`/api/community/${id}`, { method: 'POST', body: fd })
      setPost({ ...post, comments: [...(post.comments || []), res.comment] })
      setReplyTo(null)
      setReplyText('')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to reply', 2400)
    }
  }

  async function deletePost() {
    if (!post) return
    if (!window.confirm(`Really delete "${post.title}"?`)) return
    try {
      await api(`/api/community/${id}`, { method: 'DELETE' })
      router.push('/community')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    }
  }

  if (loading) return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading post...</div>
  if (error || !post) {
    return (
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#a81a13' }}>
        {error || 'Post not found'}
        <div style={{ marginTop: 12 }}>
          <button className="rb-btn" onClick={() => router.push('/community')}>Back to Community</button>
        </div>
      </div>
    )
  }

  const canDelete = user && (user.id === post.author.id || user.role === 'admin')

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      <div style={{ flex: 1, minWidth: 280 }}>
        <div className="rb-box" style={{ padding: '14px 16px', display: 'flex', gap: 12 }}>
          <VoteArrows ups={post.ups} downs={post.downs} score={post.score} myVote={post.myVote} onVote={(v) => vote(v as 1 | -1)} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11, color: '#7b8896', marginBottom: 6, display: 'flex', gap: 5, alignItems: 'center', flexWrap: 'wrap' }}>
              <SubChip post={post} />
              <span>· posted by</span>
              <Link href={`/users/${post.author.id}`} className="rb-link" style={{ fontSize: 11 }}>u/{post.author.username}</Link>
              {post.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
              <span>· {timeAgo(post.createdAt)}</span>
            </div>
            <h1 style={{ fontSize: 20, color: '#1c2733', margin: '0 0 10px', lineHeight: 1.3 }}><FxText text={post.title} /></h1>
            {post.body && <div style={{ fontSize: 13, color: '#2c3e50', lineHeight: 1.7, whiteSpace: 'pre-wrap' }}><FxText text={post.body} /></div>}
            {mediaRender(post.mediaFileId ?? null, post.mediaType ?? null, post.mediaName)}
            {post.videoId && (
              <Link href={`/videos/${post.videoId}`} className="rb-btn" style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11, textDecoration: 'none', marginTop: 8 }}>
                <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 3.5h10v9H3z" fill="none" stroke="#c81c14" strokeWidth="1.3" /><path d="M6.5 6l3.5 2-3.5 2z" fill="#c81c14" /></svg>
                Watch on the Videos tab — views and comments live there
              </Link>
            )}
            {canDelete && (
              <div style={{ marginTop: 10 }}>
                <button className="rb-btn rb-btn-red" style={{ fontSize: 9, padding: '3px 9px' }} onClick={deletePost}>Delete Post</button>
              </div>
            )}
          </div>
        </div>

        {/* comments */}
        <div className="rb-box" style={{ marginTop: 14 }}>
          <div className="rb-panel-head"><span>Comments ({post.comments?.length || 0})</span></div>
          <div style={{ padding: 14 }}>
            {user && (
              <div style={{ display: 'flex', gap: 10, marginBottom: 18 }}>
                <Avatar user={user as RetroUser} size={38} />
                <div style={{ flex: 1 }}>
                  <textarea
                    ref={commentTaRef}
                    className="rb-textarea"
                    value={comment}
                    onChange={(e) => setComment(e.target.value)}
                    placeholder="Join the conversation..."
                    rows={2}
                    style={{ width: '100%', resize: 'vertical' }}
                    maxLength={2000}
                    aria-label="Write a comment"
                  />
                  <FxToolbar taRef={commentTaRef} value={comment} onChange={setComment} />
                  {commentFile && (
                    <div className="rb-chat-attach-chip" style={{ marginTop: 5 }}>
                      {commentFile.name.length > 34 ? `${commentFile.name.slice(0, 34)}...` : commentFile.name}
                      <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }} onClick={() => setCommentFile(null)}>
                        remove
                      </button>
                    </div>
                  )}
                  <div style={{ display: 'flex', justifyContent: 'flex-end', alignItems: 'center', gap: 6, marginTop: 5 }}>
                    <input
                      ref={commentFileRef}
                      type="file"
                      accept="image/*,video/*"
                      style={{ display: 'none' }}
                      onChange={(e) => {
                        const f = e.target.files?.[0]
                        if (f) setCommentFile(f)
                        e.target.value = ''
                      }}
                    />
                    <button className="rb-btn" style={{ fontSize: 10 }} type="button" onClick={() => commentFileRef.current?.click()}>
                      + Image / Video
                    </button>
                    <button className="rb-btn rb-btn-green" onClick={sendComment} disabled={busy || (!comment.trim() && !commentFile)}>Post Comment</button>
                  </div>
                </div>
              </div>
            )}

            {(!post.comments || post.comments.length === 0) && (
              <div style={{ color: '#7b8896', fontSize: 11, padding: '6px 2px' }}>No comments yet. Say something!</div>
            )}

            {/* threads: top-level comments with replies nested under them */}
            {(post.comments || []).filter((c) => !c.parentId).map((c) => {
              const replies = (post.comments || []).filter((r) => r.parentId === c.id)
              const replyOpen = replyTo === c.id
              return (
                <div key={c.id} style={{ padding: '10px 0', borderTop: '1px solid #e4eaf0' }}>
                  <div style={{ display: 'flex', gap: 10 }}>
                    <Avatar user={c.author} size={34} />
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                        <Link href={`/users/${c.author.id}`} className="rb-link" style={{ fontSize: 11 }}>u/{c.author.username}</Link>
                        {c.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                        <span style={{ fontSize: 10, color: '#7b8896' }}>{timeAgo(c.createdAt)}</span>
                      </div>
                      <div style={{ fontSize: 12, color: '#2c3e50', marginTop: 3, lineHeight: 1.55, whiteSpace: 'pre-wrap' }}><FxText text={c.text} /></div>
                      {mediaRender(c.mediaFileId ?? null, c.mediaType ?? null, c.mediaName)}
                      <div style={{ marginTop: 4, display: 'flex', alignItems: 'center', gap: 8 }}>
                        <button
                          type="button"
                          className={`rb-like-btn${c.myLike ? ' rb-liked' : ''}`}
                          onClick={() => likeComment(c.id)}
                          aria-pressed={c.myLike}
                          title="Like this comment"
                        >
                          <svg width="10" height="10" viewBox="0 0 16 16" aria-hidden="true">
                            <path
                              d="M8 14s-6-3.7-6-7.6C2 4 3.7 2.5 5.6 2.5 6.9 2.5 7.7 3.2 8 4c.3-.8 1.1-1.5 2.4-1.5C12.3 2.5 14 4 14 6.4 14 10.3 8 14 8 14z"
                              fill={c.myLike ? '#e0448c' : 'none'}
                              stroke={c.myLike ? '#b02a72' : '#7b8896'}
                              strokeWidth="1.2"
                            />
                          </svg>
                          {c.likes || 0}
                        </button>
                        {user && (
                          <button
                            type="button"
                            className="rb-link"
                            style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }}
                            onClick={() => {
                              setReplyTo(replyOpen ? null : c.id)
                              setReplyText('')
                            }}
                            aria-expanded={replyOpen}
                          >
                            ↩ Reply{replies.length ? ` (${replies.length})` : ''}
                          </button>
                        )}
                        {user && (user.id === c.author.id || user.role === 'admin') && (
                          <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 9, color: '#a03a34' }} onClick={() => deleteComment(c.id)}>
                            delete
                          </button>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* replies */}
                  {replies.length > 0 && (
                    <div style={{ marginLeft: 44, marginTop: 10, display: 'grid', gap: 10 }}>
                      {replies.map((r) => (
                        <div key={r.id} style={{ display: 'flex', gap: 8 }}>
                          <Avatar user={r.author} size={26} />
                          <div style={{ flex: 1 }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                              <Link href={`/users/${r.author.id}`} className="rb-link" style={{ fontSize: 11 }}>u/{r.author.username}</Link>
                              {r.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                              <span style={{ fontSize: 10, color: '#7b8896' }}>{timeAgo(r.createdAt)}</span>
                            </div>
                            <div style={{ fontSize: 12, color: '#2c3e50', marginTop: 2, lineHeight: 1.55, whiteSpace: 'pre-wrap' }}><FxText text={r.text} /></div>
                            {mediaRender(r.mediaFileId ?? null, r.mediaType ?? null, r.mediaName)}
                            {user && (user.id === r.author.id || user.role === 'admin') && (
                              <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 9, color: '#a03a34', marginTop: 2 }} onClick={() => deleteComment(r.id)}>
                                delete
                              </button>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}

                  {/* inline reply composer */}
                  {replyOpen && user && (
                    <div style={{ marginLeft: 44, marginTop: 10, display: 'flex', gap: 8 }}>
                      <Avatar user={user as RetroUser} size={26} />
                      <div style={{ flex: 1 }}>
                        <textarea
                          ref={replyTaRef}
                          className="rb-textarea"
                          value={replyText}
                          onChange={(e) => setReplyText(e.target.value)}
                          rows={2}
                          maxLength={2000}
                          placeholder={`Replying to u/${c.author.username}...`}
                          style={{ width: '100%', resize: 'vertical' }}
                          aria-label="Write a reply"
                          autoFocus
                        />
                        <FxToolbar taRef={replyTaRef} value={replyText} onChange={setReplyText} />
                        <div style={{ display: 'flex', gap: 6, marginTop: 4 }}>
                          <button className="rb-btn rb-btn-green" style={{ fontSize: 10 }} disabled={busy || !replyText.trim()} onClick={() => postReply(c.id)}>
                            Reply
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
      <CommunitySidebar active={post.sub ? `r/${post.sub.slug}` : rName(post.flair)} />
    </div>
  )
}
