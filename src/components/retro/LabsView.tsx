'use client'

/* ------------------------------------------------------------------
   RetroLabs — the developer workshop. 2026 refresh:
   - roomier, display-font cards (Fredoka One headers, Source Sans body)
   - Reddit-style UP + DOWN vote arrows with a live score
   - image previews right on the feed card (lightbox without opening)
   - EDIT your own post (title/body/video) with the FX editor
   - text effects render everywhere + live preview before publishing
   Boards behave like r/ communities: r/tutorials, r/sourcecode,
   r/showcase, r/help.
------------------------------------------------------------------ */

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, timeAgo, fmtCount, flash, type RetroUser } from '@/lib/store'
import { Avatar, OnlineDot } from './Shell'
import { mediaRender } from './ChatView'
import { FxToolbar, FxText } from '@/lib/textfx'

export const LAB_BOARDS = ['Tutorials', 'Source Code', 'Showcase', 'Help'] as const

export const BOARD_STYLE: Record<string, { color: string; blurb: string; bg: string }> = {
  Tutorials: { color: '#1b6cb0', blurb: 'Teach other devs how you build things', bg: '#e8f1fa' },
  'Source Code': { color: '#6b3fa0', blurb: 'Share project files and code to remix', bg: '#f0e9f8' },
  Showcase: { color: '#b0611b', blurb: 'Show off what you are building', bg: '#fbf0e4' },
  Help: { color: '#2c6e31', blurb: 'Stuck? Ask the workshop', bg: '#e8f5e4' },
}

function BoardChip({ board }: { board: string }) {
  const s = BOARD_STYLE[board] || { color: '#5a6b7b', bg: '#eef3f8' }
  return (
    <span
      style={{
        display: 'inline-block',
        fontFamily: 'var(--rb-display)',
        fontSize: 10,
        padding: '2px 9px',
        borderRadius: 4,
        border: `1px solid ${s.color}55`,
        color: s.color,
        background: s.bg,
        letterSpacing: '0.4px',
      }}
    >
      {board}
    </span>
  )
}

/* reddit-style vote column — shared by feed cards + detail */
export function LabVoteCol({
  myVote, score, onVote, compact,
}: {
  myVote: number
  score: number
  onVote: (v: number) => void
  compact?: boolean
}) {
  const arrow = (up: boolean, active: boolean) => (
    <svg width="17" height="13" viewBox="0 0 16 12" aria-hidden="true">
      <path
        d={up ? 'M8 1l6 8H2z' : 'M8 11L2 3h12z'}
        fill={active ? (up ? '#e07b00' : '#5a7b9a') : '#c3cdd7'}
        stroke={active ? (up ? '#a35a00' : '#3d566e') : '#a8b6c2'}
        strokeWidth="1"
      />
    </svg>
  )
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, width: compact ? 34 : 40, flexShrink: 0, paddingTop: 2 }}>
      <button
        type="button"
        className={`rb-vote-btn${myVote === 1 ? ' rb-vote-btn-on-up' : ''}`}
        onClick={() => onVote(1)}
        aria-label="Upvote"
        aria-pressed={myVote === 1}
        title="Upvote"
      >
        {arrow(true, myVote === 1)}
      </button>
      <span style={{ fontSize: 12, color: score > 0 ? '#c2570e' : score < 0 ? '#3d566e' : '#5a6b7b' }}>{score}</span>
      <button
        type="button"
        className={`rb-vote-btn${myVote === -1 ? ' rb-vote-btn-on-down' : ''}`}
        onClick={() => onVote(-1)}
        aria-label="Downvote"
        aria-pressed={myVote === -1}
        title="Downvote"
      >
        {arrow(false, myVote === -1)}
      </button>
    </div>
  )
}

/* fullscreen lightbox — preview a picture WITHOUT opening the post */
function Lightbox({ src, onClose }: { src: string; onClose: () => void }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', onKey)
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = prev
    }
  }, [onClose])
  return (
    <div className="rb-lightbox" role="dialog" aria-modal="true" aria-label="Image preview" onClick={onClose}>
      <button type="button" className="rb-lightbox-x" aria-label="Close preview" onClick={onClose}>✕</button>
      <img src={src} alt="Preview" onClick={(e) => e.stopPropagation()} />
    </div>
  )
}

function parseMedia(json: string): { fileId: string; type: string; name: string }[] {
  try {
    const arr = JSON.parse(json || '[]')
    return Array.isArray(arr) ? arr : []
  } catch {
    return []
  }
}

/* thumbnail strip for feed cards — images BEFORE opening the post */
function CardThumbGrid({ mediaJson, onPreview }: { mediaJson: string; onPreview: (src: string) => void }) {
  const media = parseMedia(mediaJson)
  if (media.length === 0) return null
  const isImg = (m: { type: string }) => m.type === 'image'
  return (
    <div className={`rb-thumbgrid rb-thumbs-${Math.min(media.length, 3)}`}>
      {media.slice(0, 3).map((m, i) => (
        <button
          key={m.fileId}
          type="button"
          className="rb-thumb"
          onClick={() => onPreview(`/api/files/${m.fileId}`)}
          title={isImg(m) ? `Preview ${m.name || 'picture'}` : 'Video — open the post to watch'}
          aria-label={isImg(m) ? 'Preview picture' : 'Video preview'}
        >
          <img src={`/api/files/${m.fileId}`} alt={m.name || 'attachment'} loading="lazy" />
          {!isImg(m) && (
            <span className="rb-thumb-video">
              <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden="true">
                <circle cx="11" cy="11" r="10" fill="rgba(255,255,255,.9)" />
                <path d="M8.5 6.8v8.4l7-4.2z" fill="#0d69ac" />
              </svg>
            </span>
          )}
          {i === 2 && media.length > 3 && <span className="rb-thumb-count">+{media.length - 3}</span>}
        </button>
      ))}
    </div>
  )
}

/* detail-page gallery (full-size media) */
function LabsMediaGallery({ mediaJson, onPreview }: { mediaJson: string; onPreview: (src: string) => void }) {
  const media = parseMedia(mediaJson)
  if (media.length === 0) return null
  return (
    <div style={{ marginTop: 12, display: 'grid', gap: 10, maxWidth: 520 }}>
      {media.map((m) => (
        <div key={m.fileId}>
          {m.type === 'image' ? (
            <button
              type="button"
              className="rb-thumb"
              style={{ aspectRatio: 'auto', maxHeight: 340 }}
              onClick={() => onPreview(`/api/files/${m.fileId}`)}
              title="Click to enlarge"
            >
              <img src={`/api/files/${m.fileId}`} alt={m.name || 'picture'} style={{ maxHeight: 340 }} />
            </button>
          ) : (
            mediaRender(m.fileId, m.type, m.name)
          )}
        </div>
      ))}
    </div>
  )
}

function VideoBox({ url }: { url: string }) {
  const yt = url.match(/(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([A-Za-z0-9_-]{6,})/)
  if (yt) {
    return (
      <div style={{ marginTop: 12, border: '1px solid #c3cdd7', background: '#000', maxWidth: 480, borderRadius: 6, overflow: 'hidden' }}>
        <iframe
          src={`https://www.youtube.com/embed/${yt[1]}`}
          title="Video"
          style={{ display: 'block', width: '100%', aspectRatio: '16/9', border: 'none' }}
          allowFullScreen
        />
      </div>
    )
  }
  return (
    <a href={url} target="_blank" rel="noreferrer" className="rb-link" style={{ fontSize: 12, display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 8 }}>
      <span style={{ fontSize: 13 }}>&#9654;</span> Watch video
    </a>
  )
}

function countIds(json: string): number {
  try { return (JSON.parse(json || '[]') as unknown[]).length } catch { return 0 }
}

/* r/ style name for boards */
function rBoard(board: string): string {
  return `r/${board.toLowerCase().replace(/\s+/g, '')}`
}

/* ================= RetroLabs index (/labs) ================= */

interface LabPostSummary {
  id: string
  board: string
  title: string
  excerpt: string
  videoUrl: string | null
  mediaJson: string
  codeFileId: string | null
  codeFileName: string | null
  likeIds: string
  downIds: string
  editedAt: string | null
  views: number
  author: { id: string; username: string; avatarUrl: string | null; role: string }
  createdAt: string
  replyCount: number
}

export function LabsView() {
  const { setToast } = useRetro()
  const router = useRouter()
  const [data, setData] = useState<{ posts: LabPostSummary[]; key: string } | null>(null)
  const [board, setBoard] = useState<string>('')
  const [sort, setSort] = useState<'hot' | 'new' | 'top'>('hot')
  const [q, setQ] = useState('')
  const [query, setQuery] = useState('')
  const [lightbox, setLightbox] = useState<string | null>(null)

  const key = `${board}|${sort}|${query}`
  const loading = !data || data.key !== key
  const raw = data?.posts ?? []

  useEffect(() => {
    let cancelled = false
    const params = new URLSearchParams()
    if (board) params.set('board', board)
    if (query) params.set('q', query)
    const qs = params.toString()
    api<{ posts: LabPostSummary[] }>(`/api/labs${qs ? `?${qs}` : ''}`)
      .then((r) => { if (!cancelled) setData({ posts: r.posts, key: `${board}|${sort}|${query}` }) })
      .catch(() => { if (!cancelled) setData({ posts: [], key: `${board}|${sort}|${query}` }) })
    return () => { cancelled = true }
  }, [board, query, sort])

  useEffect(() => {
    document.title = 'RetroLabs - RetroBlox'
  }, [])

  const posts = (() => {
    const withRank = raw.map((p) => ({
      p,
      score: countIds(p.likeIds) - countIds(p.downIds),
      at: new Date(p.createdAt).getTime(),
    }))
    if (sort === 'new') withRank.sort((a, b) => b.at - a.at)
    else if (sort === 'top') withRank.sort((a, b) => b.score - a.score)
    else {
      const hot = (x: { score: number; at: number }) => (x.score + 1) / Math.pow((Date.now() - x.at) / 3600000 + 2, 1.4)
      withRank.sort((a, b) => hot(b) - hot(a))
    }
    return withRank.map((x) => x.p)
  })()

  async function vote(p: LabPostSummary, v: 1 | -1) {
    if (!useRetro.getState().user) {
      router.push('/login')
      return
    }
    const meId = useRetro.getState().user?.id
    try {
      const res = await api<{ ups: number; downs: number; score: number; myVote: number }>(`/api/labs/${p.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ vote: v }),
      })
      setData((d) =>
        d
          ? {
              ...d,
              posts: d.posts.map((x) => {
                if (x.id !== p.id) return x
                const ups = parseIds(x.likeIds).filter((id) => id !== meId)
                const downs = parseIds(x.downIds).filter((id) => id !== meId)
                if (res.myVote === 1 && meId) ups.push(meId)
                if (res.myVote === -1 && meId) downs.push(meId)
                return { ...x, likeIds: JSON.stringify(ups), downIds: JSON.stringify(downs) }
              }),
            }
          : d,
      )
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    }
  }

  function parseIds(json: string): string[] {
    try { return JSON.parse(json || '[]') as string[] } catch { return [] }
  }

  return (
    <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      {/* --------------- feed --------------- */}
      <div style={{ flex: 1, minWidth: 300, display: 'grid', gap: 14 }}>
        {/* header bar: title + search + actions */}
        <div className="rb-box" style={{ padding: 0, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', flexWrap: 'wrap' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 9 }}>
              <span style={{ width: 34, height: 34, borderRadius: 7, background: 'linear-gradient(180deg,#2f7bc0,#1b4f7e)', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace", fontSize: 14, border: '1px solid #17456f' }}>&lt;/&gt;</span>
              <span className="rb-display" style={{ fontSize: 17, color: '#16324a' }}>RetroLabs — Dev Forum</span>
            </span>
            <form
              onSubmit={(e) => {
                e.preventDefault()
                setQuery(q.trim())
              }}
              style={{ display: 'flex', flex: 1, minWidth: 150, maxWidth: 280, marginLeft: 'auto' }}
            >
              <input
                className="rb-input"
                type="search"
                placeholder="Search tutorials & code..."
                value={q}
                onChange={(e) => setQ(e.target.value)}
                style={{ flex: 1, minWidth: 0, borderRadius: '4px 0 0 4px', fontSize: 12 }}
                aria-label="Search RetroLabs posts"
              />
              <button className="rb-btn" type="submit" style={{ borderRadius: '0 4px 4px 0', borderLeft: 'none', fontSize: 12 }}>
                Go
              </button>
            </form>
            <Link className="rb-btn rb-btn-green" href="/labs/new" style={{ fontSize: 12, padding: '7px 14px', textDecoration: 'none', whiteSpace: 'nowrap' }}>
              + New Post
            </Link>
          </div>
          <div style={{ display: 'flex', borderTop: '1px solid #e4eaf0', alignItems: 'center', flexWrap: 'wrap' }}>
            {(['hot', 'new', 'top'] as const).map((s) => (
              <button
                key={s}
                type="button"
                className="rb-clickable rb-display"
                onClick={() => setSort(s)}
                style={{
                  flex: 1, textAlign: 'center', padding: '10px 6px', background: sort === s ? '#e8f1fa' : 'transparent',
                  border: 'none', borderBottom: sort === s ? '2px solid #2f7bc0' : '2px solid transparent',
                  fontSize: 12, color: sort === s ? '#0a4f82' : '#5a6b7b', letterSpacing: '0.4px', cursor: 'pointer',
                }}
                aria-pressed={sort === s}
              >
                {s === 'hot' ? 'Hot' : s === 'new' ? 'New' : 'Top'}
              </button>
            ))}
            {(query || board) && (
              <button
                type="button"
                className="rb-clickable"
                onClick={() => {
                  setBoard('')
                  setQuery('')
                  setQ('')
                }}
                style={{ fontSize: 11, color: '#a03a34', background: 'none', border: 'none', padding: '4px 12px', cursor: 'pointer' }}
                title="Clear search + board filter"
              >
                ✕ clear
              </button>
            )}
          </div>
        </div>

        <div style={{ fontSize: 12, color: '#5a6b7b', padding: '0 4px', lineHeight: 1.65 }}>
          The developer workshop — any engine welcome (Unity, Godot, Unreal, GameMaker, Roblox Studio, whatever you code in).
          Tutorials, videos, source code, help — by devs, for devs. Preview the pictures right on the card, then open the post.
        </div>

        {loading && (
          <div style={{ display: 'grid', gap: 12 }} aria-label="Loading">
            {[0, 1, 2].map((i) => (
              <div key={i} className="rb-box rb-skeleton" style={{ padding: 16, display: 'flex', gap: 12 }}>
                <span className="rb-skel-block" style={{ width: 40, height: 52 }} />
                <span style={{ flex: 1, display: 'grid', gap: 7 }}>
                  <span className="rb-skel-block" style={{ width: '42%', height: 10 }} />
                  <span className="rb-skel-block" style={{ width: '88%', height: 14 }} />
                  <span className="rb-skel-block" style={{ width: '58%', height: 10 }} />
                </span>
              </div>
            ))}
          </div>
        )}

        {!loading && posts.length === 0 && (
          <div className="rb-box" style={{ padding: '38px 22px', textAlign: 'center', color: '#5a6b7b' }}>
            <div className="rb-display" style={{ fontSize: 16, marginBottom: 6, color: '#16324a' }}>
              {query ? `Nothing matches "${query}"` : board ? `${rBoard(board)} is quiet right now.` : 'No posts here yet.'}
            </div>
            <div style={{ fontSize: 12, marginBottom: 14 }}>Be the first to teach the workshop something!</div>
            <Link className="rb-btn rb-btn-green" href="/labs/new" style={{ textDecoration: 'none', display: 'inline-block' }}>Write the first post</Link>
          </div>
        )}

        {!loading && posts.map((p) => {
          const media = parseMedia(p.mediaJson)
          const ups = parseIds(p.likeIds)
          const downs = parseIds(p.downIds)
          const meId = useRetro.getState().user?.id
          const myVote = meId ? (ups.includes(meId) ? 1 : downs.includes(meId) ? -1 : 0) : 0
          const score = ups.length - downs.length
          return (
            <div key={p.id} className="rb-box rb-feed-card" style={{ display: 'flex', gap: 12 }}>
              {/* reddit-style vote column: up AND down */}
              <LabVoteCol myVote={myVote} score={score} onVote={(v) => vote(p, v === 1 ? 1 : -1)} compact />

              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 11, color: '#7b8896', marginBottom: 4, display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                    <span style={{ width: 17, height: 17, borderRadius: '50%', background: BOARD_STYLE[p.board]?.bg || '#eef3f8', border: `1px solid ${BOARD_STYLE[p.board]?.color || '#b4c2cf'}`, color: BOARD_STYLE[p.board]?.color || '#5a6b7b', fontSize: 8, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace" }}>{'</>'}</span>
                    <span style={{ color: BOARD_STYLE[p.board]?.color || '#5a6b7b', fontFamily: 'var(--rb-display)', fontSize: 10.5, letterSpacing: '0.3px' }}>{rBoard(p.board)}</span>
                  </span>
                  <span>· posted by</span>
                  <Link href={`/users/${p.author.id}`} className="rb-link" style={{ fontSize: 11 }}>u/{p.author.username}</Link>
                  {p.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                  <span>· {timeAgo(p.createdAt)}</span>
                  {p.editedAt && <span className="rb-edited-chip">· edited {timeAgo(p.editedAt)}</span>}
                </div>

                <Link href={`/labs/${p.id}`} className="rb-post-title"><FxText text={p.title} /></Link>

                {p.excerpt && (
                  <div style={{
                    fontSize: 12, color: '#4a5a68', lineHeight: 1.55, marginTop: 4,
                    display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
                  }}>
                    {p.excerpt}
                  </div>
                )}

                {/* image previews BEFORE opening the post */}
                <CardThumbGrid mediaJson={p.mediaJson} onPreview={setLightbox} />

                <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 8, flexWrap: 'wrap' }}>
                  <BoardChip board={p.board} />
                  {p.videoUrl && <span style={{ fontSize: 10, color: '#c81c14' }}>▶ video</span>}
                  {media.length > 0 && <span style={{ fontSize: 10, color: '#7b8896' }}>media ×{media.length}</span>}
                  {p.codeFileId && <span style={{ fontSize: 10, color: '#6b3fa0', fontFamily: "'Courier New', monospace" }}>{'</>'} {p.codeFileName || 'source'}</span>}
                </div>

                <div style={{ marginTop: 9, fontSize: 11, display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap', color: '#7b8896' }}>
                  <Link href={`/labs/${p.id}`} className="rb-clickable" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11, color: '#7b8896', textDecoration: 'none' }}>
                    <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><path d="M2 2h12v8H6l-3 3v-3H2z" fill="none" stroke="#7b8896" strokeWidth="1.3" /></svg>
                    {p.replyCount} repl{p.replyCount === 1 ? 'y' : 'ies'}
                  </Link>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                    <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><path d="M1.5 8s2.5-4 6.5-4 6.5 4 6.5 4-2.5 4-6.5 4-6.5-4-6.5-4z" fill="none" stroke="#7b8896" strokeWidth="1.3" /><circle cx="8" cy="8" r="1.7" fill="#7b8896" /></svg>
                    {fmtCount(p.views)} views
                  </span>
                  <Link href={`/labs/${p.id}`} className="rb-link" style={{ fontSize: 11 }}>open post →</Link>
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {/* --------------- right rail: community-style, white --------------- */}
      <aside style={{ width: 300, flexShrink: 0, display: 'grid', gap: 14, alignContent: 'start' }} className="rb-comm-rail">
        <div className="rb-box" style={{ overflow: 'hidden', padding: 0 }}>
          <div style={{ height: 58, background: 'linear-gradient(120deg,#1b4f7e,#2f7bc0 55%,#6b3fa0)', display: 'flex', alignItems: 'flex-end', padding: '0 13px 6px' }}>
            <span style={{ background: '#fff', border: '1px solid #c3cdd7', borderRadius: 9, width: 46, height: 46, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: -22, boxShadow: '0 1px 4px rgba(0,0,0,.25)', fontFamily: "'Courier New', monospace", color: '#1b4f7e', fontSize: 14 }}>&lt;/&gt;</span>
          </div>
          <div style={{ padding: '28px 13px 13px' }}>
            <div className="rb-display" style={{ fontSize: 15, color: '#16324a' }}>r/RetroLabs — Dev Forum</div>
            <div style={{ fontSize: 11, color: '#5a6b7b', margin: '6px 0 11px', lineHeight: 1.6 }}>
              The developer community: post tutorials, upload videos and source code from ANY engine, and help each other build.
            </div>
            <div style={{ display: 'flex', gap: 20, fontSize: 12, color: '#1c2733' }}>
              <div>
                <div style={{ fontSize: 15 }}>{raw.length}</div>
                <div style={{ fontSize: 10, color: '#7b8896' }}>Topics</div>
              </div>
              <div>
                <div style={{ fontSize: 15 }}>{raw.reduce((n, p) => n + p.replyCount, 0)}</div>
                <div style={{ fontSize: 10, color: '#7b8896' }}>Replies</div>
              </div>
            </div>
            <Link className="rb-btn rb-btn-green" href="/labs/new" style={{ textDecoration: 'none', display: 'block', textAlign: 'center', marginTop: 12, fontSize: 13, padding: '8px 0' }}>
              + Create Post
            </Link>
            <Link href="/community" className="rb-clickable" style={{ display: 'block', textAlign: 'center', marginTop: 9, fontSize: 11, color: '#1c4e7c', textDecoration: 'none' }}>
              ← back to the player lounge
            </Link>
          </div>
        </div>

        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head"><span>r/ Boards</span></div>
          <div style={{ padding: 7 }}>
            <button
              type="button"
              onClick={() => setBoard('')}
              className="rb-clickable"
              style={{
                display: 'flex', alignItems: 'center', gap: 9, padding: '7px 9px', borderRadius: 5, width: '100%',
                textAlign: 'left', background: board === '' ? '#e8f1fa' : 'transparent', border: 'none', cursor: 'pointer',
              }}
            >
              <span style={{ width: 23, height: 23, borderRadius: '50%', background: '#1b4f7e', color: '#fff', fontSize: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace", flexShrink: 0 }}>r/</span>
              <span>
                <span style={{ display: 'block', fontSize: 12, color: '#1c4e7c' }}>r/all</span>
                <span style={{ display: 'block', fontSize: 10, color: '#7b8896' }}>everything from the workshop</span>
              </span>
            </button>
            {LAB_BOARDS.map((b) => (
              <button
                key={b}
                type="button"
                onClick={() => setBoard(board === b ? '' : b)}
                className="rb-clickable"
                style={{
                  display: 'flex', alignItems: 'center', gap: 9, padding: '7px 9px', borderRadius: 5, width: '100%',
                  textAlign: 'left', background: board === b ? BOARD_STYLE[b].bg : 'transparent', border: 'none', cursor: 'pointer',
                }}
              >
                <span style={{ width: 23, height: 23, borderRadius: '50%', background: '#fff', border: `1px solid ${BOARD_STYLE[b].color}`, color: BOARD_STYLE[b].color, fontSize: 9, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace", flexShrink: 0 }}>{'</>'}</span>
                <span>
                  <span style={{ display: 'block', fontSize: 12, color: '#1c4e7c' }}>{rBoard(b)}</span>
                  <span style={{ display: 'block', fontSize: 10, color: '#7b8896' }}>{BOARD_STYLE[b].blurb}</span>
                </span>
              </button>
            ))}
          </div>
        </div>

        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head"><span>Workshop Rules</span></div>
          <ol style={{ margin: 0, padding: '10px 12px 12px 28px', fontSize: 11, color: '#5a6b7b', lineHeight: 1.9 }}>
            <li>Teach, don&apos;t gatekeep.</li>
            <li>Credit code you didn&apos;t write.</li>
            <li>Any engine is welcome here.</li>
            <li>Help beginners — you were one too.</li>
            <li>Ship things. Retro things.</li>
          </ol>
        </div>
      </aside>

      {lightbox && <Lightbox src={lightbox} onClose={() => setLightbox(null)} />}
    </div>
  )
}

/* ================= New RetroLabs post (/labs/new) ================= */

interface PickedMedia {
  file: File
  url: string // object URL for the before-publish preview
  kind: 'image' | 'video'
}

export function LabNewView() {
  const { setToast } = useRetro()
  const router = useRouter()
  const [board, setBoard] = useState<string>('Tutorials')
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [videoUrl, setVideoUrl] = useState('')
  const [mediaFiles, setMediaFiles] = useState<PickedMedia[]>([])
  const [codeFile, setCodeFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const mediaRef = useRef<HTMLInputElement>(null)
  const bodyTaRef = useRef<HTMLTextAreaElement>(null)
  const titleTaRef = useRef<HTMLInputElement>(null)
  const [lightbox, setLightbox] = useState<string | null>(null)

  // revoke the object URLs when the composer unmounts
  useEffect(() => {
    return () => { mediaFiles.forEach((m) => URL.revokeObjectURL(m.url)) }
  }, [])

  function addMedia(files: File[]) {
    setMediaFiles((prev) => {
      const next = [...prev]
      for (const f of files) {
        if (next.length >= 4) break
        if (!f.type.startsWith('image/') && !f.type.startsWith('video/')) continue
        next.push({ file: f, url: URL.createObjectURL(f), kind: f.type.startsWith('video/') ? 'video' : 'image' })
      }
      return next
    })
  }

  function removeMedia(i: number) {
    setMediaFiles((prev) => {
      URL.revokeObjectURL(prev[i].url)
      return prev.filter((_, j) => j !== i)
    })
  }

  async function submit(e?: React.FormEvent) {
    e?.preventDefault()
    setError('')
    if (title.trim().length < 5) {
      setError('Title must be at least 5 characters.')
      return
    }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('board', board)
      fd.append('title', title.trim())
      fd.append('body', body.trim())
      fd.append('videoUrl', videoUrl.trim())
      mediaFiles.forEach((m) => fd.append('mediaFile', m.file))
      if (codeFile) fd.append('codeFile', codeFile)
      const res = await api<{ post: { id: string } }>('/api/labs', { method: 'POST', body: fd })
      flash(setToast, 'Posted to RetroLabs!')
      router.push(`/labs/${res.post.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to post')
      setBusy(false)
    }
  }

  const labelStyle = { fontSize: 12, color: '#24425f', display: 'block', marginBottom: 5 }

  return (
    <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      <form className="rb-box" style={{ flex: 1, minWidth: 300, maxWidth: 720, padding: 0 }} onSubmit={submit}>
        <div className="rb-panel-head">
          <span>Create a post in {rBoard(board)}</span>
          <span style={{ fontSize: 11, color: '#5a6b7b', fontFamily: "'Source Sans Pro', sans-serif" }}>for devs, by devs</span>
        </div>
        <div style={{ padding: 16, display: 'grid', gap: 16 }}>
          {error && (
            <div role="alert" style={{ background: '#fdebe9', border: '1px solid #e1231a', color: '#a81a13', fontSize: 12, padding: '8px 11px', borderRadius: 4 }}>
              {error}
            </div>
          )}
          <div>
            <label style={labelStyle}>Board *</label>
            <div style={{ display: 'flex', gap: 7, flexWrap: 'wrap' }}>
              {LAB_BOARDS.map((b) => (
                <button
                  key={b}
                  type="button"
                  onClick={() => setBoard(b)}
                  className="rb-clickable"
                  style={{
                    fontFamily: 'var(--rb-display)',
                    fontSize: 12, padding: '6px 14px', borderRadius: 13,
                    border: `1px solid ${board === b ? BOARD_STYLE[b].color : '#c3cdd7'}`,
                    background: board === b ? BOARD_STYLE[b].bg : '#fff',
                    color: BOARD_STYLE[b].color,
                    letterSpacing: '0.3px',
                  }}
                  aria-pressed={board === b}
                >
                  {b}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label style={labelStyle} htmlFor="lp-title">Title *</label>
            <input id="lp-title" ref={titleTaRef} className="rb-input" style={{ width: '100%', fontSize: 14 }} value={title} onChange={(e) => setTitle(e.target.value)} maxLength={120} placeholder="Give your post a clear title" />
            <FxToolbar taRef={titleTaRef} value={title} onChange={setTitle} />
          </div>
          <div>
            <label style={labelStyle} htmlFor="lp-body">Post</label>
            <textarea
              id="lp-body"
              ref={bodyTaRef}
              className="rb-textarea"
              style={{ width: '100%', minHeight: 130, resize: 'vertical' }}
              rows={8}
              value={body}
              onChange={(e) => setBody(e.target.value)}
              maxLength={20000}
              placeholder={'Write your tutorial, describe your source code, show your work...\n\nTip: select some text and open FX Menu to give it rainbow, fire, glow and more.'}
            />
            {/* text FX + the always-visible preview — see it BEFORE you publish */}
            <FxToolbar taRef={bodyTaRef} value={body} onChange={setBody} livePreview />
          </div>

          {/* uploaded media: images + video file, WITH previews before publishing */}
          <div style={{ border: '1px dashed #b4c2cf', borderRadius: 6, padding: 12, background: '#f7fafc' }}>
            <label style={labelStyle}>Pictures &amp; video upload (optional)</label>
            <input
              ref={mediaRef}
              type="file"
              accept="image/*,video/*"
              multiple
              style={{ display: 'none' }}
              onChange={(e) => {
                addMedia(Array.from(e.target.files || []))
                e.target.value = ''
              }}
            />
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
              <button type="button" className="rb-btn" onClick={() => mediaRef.current?.click()}>
                + Add pictures / video
              </button>
              <span style={{ fontSize: 11, color: '#7b8896' }}>images up to 8MB, video up to 40MB, max 4 files</span>
            </div>
            {mediaFiles.length > 0 && (
              <div className="rb-upload-strip">
                {mediaFiles.map((m, i) => (
                  <div key={`${m.file.name}-${i}`} className="rb-upload-card">
                    {m.kind === 'image' ? (
                      <img src={m.url} alt={m.file.name} onClick={() => setLightbox(m.url)} style={{ cursor: 'pointer' }} />
                    ) : (
                      <video src={m.url} muted playsInline preload="metadata" />
                    )}
                    <span className="rb-upload-name">{m.file.name}</span>
                    <button type="button" className="rb-upload-x" aria-label={`Remove ${m.file.name}`} onClick={() => removeMedia(i)}>✕</button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div>
            <label style={labelStyle} htmlFor="lp-video">Video link (optional, YouTube embeds)</label>
            <input id="lp-video" className="rb-input" style={{ width: '100%' }} value={videoUrl} onChange={(e) => setVideoUrl(e.target.value)} placeholder="https://youtube.com/watch?v=..." />
          </div>

          <div style={{ border: '1px dashed #b99ad4', borderRadius: 6, padding: 12, background: '#f7f4fa' }}>
            <label style={labelStyle}>Source code upload (optional) — like GitHub</label>
            <input type="file" className="rb-input" style={{ width: '100%', fontSize: 11 }} onChange={(e) => setCodeFile(e.target.files?.[0] || null)} />
            <div style={{ fontSize: 11, marginTop: 5, color: '#7b8896' }}>
              Attach a .zip of your project so others can download, read and remix it (max 40MB).
            </div>
          </div>

          <div>
            <button className="rb-btn rb-btn-green" type="submit" disabled={busy} style={{ fontSize: 14, padding: '10px 24px' }}>
              {busy ? 'Posting...' : `Post to ${rBoard(board)}`}
            </button>
          </div>
        </div>
      </form>

      {/* mini rail for the composer */}
      <aside style={{ width: 300, flexShrink: 0, display: 'grid', gap: 14, alignContent: 'start' }} className="rb-comm-rail">
        <div className="rb-box" style={{ overflow: 'hidden', padding: 0 }}>
          <div style={{ height: 58, background: 'linear-gradient(120deg,#1b4f7e,#2f7bc0 55%,#6b3fa0)' }} />
          <div style={{ padding: 13 }}>
            <div className="rb-display" style={{ fontSize: 15, color: '#16324a' }}>Posting to r/RetroLabs</div>
            <div style={{ fontSize: 11, color: '#5a6b7b', margin: '6px 0 10px', lineHeight: 1.6 }}>
              Pick the board that fits. Good titles get more answers — &ldquo;How do I make a door open in Godot?&rdquo; beats &ldquo;help pls&rdquo;.
            </div>
          </div>
        </div>
        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head"><span>Boards</span></div>
          <div style={{ padding: 7 }}>
            {LAB_BOARDS.map((b) => (
              <button
                key={b}
                type="button"
                onClick={() => setBoard(b)}
                className="rb-clickable"
                style={{
                  display: 'flex', alignItems: 'center', gap: 9, padding: '7px 9px', borderRadius: 5, width: '100%',
                  textAlign: 'left', background: board === b ? BOARD_STYLE[b].bg : 'transparent', border: 'none', cursor: 'pointer',
                }}
              >
                <span style={{ width: 23, height: 23, borderRadius: '50%', background: '#fff', border: `1px solid ${BOARD_STYLE[b].color}`, color: BOARD_STYLE[b].color, fontSize: 9, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace", flexShrink: 0 }}>{'</>'}</span>
                <span>
                  <span style={{ display: 'block', fontSize: 12, color: '#1c4e7c' }}>{rBoard(b)}</span>
                  <span style={{ display: 'block', fontSize: 10, color: '#7b8896' }}>{BOARD_STYLE[b].blurb}</span>
                </span>
              </button>
            ))}
          </div>
        </div>
      </aside>

      {lightbox && <Lightbox src={lightbox} onClose={() => setLightbox(null)} />}
    </div>
  )
}

/* ================= RetroLabs post detail (/labs/[id]) ================= */

interface LabReplyT {
  id: string
  text: string
  createdAt: string
  likes: number
  myLike: boolean
  author: RetroUser
}

interface LabPostDetailT {
  id: string
  board: string
  title: string
  body: string
  videoUrl: string | null
  mediaJson: string
  codeFileId: string | null
  codeFileName: string | null
  views: number
  likes: number
  myLike: boolean
  likeIds: string // raw JSON array (the API returns it via the post spread)
  downIds: string
  editedAt: string | null
  createdAt: string
  author: RetroUser & { createdAt: string }
  replies: LabReplyT[]
}

export function LabDetailView({ id }: { id: string }) {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const [post, setPost] = useState<LabPostDetailT | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [reply, setReply] = useState('')
  const [busy, setBusy] = useState(false)
  const [lightbox, setLightbox] = useState<string | null>(null)

  // editing state
  const [editing, setEditing] = useState(false)
  const [editTitle, setEditTitle] = useState('')
  const [editBody, setEditBody] = useState('')
  const [editVideo, setEditVideo] = useState('')
  const [saving, setSaving] = useState(false)
  const editTaRef = useRef<HTMLTextAreaElement>(null)
  const editTitleRef = useRef<HTMLInputElement>(null)

  const load = useCallback(async () => {
    try {
      const res = await api<{ post: LabPostDetailT }>(`/api/labs/${id}`)
      setPost(res.post)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load post')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => { load() }, [load])

  useEffect(() => {
    if (post) document.title = `${post.title} - RetroBlox`
  }, [post])

  function voteState(): { myVote: number; score: number } {
    if (!post) return { myVote: 0, score: 0 }
    const meId = user?.id
    const ups = parseIds(post.likeIds)
    const downs = parseIds(post.downIds)
    const myVote = meId ? (ups.includes(meId) ? 1 : downs.includes(meId) ? -1 : 0) : 0
    return { myVote, score: ups.length - downs.length }
  }

  async function votePost(v: 1 | -1) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!post) return
    try {
      const res = await api<{ ups: number; downs: number; score: number; myVote: number }>(`/api/labs/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ vote: v }),
      })
      // the server returns the FINAL vote state — mirror it exactly:
      // myVote 1 → in ups, -1 → in downs, 0 → removed from both
      setPost({ ...post, likeIds: applyVote(post.likeIds, res.myVote === 1), downIds: applyVote(post.downIds, res.myVote === -1) })
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    }
  }

  // helper: set the local vote arrays to match the server response
  function applyVote(json: string, on: boolean): string {
    const meId = user?.id
    if (!meId) return json
    const arr = parseIds(json).filter((x) => x !== meId)
    if (on) arr.push(meId)
    return JSON.stringify(arr)
  }

  function parseIds(json: string): string[] {
    try { return JSON.parse(json || '[]') as string[] } catch { return [] }
  }

  function startEdit() {
    if (!post) return
    setEditTitle(post.title)
    setEditBody(post.body)
    setEditVideo(post.videoUrl || '')
    setEditing(true)
  }

  async function saveEdit() {
    if (!post) return
    if (editTitle.trim().length < 5) {
      flash(setToast, 'Title must be at least 5 characters.', 2200)
      return
    }
    setSaving(true)
    try {
      const res = await api<{ post: { title: string; body: string; videoUrl: string | null; editedAt: string } }>(`/api/labs/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: editTitle.trim(), body: editBody.trim(), videoUrl: editVideo.trim() }),
      })
      setPost({ ...post, title: res.post.title, body: res.post.body, videoUrl: res.post.videoUrl, editedAt: res.post.editedAt })
      setEditing(false)
      flash(setToast, 'Post updated!')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to save', 2400)
    } finally {
      setSaving(false)
    }
  }

  async function likeReply(replyId: string) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!post) return
    try {
      const res = await api<{ likes: number; myLike: boolean }>(`/api/labs/reply/${replyId}`, { method: 'PATCH' })
      setPost({ ...post, replies: post.replies.map((r) => (r.id === replyId ? { ...r, likes: res.likes, myLike: res.myLike } : r)) })
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    }
  }

  async function sendReply() {
    if (!reply.trim()) return
    setBusy(true)
    try {
      const res = await api<{ reply: LabReplyT }>(`/api/labs/${id}`, { method: 'POST', body: JSON.stringify({ text: reply.trim() }) })
      if (post) setPost({ ...post, replies: [...post.replies, { ...res.reply, likes: 0, myLike: false }] })
      setReply('')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to reply', 2400)
    } finally {
      setBusy(false)
    }
  }

  async function deletePost() {
    if (!post) return
    if (!window.confirm(`Really delete "${post.title}"?`)) return
    try {
      await api(`/api/labs/${id}`, { method: 'DELETE' })
      router.push('/labs')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    }
  }

  const replyTaRef = useRef<HTMLTextAreaElement>(null)

  if (loading) return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading post...</div>
  if (error || !post) {
    return (
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#a81a13' }}>
        {error || 'Post not found'}
        <div style={{ marginTop: 12 }}>
          <button className="rb-btn" onClick={() => router.push('/labs')}>Back to RetroLabs</button>
        </div>
      </div>
    )
  }

  const canManage = user && (user.id === post.author.id || user.role === 'admin')
  const { myVote, score } = voteState()

  return (
    <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', flexWrap: 'wrap' }}>
      <div style={{ flex: 1, minWidth: 300 }}>
        <div style={{ marginBottom: 10, fontSize: 12, color: '#7b8896' }}>
          <button className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 12 }} onClick={() => router.push('/labs')}>
            ← all posts
          </button>
          <span> / {rBoard(post.board)}</span>
        </div>

        {/* post */}
        <div className="rb-box" style={{ overflow: 'hidden' }}>
          <div className="rb-panel-head">
            <span style={{ display: 'inline-flex', gap: 9, alignItems: 'center', flexWrap: 'wrap' }}>
              <span className="rb-post-title-plain" style={{ fontSize: 17 }}><FxText text={post.title} /></span>
              <BoardChip board={post.board} />
            </span>
            <span style={{ fontSize: 11, color: '#7b8896', fontFamily: "'Source Sans Pro', sans-serif" }}>{fmtCount(post.views)} views</span>
          </div>
          <div style={{ display: 'flex', gap: 14, padding: 16, flexWrap: 'wrap' }}>
            <div style={{ width: 120, textAlign: 'center', flexShrink: 0 }}>
              <Link href={`/users/${post.author.id}`} style={{ display: 'inline-block', position: 'relative' }}>
                <Avatar user={post.author} size={90} />
                <span style={{ position: 'absolute', right: 2, bottom: 2 }}>
                  <OnlineDot online={post.author.online} />
                </span>
              </Link>
              <Link href={`/users/${post.author.id}`} className="rb-link" style={{ fontSize: 12, display: 'block', marginTop: 6 }}>
                {post.author.username}
              </Link>
              {post.author.role === 'admin' && <div style={{ marginTop: 4 }}><span className="rb-admin-badge">ADMIN</span></div>}
              <div style={{ fontSize: 10, marginTop: 4, color: '#7b8896' }}>Joined {new Date(post.author.createdAt).toLocaleDateString('en-US', { month: 'numeric', day: 'numeric', year: 'numeric' })}</div>
            </div>

            {/* vote column between the author card and the content, reddit-style */}
            <LabVoteCol myVote={myVote} score={score} onVote={(v) => votePost(v === 1 ? 1 : -1)} />

            <div style={{ flex: 1, minWidth: 240 }}>
              <div style={{ fontSize: 11, marginBottom: 9, color: '#7b8896', display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
                <span>Posted {timeAgo(post.createdAt)}</span>
                {post.editedAt && <span className="rb-edited-chip">· edited {timeAgo(post.editedAt)}</span>}
              </div>

              {editing ? (
                /* ---------------- EDIT MODE ---------------- */
                <div style={{ display: 'grid', gap: 12 }}>
                  <div>
                    <label style={{ fontSize: 12, color: '#24425f', display: 'block', marginBottom: 5 }} htmlFor="le-title">Title</label>
                    <input id="le-title" ref={editTitleRef} className="rb-input" style={{ width: '100%', fontSize: 14 }} value={editTitle} onChange={(e) => setEditTitle(e.target.value)} maxLength={120} />
                    <FxToolbar taRef={editTitleRef} value={editTitle} onChange={setEditTitle} />
                  </div>
                  <div>
                    <label style={{ fontSize: 12, color: '#24425f', display: 'block', marginBottom: 5 }} htmlFor="le-body">Post</label>
                    <textarea
                      id="le-body"
                      ref={editTaRef}
                      className="rb-textarea"
                      style={{ width: '100%', minHeight: 140, resize: 'vertical' }}
                      rows={9}
                      value={editBody}
                      onChange={(e) => setEditBody(e.target.value)}
                      maxLength={20000}
                    />
                    <FxToolbar taRef={editTaRef} value={editBody} onChange={setEditBody} livePreview />
                  </div>
                  <div>
                    <label style={{ fontSize: 12, color: '#24425f', display: 'block', marginBottom: 5 }} htmlFor="le-video">Video link</label>
                    <input id="le-video" className="rb-input" style={{ width: '100%' }} value={editVideo} onChange={(e) => setEditVideo(e.target.value)} placeholder="https://youtube.com/watch?v=..." />
                  </div>
                  <div style={{ display: 'flex', gap: 8 }}>
                    <button className="rb-btn rb-btn-green" onClick={saveEdit} disabled={saving} style={{ fontSize: 12 }}>
                      {saving ? 'Saving...' : 'Save changes'}
                    </button>
                    <button className="rb-btn" onClick={() => setEditing(false)} disabled={saving} style={{ fontSize: 12 }}>
                      Cancel
                    </button>
                  </div>
                </div>
              ) : (
                /* ---------------- READ MODE ---------------- */
                <>
                  <div style={{ fontSize: 13, color: '#2c3e50', lineHeight: 1.75, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                    <FxText text={post.body || '(no text)'} />
                  </div>
                  <LabsMediaGallery mediaJson={post.mediaJson} onPreview={setLightbox} />
                  {post.videoUrl && <VideoBox url={post.videoUrl} />}
                  {post.codeFileId && (
                    <div style={{ marginTop: 14, border: '1px solid #b99ad4', borderRadius: 6, background: '#f7f4fa', padding: 12, display: 'flex', alignItems: 'center', gap: 11, flexWrap: 'wrap' }}>
                      <span style={{ fontFamily: "'Courier New', Courier, monospace", fontSize: 15, color: '#6b3fa0' }}>&lt;/&gt;</span>
                      <div style={{ flex: 1, minWidth: 140 }}>
                        <div style={{ fontSize: 12, color: '#2c3e50' }}>{post.codeFileName || 'source.zip'}</div>
                        <div style={{ fontSize: 10, color: '#7b8896' }}>Source code — download it, read it, remix it</div>
                      </div>
                      <a className="rb-btn" href={`/api/files/${post.codeFileId}?dl=1`} download={post.codeFileName || 'source.zip'} style={{ textDecoration: 'none', fontSize: 11 }}>
                        Download Source
                      </a>
                    </div>
                  )}
                  <div style={{ marginTop: 12, display: 'flex', alignItems: 'center', gap: 9, flexWrap: 'wrap' }}>
                    {canManage && (
                      <button className="rb-btn" style={{ fontSize: 11, padding: '6px 13px' }} onClick={startEdit} title="Edit this post">
                        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                          <svg width="11" height="11" viewBox="0 0 16 16" aria-hidden="true"><path d="M11.3 1.6l3.1 3.1-8.4 8.4-3.9.8.8-3.9zM10 3l3 3" fill="none" stroke="#24425f" strokeWidth="1.3" strokeLinejoin="round" /></svg>
                          Edit Post
                        </span>
                      </button>
                    )}
                    {canManage && (
                      <button className="rb-btn rb-btn-red" style={{ fontSize: 10, padding: '6px 11px' }} onClick={deletePost}>Delete Post</button>
                    )}
                  </div>
                </>
              )}
            </div>
          </div>
        </div>

        {/* replies */}
        <div className="rb-box" style={{ marginTop: 14 }}>
          <div className="rb-panel-head"><span>Replies ({post.replies.length})</span></div>
          <div style={{ padding: 14 }}>
            {user && (
              <div style={{ display: 'flex', gap: 10, marginBottom: 16 }}>
                <Avatar user={user as RetroUser} size={38} />
                <div style={{ flex: 1 }}>
                  <textarea
                    ref={replyTaRef}
                    className="rb-textarea"
                    value={reply}
                    onChange={(e) => setReply(e.target.value)}
                    placeholder="Add to the discussion..."
                    rows={2}
                    style={{ width: '100%', resize: 'vertical' }}
                    maxLength={2000}
                    aria-label="Write a reply"
                  />
                  <FxToolbar taRef={replyTaRef} value={reply} onChange={setReply} />
                  <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 6 }}>
                    <button className="rb-btn rb-btn-green" onClick={sendReply} disabled={busy || !reply.trim()}>Post Reply</button>
                  </div>
                </div>
              </div>
            )}

            {post.replies.length === 0 && (
              <div style={{ fontSize: 12, padding: '8px 2px', color: '#7b8896' }}>No replies yet. Help this dev out!</div>
            )}

            {post.replies.map((r) => (
              <div key={r.id} style={{ display: 'flex', gap: 10, padding: '10px 0', borderTop: '1px solid #e4eaf0' }}>
                <Avatar user={r.author} size={36} />
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 7, flexWrap: 'wrap' }}>
                    <Link href={`/users/${r.author.id}`} className="rb-link" style={{ fontSize: 12 }}>{r.author.username}</Link>
                    {r.author.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                    <span style={{ fontSize: 11, color: '#7b8896' }}>{timeAgo(r.createdAt)}</span>
                  </div>
                  <div style={{ fontSize: 13, color: '#2c3e50', marginTop: 4, lineHeight: 1.6, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}><FxText text={r.text} /></div>
                  <div style={{ marginTop: 5 }}>
                    <LikeButton liked={r.myLike} count={r.likes} onClick={() => likeReply(r.id)} label="Like this reply" />
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* mini rail on detail */}
      <aside style={{ width: 300, flexShrink: 0, display: 'grid', gap: 14, alignContent: 'start' }} className="rb-comm-rail">
        <div className="rb-box" style={{ overflow: 'hidden', padding: 0 }}>
          <div style={{ height: 48, background: 'linear-gradient(120deg,#1b4f7e,#2f7bc0 55%,#6b3fa0)' }} />
          <div style={{ padding: 13 }}>
            <div className="rb-display" style={{ fontSize: 14, color: '#16324a' }}>r/RetroLabs — Dev Forum</div>
            <div style={{ fontSize: 11, color: '#5a6b7b', margin: '6px 0 11px', lineHeight: 1.6 }}>
              Post in the board that fits your question. Upvote helpful replies so good answers rise to the top.
            </div>
            <Link className="rb-btn rb-btn-green" href="/labs/new" style={{ textDecoration: 'none', display: 'block', textAlign: 'center', fontSize: 13, padding: '8px 0' }}>
              + Create Post
            </Link>
          </div>
        </div>
        <div className="rb-box" style={{ padding: 0 }}>
          <div className="rb-panel-head"><span>Workshop Rules</span></div>
          <ol style={{ margin: 0, padding: '10px 12px 12px 28px', fontSize: 11, color: '#5a6b7b', lineHeight: 1.9 }}>
            <li>Teach, don&apos;t gatekeep.</li>
            <li>Credit code you didn&apos;t write.</li>
            <li>Any engine is welcome here.</li>
            <li>Help beginners — you were one too.</li>
            <li>Ship things. Retro things.</li>
          </ol>
        </div>
      </aside>

      {lightbox && <Lightbox src={lightbox} onClose={() => setLightbox(null)} />}
    </div>
  )
}

/* heart-style like pill for replies */
function LikeButton({ liked, count, onClick, label }: { liked: boolean; count: number; onClick: () => void; label: string }) {
  return (
    <button type="button" className={`rb-like-btn${liked ? ' rb-liked' : ''}`} onClick={onClick} aria-pressed={liked} title={label} style={{ fontSize: 11, padding: '4px 11px' }}>
      <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true">
        <path
          d="M8 14s-6-3.7-6-7.6C2 4 3.7 2.5 5.6 2.5 6.9 2.5 7.7 3.2 8 4c.3-.8 1.1-1.5 2.4-1.5C12.3 2.5 14 4 14 6.4 14 10.3 8 14 8 14z"
          fill={liked ? '#e0448c' : 'none'}
          stroke={liked ? '#b02a72' : '#7b8896'}
          strokeWidth="1.2"
        />
      </svg>
      {count}
    </button>
  )
}
