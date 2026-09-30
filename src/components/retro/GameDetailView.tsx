'use client'

import { Fragment, useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, fmtDate, fmtCount, timeAgo, type RetroUser } from '@/lib/store'
import { FxToolbar, FxText } from '@/lib/textfx'
import { Avatar, OnlineDot } from './Shell'
import { GameSummary, ThumbIcon } from './HomeView'
import { mediaRender } from './ChatView'
import { RetroVideoPlayer } from './RetroVideoPlayer'

interface CommentT {
  id: string
  text: string
  parentId?: string | null
  createdAt: string
  mediaFileId?: string | null
  mediaType?: string | null
  mediaName?: string | null
  rating?: number | null
  rec?: number | null
  upIds?: string | string[]
  user: { id: string; username: string; avatarUrl: string | null; role?: string; online?: boolean; lastSeen: string }
}

interface GameMedia {
  fileId: string
  type: string // "video" | "image"
  name: string
}

interface GameDetail extends Omit<GameSummary, 'creator'> {
  description: string
  fileId: string | null
  fileName: string | null
  sourceFileId: string | null
  sourceFileName: string | null
  favorites: number
  views: number
  gem: boolean
  media: GameMedia[]
  group: { id: string; name: string } | null
  comments: CommentT[]
  myLike: number
  myFavorite: boolean
  isOwner: boolean
  reviewStats: {
    avgRating: number | null
    positivePct: number | null
    reviewCount: number
    recCount: number
    notRecCount: number
  }
  playtime?: {
    totalSeconds: number
    players: number
    sessions: number
    avgSeconds: number
  }
  creator: GameSummary['creator'] & { role?: string; createdAt?: string; lastSeen?: string }
}

/* seconds -> "1h 23m" / "45m" for the playtime stat row */
function fmtDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  return h > 0 ? `${h}h ${m}m` : `${Math.max(1, m)}m`
}

function parseUpIds(v: string | string[] | undefined | null): string[] {
  if (Array.isArray(v)) return v
  if (!v) return []
  try {
    const p = JSON.parse(v)
    return Array.isArray(p) ? p : []
  } catch {
    return []
  }
}

export function GameDetailView({ id }: { id: string }) {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const isAdmin = user?.role === 'admin'
  const [game, setGame] = useState<GameDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [downloaded, setDownloaded] = useState(false)
  const [busy, setBusy] = useState(false)

  /* Steam-style media gallery index */
  const [mediaIdx, setMediaIdx] = useState(0)

  /* review composer state */
  const [reviewText, setReviewText] = useState('')
  const [reviewRec, setReviewRec] = useState<1 | 0 | null>(null)
  const [reviewStars, setReviewStars] = useState<number | null>(null)
  const [reviewFile, setReviewFile] = useState<File | null>(null)
  const reviewFileRef = useRef<HTMLInputElement>(null)
  const reviewTaRef = useRef<HTMLTextAreaElement>(null)
  const replyTaRef = useRef<HTMLTextAreaElement>(null)
  const [postingReview, setPostingReview] = useState(false)
  const [helpfulMarked, setHelpfulMarked] = useState<Record<string, boolean>>({})
  /* replies: which review is the reply box open under + the draft text */
  const [replyTo, setReplyTo] = useState<string | null>(null)
  const [replyText, setReplyText] = useState('')
  const [postingReply, setPostingReply] = useState(false)

  const [mediaFile, setMediaFile] = useState<File | null>(null)
  const mediaInputRef = useRef<HTMLInputElement>(null)
  const [updating, setUpdating] = useState(false)
  const updateFileRef = useRef<HTMLInputElement>(null)
  const updateSrcRef = useRef<HTMLInputElement>(null)

  const load = useCallback(async () => {
    try {
      const res = await api<{ game: GameDetail }>(`/api/games/${id}`)
      setGame(res.game)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load game')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => {
    load()
    setDownloaded(localStorage.getItem(`rb_dl_${id}`) === '1')
  }, [load, id])

  /* one view per browser session per game (dev analytics feed off this) */
  useEffect(() => {
    if (!id) return
    const key = `rb_view_${id}`
    if (sessionStorage.getItem(key)) return
    sessionStorage.setItem(key, '1')
    api(`/api/games/${id}/view`, { method: 'POST' }).catch(() => {})
  }, [id])

  /* real per-page tab title once the game loads */
  useEffect(() => {
    if (game) document.title = `${game.name} - RetroBlox`
  }, [game])

  /* ---- download / play / re-download ---- */

  async function doDownload() {
    if (!user) {
      router.push('/login')
      return
    }
    if (!game || busy) return
    setBusy(true)
    try {
      const res = await api<{ downloads: number; fileUrl: string }>(`/api/games/${game.id}/download`, {
        method: 'POST',
      })
      triggerFile(res.fileUrl, game.fileName || 'game')
      localStorage.setItem(`rb_dl_${game.id}`, '1')
      setDownloaded(true)
      setGame({ ...game, downloads: res.downloads })
      setToast('Download started! Check your downloads folder.')
      setTimeout(() => setToast(null), 2600)
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Download failed')
      setTimeout(() => setToast(null), 2600)
    } finally {
      setBusy(false)
    }
  }

  function playNow() {
    if (!game?.fileId) return
    // log the play for "Games You've Played" (best-effort)
    if (user) {
      api(`/api/games/${game.id}/play`, { method: 'POST' }).catch(() => {})
    }
    window.open(`/api/files/${game.fileId}`, '_blank')
  }

  function triggerFile(url: string, name: string) {
    const a = document.createElement('a')
    a.href = url
    a.download = name
    document.body.appendChild(a)
    a.click()
    a.remove()
  }

  /* ---- like / favorite ---- */

  async function vote(value: 1 | -1) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!game) return
    try {
      const res = await api<{ likes: number; dislikes: number; rating: number | null; myLike: number }>(
        `/api/games/${game.id}/like`,
        { method: 'POST', body: JSON.stringify({ value }) }
      )
      setGame({ ...game, ...res })
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Vote failed')
      setTimeout(() => setToast(null), 2200)
    }
  }

  async function toggleFavorite() {
    if (!user) {
      router.push('/login')
      return
    }
    if (!game) return
    try {
      const res = await api<{ favorites: number; myFavorite: boolean }>(`/api/games/${game.id}/favorite`, {
        method: 'POST',
      })
      setGame({ ...game, ...res })
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Failed')
      setTimeout(() => setToast(null), 2200)
    }
  }

  /* ---- Steam-style reviews ---- */

  async function postReview() {
    if (!user) {
      router.push('/login')
      return
    }
    if (!game || !reviewText.trim() || reviewRec === null) return
    setPostingReview(true)
    try {
      const fd = new FormData()
      fd.append('text', reviewText.trim())
      fd.append('rec', String(reviewRec))
      if (reviewStars !== null) fd.append('rating', String(reviewStars))
      if (reviewFile) fd.append('file', reviewFile)
      const res = await api<{ comment: CommentT }>(`/api/games/${game.id}/comments`, {
        method: 'POST',
        body: fd,
      })
      setGame({ ...game, comments: [res.comment, ...game.comments] })
      setReviewText('')
      setReviewRec(null)
      setReviewStars(null)
      setReviewFile(null)
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Failed to review')
      setTimeout(() => setToast(null), 2200)
    } finally {
      setPostingReview(false)
    }
  }

  async function markHelpful(c: CommentT) {
    if (!user) {
      router.push('/login')
      return
    }
    try {
      const res = await api<{ helpful: number; marked: boolean }>(`/api/games/${game?.id}/comments/${c.id}`, { method: 'POST' })
      setGame((g) => {
        if (!g) return g
        return {
          ...g,
          comments: g.comments.map((x) => (x.id === c.id ? { ...x, upIds: JSON.stringify(Array(res.helpful).fill('x')) } : x)),
        }
      })
      // keep a local "my vote" memory for instant UI feedback
      const key = `rb_helpful_${c.id}`
      localStorage.setItem(key, res.marked ? '1' : '0')
      setHelpfulMarked((m) => ({ ...m, [c.id]: res.marked }))
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Failed')
      setTimeout(() => setToast(null), 2200)
    }
  }

  async function delReview(cid: string) {
    if (!game) return
    if (!window.confirm('Delete this review?')) return
    try {
      await api(`/api/games/${game.id}/comments/${cid}`, { method: 'DELETE' })
      setGame({ ...game, comments: game.comments.filter((c) => c.id !== cid && c.parentId !== cid) })
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Failed to delete')
      setTimeout(() => setToast(null), 2200)
    }
  }

  async function postReply(parentId: string) {
    if (!user) {
      router.push('/login')
      return
    }
    if (!game || !replyText.trim()) return
    setPostingReply(true)
    try {
      const fd = new FormData()
      fd.append('text', replyText.trim())
      fd.append('parentId', parentId)
      const res = await api<{ comment: CommentT }>(`/api/games/${game.id}/comments`, {
        method: 'POST',
        body: fd,
      })
      setGame({ ...game, comments: [...game.comments, res.comment] })
      setReplyTo(null)
      setReplyText('')
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Failed to reply')
      setTimeout(() => setToast(null), 2200)
    } finally {
      setPostingReply(false)
    }
  }

  /* ---- owner updates ---- */

  async function updateGame(includeBuild: boolean, includeSource: boolean) {
    if (!game) return
    const build = includeBuild ? updateFileRef.current?.files?.[0] : null
    const source = includeSource ? updateSrcRef.current?.files?.[0] : null
    if (includeBuild && !build) {
      setToast('Choose a new build file first!')
      setTimeout(() => setToast(null), 2200)
      return
    }
    setUpdating(true)
    try {
      const fd = new FormData()
      if (build) fd.append('gameFile', build)
      if (source) fd.append('sourceFile', source)
      if (!includeBuild && !includeSource && mediaFile) fd.append('media', mediaFile)
      await api(`/api/games/${game.id}`, { method: 'PATCH', body: fd })
      setToast('Game updated!')
      setTimeout(() => setToast(null), 2200)
      localStorage.removeItem(`rb_dl_${game.id}`)
      setDownloaded(false)
      setMediaFile(null)
      await load()
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Update failed')
      setTimeout(() => setToast(null), 2600)
    } finally {
      setUpdating(false)
    }
  }

  async function addMedia() {
    if (!game) return
    const f = mediaInputRef.current?.files?.[0]
    if (!f) {
      setToast('Pick a video or screenshot first!')
      setTimeout(() => setToast(null), 2200)
      return
    }
    setUpdating(true)
    try {
      const fd = new FormData()
      fd.append('media', f)
      await api(`/api/games/${game.id}`, { method: 'PATCH', body: fd })
      setToast('Media added to the gallery!')
      setTimeout(() => setToast(null), 2200)
      setMediaFile(null)
      if (mediaInputRef.current) mediaInputRef.current.value = ''
      await load()
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Upload failed')
      setTimeout(() => setToast(null), 2600)
    } finally {
      setUpdating(false)
    }
  }

  async function toggleGem() {
    if (!game || !isAdmin) return
    try {
      const res = await api<{ gem: boolean }>(`/api/games/${game.id}/gem`, { method: 'POST' })
      setGame({ ...game, gem: res.gem })
      setToast(res.gem ? 'Marked as a Hidden Gem! 💎' : 'Removed from Hidden Gems.')
      setTimeout(() => setToast(null), 2400)
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Failed')
      setTimeout(() => setToast(null), 2200)
    }
  }

  async function deleteGame() {
    if (!game) return
    if (!window.confirm(`Really delete "${game.name}" forever?`)) return
    try {
      await api(`/api/games/${game.id}`, { method: 'DELETE' })
      setToast(game.isOwner ? 'Game deleted.' : 'Game removed by administrator.')
      router.push('/')
    } catch (e) {
      setToast(e instanceof Error ? e.message : 'Delete failed')
      setTimeout(() => setToast(null), 2200)
    }
  }

  if (loading) {
    return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading game...</div>
  }
  if (error || !game) {
    return (
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#a81a13' }}>
        {error || 'Game not found'}
        <div style={{ marginTop: 12 }}>
          <button className="rb-btn" onClick={() => router.push('/games')}>
            Browse Games
          </button>
        </div>
      </div>
    )
  }

  const totalVotes = game.likes + game.dislikes
  const likePct = totalVotes > 0 ? Math.round((game.likes / totalVotes) * 100) : 0

  /* Steam-style media strip: thumbnail + uploaded media (videos play inline) */
  const gallery: { key: string; type: 'image' | 'video'; src: string; name: string }[] = []
  if (game.thumbnailUrl) gallery.push({ key: 'thumb', type: 'image', src: game.thumbnailUrl, name: 'Thumbnail' })
  for (const m of game.media) {
    gallery.push({ key: m.fileId, type: m.type === 'video' ? 'video' : 'image', src: `/api/files/${m.fileId}`, name: m.name })
  }
  if (gallery.length === 0 && game.iconUrl) gallery.push({ key: 'icon', type: 'image', src: game.iconUrl, name: 'Icon' })
  const active = gallery[Math.min(mediaIdx, gallery.length - 1)]
  /* derive Steam-style stats from the live comment list so posting a review
     updates the summary instantly (server stats are the fallback seed) */
  const rated = game.comments.filter((c) => c.rec === 1 || c.rec === 0)
  const starred = game.comments.filter((c) => typeof c.rating === 'number')
  const rs = {
    avgRating: starred.length > 0 ? Math.round((starred.reduce((s, c) => s + (c.rating || 0), 0) / starred.length) * 10) / 10 : null,
    positivePct: rated.length > 0 ? Math.round((rated.filter((c) => c.rec === 1).length / rated.length) * 100) : null,
    reviewCount: rated.length,
    recCount: rated.filter((c) => c.rec === 1).length,
    notRecCount: rated.filter((c) => c.rec === 0).length,
  }

  return (
    <div>
      {/* breadcrumb */}
      <div style={{ marginBottom: 8, fontSize: 11, color: '#5a6b7b' }}>
        <button className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 11 }} onClick={() => router.push('/games')}>
          Games
        </button>
        {' › '}
        <button
          className="rb-link"
          style={{ background: 'none', border: 'none', padding: 0, fontSize: 11 }}
          onClick={() => router.push(`/games?genre=${encodeURIComponent(game.genre)}`)}
        >
          {game.genre}
        </button>
        {' › '}
        <span style={{ color: '#24425f' }}><FxText text={game.name} /></span>
        {game.gem && (
          <span title="An admin marked this game as a Hidden Gem" style={{ marginLeft: 8, fontSize: 10, color: '#8a6d1a', background: '#fdf3d7', border: '1px solid #d9c26a', borderRadius: 8, padding: '1px 8px' }}>
            💎 Hidden Gem
          </span>
        )}
      </div>

      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
        {/* LEFT: media + description + reviews */}
        <div style={{ flex: '1 1 520px', minWidth: 300 }}>
          {/* ---- Steam-style media gallery ---- */}
          <div className="rb-box" style={{ padding: 8 }}>
            <div style={{ aspectRatio: '16/9', background: '#dde5ec', border: '1px solid #c3cdd7', overflow: 'hidden' }}>
              {!active ? (
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#7b8896', font: 'bold 20px Verdana' }}>
                  <FxText text={game.name} />
                </div>
              ) : active.type === 'video' ? (
                <RetroVideoPlayer src={active.src} title={active.name} />
              ) : (
                <img src={active.src} alt={active.name} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
              )}
            </div>

            {gallery.length > 1 && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6 }}>
                <button
                  className="rb-btn"
                  style={{ fontSize: 11, padding: '4px 8px', flexShrink: 0 }}
                  onClick={() => setMediaIdx((i) => (i - 1 + gallery.length) % gallery.length)}
                  aria-label="Previous media"
                >
                  ‹
                </button>
                <div style={{ display: 'flex', gap: 6, overflowX: 'auto', flex: 1 }}>
                  {gallery.map((gItem, i) => (
                    <button
                      key={gItem.key}
                      type="button"
                      className="rb-clickable"
                      onClick={() => setMediaIdx(i)}
                      aria-label={`Show media ${i + 1}`}
                      style={{
                        position: 'relative',
                        width: 86,
                        aspectRatio: '16/9',
                        flexShrink: 0,
                        padding: 0,
                        overflow: 'hidden',
                        border: i === mediaIdx ? '2px solid #2f7bc0' : '1px solid #c3cdd7',
                        background: '#dde5ec',
                        cursor: 'pointer',
                      }}
                    >
                      {gItem.type === 'video' ? (
                        <>
                          <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#16202c' }}>
                            <svg width="16" height="16" viewBox="0 0 16 16"><path d="M4 2.5l9 5.5-9 5.5z" fill="#fff" /></svg>
                          </span>
                          <span style={{ position: 'absolute', left: 2, bottom: 2, fontSize: 7, color: '#fff', background: 'rgba(225,35,26,.85)', borderRadius: 2, padding: '0 3px' }}>VIDEO</span>
                        </>
                      ) : (
                        <img src={gItem.src} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                      )}
                    </button>
                  ))}
                </div>
                <button
                  className="rb-btn"
                  style={{ fontSize: 11, padding: '4px 8px', flexShrink: 0 }}
                  onClick={() => setMediaIdx((i) => (i + 1) % gallery.length)}
                  aria-label="Next media"
                >
                  ›
                </button>
              </div>
            )}
          </div>

          {/* description */}
          <div className="rb-box" style={{ marginTop: 12 }}>
            <div className="rb-panel-head"><span>Description</span></div>
            <div style={{ padding: '10px 12px', fontSize: 12, lineHeight: 1.65, whiteSpace: 'pre-wrap', color: '#2c3e50' }}>
              {game.description ? <FxText text={game.description} /> : 'No description provided.'}
            </div>
            <div style={{ padding: '6px 12px 10px', display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              <Tag>{`Maturity: ${game.maturity}`}</Tag>
              <Tag>{`Engine: ${game.engine}`}</Tag>
              {game.subgenre && <Tag>{game.subgenre}</Tag>}
            </div>
          </div>

          {/* source code (GitHub-style) */}
          {game.sourceFileId && (
            <div className="rb-box" style={{ marginTop: 12 }}>
              <div className="rb-panel-head"><span>Source Code</span></div>
              <div style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
                <span style={{ fontSize: 20 }}>&lt;/&gt;</span>
                <div style={{ flex: 1, minWidth: 140 }}>
                  <div style={{ font: 'bold 12px Verdana', color: '#24425f' }}>{game.sourceFileName || 'source.zip'}</div>
                  <div style={{ fontSize: 10, color: '#7b8896' }}>Open-sourced by the creator — fork it, remix it!</div>
                </div>
                <a
                  className="rb-btn"
                  href={`/api/files/${game.sourceFileId}?dl=1`}
                  download={game.sourceFileName || 'source.zip'}
                >
                  Download Source
                </a>
              </div>
            </div>
          )}

          {/* ---- Steam-style reviews ---- */}
          <div className="rb-box" style={{ marginTop: 12 }}>
            <div className="rb-panel-head"><span>Reviews ({rs.reviewCount})</span></div>

            {/* summary strip */}
            <div
              style={{
                padding: '12px 14px',
                display: 'flex',
                alignItems: 'center',
                gap: 16,
                flexWrap: 'wrap',
                borderBottom: '1px solid #e4eaf0',
                background: 'linear-gradient(180deg,#f6f9fc,#eef3f8)',
              }}
            >
              <div style={{ textAlign: 'center' }}>
                <div style={{ font: 'bold 30px Verdana', color: '#24425f', lineHeight: 1 }}>
                  {rs.avgRating !== null ? rs.avgRating.toFixed(1) : '0.0'}
                  <span style={{ fontSize: 15, color: '#7b8896' }}> / 5</span>
                </div>
                <div style={{ fontSize: 9, color: '#7b8896', marginTop: 2 }}>player rating</div>
              </div>
              <div style={{ flex: 1, minWidth: 160 }}>
                <div style={{ fontSize: 11, color: '#24425f', marginBottom: 4 }}>
                  {rs.positivePct !== null
                    ? `${rs.positivePct >= 80 ? 'Mostly Positive' : rs.positivePct >= 50 ? 'Mixed' : 'Mostly Negative'} — ${rs.positivePct}% of ${rs.reviewCount} review${rs.reviewCount === 1 ? '' : 's'} recommend this game`
                    : 'No reviews yet — play it and be the first!'}
                </div>
                <div className="rb-ratio" style={{ height: 10 }}>
                  <div style={{ width: `${rs.positivePct ?? 0}%` }} />
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 9, color: '#7b8896', marginTop: 3 }}>
                  <span style={{ color: '#2c6e31' }}>👍 {rs.recCount} recommend</span>
                  <span style={{ color: '#a03a34' }}>👎 {rs.notRecCount} do not</span>
                </div>
              </div>
            </div>

            {/* review composer */}
            <div style={{ padding: 10 }}>
              {user ? (
                <div style={{ marginBottom: 14 }}>
                  <div style={{ fontSize: 11, color: '#24425f', marginBottom: 6 }}>Write a review</div>

                  {/* recommend / not recommend thumbs */}
                  <div style={{ display: 'flex', gap: 8, marginBottom: 8, flexWrap: 'wrap' }}>
                    <button
                      type="button"
                      className="rb-clickable"
                      onClick={() => setReviewRec(reviewRec === 1 ? null : 1)}
                      aria-pressed={reviewRec === 1}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 6,
                        padding: '7px 14px',
                        borderRadius: 4,
                        border: '1px solid',
                        borderColor: reviewRec === 1 ? '#4c9e34' : '#b4c2cf',
                        background: reviewRec === 1 ? 'linear-gradient(180deg,#e7f7dd,#c8ecb4)' : '#f4f8fb',
                        fontSize: 11,
                        color: '#24425f',
                      }}
                    >
                      <ThumbIcon up /> Recommend
                    </button>
                    <button
                      type="button"
                      className="rb-clickable"
                      onClick={() => setReviewRec(reviewRec === 0 ? null : 0)}
                      aria-pressed={reviewRec === 0}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 6,
                        padding: '7px 14px',
                        borderRadius: 4,
                        border: '1px solid',
                        borderColor: reviewRec === 0 ? '#c0392b' : '#b4c2cf',
                        background: reviewRec === 0 ? 'linear-gradient(180deg,#fde3e0,#f6b8b1)' : '#f4f8fb',
                        fontSize: 11,
                        color: '#24425f',
                      }}
                    >
                      <ThumbIcon /> Not Recommended
                    </button>

                    {/* 0-5 stars */}
                    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 2, marginLeft: 'auto' }} role="radiogroup" aria-label="Star rating">
                      <span style={{ fontSize: 10, color: '#5a6b7b', marginRight: 4 }}>Rating:</span>
                      {[1, 2, 3, 4, 5].map((n) => (
                        <button
                          key={n}
                          type="button"
                          onClick={() => setReviewStars(reviewStars === n ? null : n)}
                          aria-label={`${n} star${n === 1 ? '' : 's'}`}
                          style={{ background: 'none', border: 'none', padding: 1, cursor: 'pointer' }}
                        >
                          <StarIcon filled={reviewStars !== null && reviewStars >= n} half={reviewStars !== null && reviewStars === n - 0.5} />
                        </button>
                      ))}
                      <span style={{ fontSize: 10, color: '#7b8896', marginLeft: 4 }}>
                        {reviewStars !== null ? `${reviewStars}/5` : 'none'}
                      </span>
                    </div>
                  </div>

                  <div style={{ display: 'flex', gap: 8 }}>
                    <Avatar user={user as RetroUser} size={36} />
                    <div style={{ flex: 1 }}>
                      <textarea
                        ref={reviewTaRef}
                        className="rb-textarea"
                        value={reviewText}
                        onChange={(e) => setReviewText(e.target.value)}
                        placeholder={reviewRec === 0 ? 'Tell everyone why you do NOT recommend it...' : 'Tell everyone what you thought — recommend it or roast it...'}
                        rows={2}
                        style={{ width: '100%', resize: 'vertical' }}
                        maxLength={500}
                        aria-label="Write a review"
                      />
                      <FxToolbar taRef={reviewTaRef} value={reviewText} onChange={setReviewText} />
                      {reviewFile && (
                        <div className="rb-chat-attach-chip" style={{ marginTop: 5 }}>
                          <span>
                            {reviewFile.name.length > 32 ? `${reviewFile.name.slice(0, 32)}...` : reviewFile.name} ({Math.ceil(reviewFile.size / 1024)} KB)
                          </span>
                          <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10 }} onClick={() => setReviewFile(null)}>
                            remove
                          </button>
                        </div>
                      )}
                      <div style={{ display: 'flex', justifyContent: 'flex-end', alignItems: 'center', gap: 6, marginTop: 5 }}>
                        <span style={{ fontSize: 9, color: '#7b8896', marginRight: 'auto' }}>
                          Screenshots, videos and audio welcome
                        </span>
                        <input
                          ref={reviewFileRef}
                          type="file"
                          accept="image/*,video/*,audio/*"
                          style={{ display: 'none' }}
                          onChange={(e) => {
                            const f = e.target.files?.[0]
                            if (f) setReviewFile(f)
                            e.target.value = ''
                          }}
                        />
                        <button className="rb-btn" style={{ fontSize: 10 }} onClick={() => reviewFileRef.current?.click()} type="button">
                          + File
                        </button>
                        <button
                          className="rb-btn rb-btn-green"
                          onClick={postReview}
                          disabled={!reviewText.trim() || reviewRec === null || postingReview}
                          type="button"
                          title={reviewRec === null ? 'Pick Recommend or Not Recommended first' : undefined}
                        >
                          Post Review
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              ) : (
                <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 12 }}>
                  <button className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 11 }} onClick={() => router.push('/login')}>
                    Log in
                  </button>{' '}
                  to write a review!
                </div>
              )}

              {game.comments.length === 0 && (
                <div style={{ color: '#7b8896', fontSize: 11, padding: '6px 2px' }}>No reviews yet. Be the first!</div>
              )}

              {game.comments.filter((c) => !c.parentId).map((c) => {
                const ups = parseUpIds(c.upIds)
                const myHelpful = !!helpfulMarked[c.id]
                const replies = game.comments.filter((r) => r.parentId === c.id)
                const replyOpen = replyTo === c.id
                return (
                  <Fragment key={c.id}>
                  <div style={{ display: 'flex', gap: 8, padding: '10px 0', borderTop: '1px solid #e4eaf0' }}>
                    <Avatar user={c.user} size={36} />
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                        <button
                          className="rb-link"
                          style={{ background: 'none', border: 'none', padding: 0, font: 'bold 11px Verdana' }}
                          onClick={() => router.push(`/users/${c.user.id}`)}
                        >
                          {c.user.username}
                        </button>
                        {c.user.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                        {c.user.id === game.creator.id && <Tag small>CREATOR</Tag>}
                        {c.rec !== null && c.rec !== undefined ? (
                          <span
                            style={{
                              fontSize: 9,
                              padding: '1px 8px',
                              borderRadius: 8,
                              border: `1px solid ${c.rec === 1 ? '#4c9e34' : '#c0392b'}`,
                              background: c.rec === 1 ? '#e8f5e4' : '#fbe3e0',
                              color: c.rec === 1 ? '#2c6e31' : '#a03a34',
                            }}
                          >
                            {c.rec === 1 ? '👍 Recommended' : '👎 Not Recommended'}
                          </span>
                        ) : null}
                        {typeof c.rating === 'number' && (
                          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 1 }}>
                            {[1, 2, 3, 4, 5].map((n) => (
                              <StarIcon key={n} filled={c.rating !== null && c.rating !== undefined && c.rating >= n} size={11} />
                            ))}
                            <span style={{ fontSize: 9, color: '#7b8896', marginLeft: 3 }}>{c.rating}/5</span>
                          </span>
                        )}
                        <span style={{ fontSize: 10, color: '#7b8896' }}>{timeAgo(c.createdAt)}</span>
                      </div>
                      <div style={{ fontSize: 12, color: '#2c3e50', marginTop: 3, lineHeight: 1.5, whiteSpace: 'pre-wrap' }}><FxText text={c.text} /></div>
                      {mediaRender(c.mediaFileId ?? null, c.mediaType ?? null, c.mediaName)}

                      {/* helpful row */}
                      <div style={{ marginTop: 5, display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
                        <button
                          type="button"
                          className="rb-like-btn"
                          onClick={() => markHelpful(c)}
                          aria-pressed={!!myHelpful}
                          style={{ color: myHelpful ? '#2c6e31' : '#5a6b7b' }}
                        >
                          <ThumbIcon up /> Helpful ({ups.length})
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
                        {(user?.id === c.user.id || isAdmin) && (
                          <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10, color: '#a03a34' }} onClick={() => delReview(c.id)}>
                            ✕ delete
                          </button>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* replies under this review */}
                  {replies.length > 0 && (
                    <div style={{ marginLeft: 44, marginBottom: 8, display: 'grid', gap: 8 }}>
                      {replies.map((r) => (
                        <div key={r.id} style={{ display: 'flex', gap: 8 }}>
                          <Avatar user={r.user} size={26} />
                          <div style={{ flex: 1 }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                              <button
                                className="rb-link"
                                style={{ background: 'none', border: 'none', padding: 0, font: 'bold 11px Verdana' }}
                                onClick={() => router.push(`/users/${r.user.id}`)}
                              >
                                {r.user.username}
                              </button>
                              {r.user.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                              <span style={{ fontSize: 10, color: '#7b8896' }}>{timeAgo(r.createdAt)}</span>
                            </div>
                            <div style={{ fontSize: 12, color: '#2c3e50', marginTop: 2, lineHeight: 1.5, whiteSpace: 'pre-wrap' }}><FxText text={r.text} /></div>
                            {mediaRender(r.mediaFileId ?? null, r.mediaType ?? null, r.mediaName)}
                            {(user?.id === r.user.id || isAdmin) && (
                              <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 9, color: '#a03a34', marginTop: 2 }} onClick={() => delReview(r.id)}>
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
                    <div style={{ marginLeft: 44, marginBottom: 10, display: 'flex', gap: 8 }}>
                      <Avatar user={user as RetroUser} size={26} />
                      <div style={{ flex: 1 }}>
                        <textarea
                          ref={replyTaRef}
                          className="rb-textarea"
                          value={replyText}
                          onChange={(e) => setReplyText(e.target.value)}
                          rows={2}
                          maxLength={500}
                          placeholder={`Replying to ${c.user.username}...`}
                          style={{ width: '100%', resize: 'vertical' }}
                          aria-label="Write a reply"
                          autoFocus
                        />
                        <FxToolbar taRef={replyTaRef} value={replyText} onChange={setReplyText} />
                        <div style={{ display: 'flex', gap: 6, marginTop: 4 }}>
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
                  </Fragment>
                )
              })}
            </div>
          </div>
        </div>

        {/* RIGHT: title + actions + info */}
        <div style={{ flex: '1 1 300px', minWidth: 280 }}>
          <div className="rb-box" style={{ padding: 14 }}>
            <h1 style={{ font: 'bold 22px Verdana', color: '#1c2733', margin: 0, lineHeight: 1.25 }}><FxText text={game.name} /></h1>
            {game.group && (
              <div style={{ marginTop: 6 }}>
                <Link
                  href={`/groups/${game.group.id}`}
                  className="rb-link"
                  style={{ fontSize: 11, textDecoration: 'none', display: 'inline-flex', alignItems: 'center', gap: 4 }}
                >
                  <GroupGlyph /> {game.group.name}
                </Link>
              </div>
            )}

            {/* By Developer — click through to the dev's profile */}
            <div
              style={{
                marginTop: 10,
                border: '1px solid #c3cdd7',
                borderRadius: 4,
                background: 'linear-gradient(180deg,#f6f9fc,#e9eff5)',
                padding: '8px 10px',
                display: 'flex',
                alignItems: 'center',
                gap: 10,
              }}
            >
              <Avatar user={game.creator} size={40} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 10, color: '#5a6b7b', letterSpacing: '0.4px' }}>BY DEVELOPER</div>
                <Link
                  href={`/users/${game.creator.id}`}
                  className="rb-link"
                  style={{ fontSize: 13, display: 'inline-flex', alignItems: 'center', gap: 6 }}
                >
                  {game.creator.username}
                  {game.creator.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                </Link>
              </div>
              <Link
                href={`/users/${game.creator.id}`}
                className="rb-btn"
                style={{ textDecoration: 'none', fontSize: 10, padding: '4px 10px', flexShrink: 0 }}
              >
                View Profile
              </Link>
            </div>

            <div style={{ marginTop: 8, fontSize: 11, color: '#7b8896' }}>Maturity: {game.maturity}</div>

            {/* PLAY / DOWNLOAD button */}
            <div style={{ marginTop: 14 }}>
              {downloaded ? (
                <>
                  <button
                    className="rb-btn rb-btn-green"
                    onClick={playNow}
                    style={{ width: '100%', fontSize: 16, padding: '11px 0', borderRadius: 5 }}
                  >
                    ▶ Play now
                  </button>
                  <button
                    className="rb-link"
                    onClick={doDownload}
                    disabled={busy}
                    style={{
                      display: 'block',
                      margin: '7px auto 0',
                      background: 'none',
                      border: 'none',
                      font: 'bold 11px Verdana',
                      padding: 0,
                      textDecoration: 'underline',
                    }}
                  >
                    {busy ? 'Preparing...' : 'Re-Download'}
                  </button>
                </>
              ) : (
                <button
                  className="rb-btn rb-btn-green"
                  onClick={doDownload}
                  disabled={busy}
                  style={{ width: '100%', fontSize: 16, padding: '11px 0', borderRadius: 5 }}
                >
                  {busy ? 'Preparing...' : '⬇ Download'}
                </button>
              )}
              {game.fileName && (
                <div style={{ textAlign: 'center', fontSize: 10, color: '#7b8896', marginTop: 6 }}>
                  {game.fileName} — opens with its own engine ({game.engine})
                </div>
              )}
            </div>

            {/* favorite / like bar */}
            <div style={{ marginTop: 14, display: 'flex', alignItems: 'stretch', gap: 8 }}>
              <button
                onClick={toggleFavorite}
                className="rb-clickable"
                style={{
                  flex: 1,
                  background: game.myFavorite ? 'linear-gradient(180deg,#fff3c4,#ffe082)' : 'linear-gradient(180deg,#fff,#dbe4ec)',
                  border: '1px solid #8ba4b8',
                  borderRadius: 4,
                  padding: '7px 4px',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  gap: 3,
                }}
                aria-pressed={game.myFavorite}
                aria-label="Favorite"
              >
                <StarIcon filled={game.myFavorite} />
                <span style={{ font: 'bold 9px Verdana', color: '#24425f' }}>Favorite</span>
                <span style={{ fontSize: 10, color: '#5a6b7b' }}>{fmtCount(game.favorites)}</span>
              </button>

              <button
                onClick={() => vote(1)}
                className="rb-clickable"
                style={{
                  flex: 1,
                  background: game.myLike === 1 ? 'linear-gradient(180deg,#e7f7dd,#bfe8a9)' : 'linear-gradient(180deg,#fff,#dbe4ec)',
                  border: '1px solid #8ba4b8',
                  borderRadius: 4,
                  padding: '7px 4px',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  gap: 3,
                }}
                aria-pressed={game.myLike === 1}
                aria-label="Like"
              >
                <ThumbIcon up />
                <span style={{ font: 'bold 9px Verdana', color: '#24425f' }}>Like</span>
                <span style={{ fontSize: 10, color: '#5a6b7b' }}>{fmtCount(game.likes)}</span>
              </button>

              <button
                onClick={() => vote(-1)}
                className="rb-clickable"
                style={{
                  flex: 1,
                  background: game.myLike === -1 ? 'linear-gradient(180deg,#fde3e0,#f6b8b1)' : 'linear-gradient(180deg,#fff,#dbe4ec)',
                  border: '1px solid #8ba4b8',
                  borderRadius: 4,
                  padding: '7px 4px',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  gap: 3,
                }}
                aria-pressed={game.myLike === -1}
                aria-label="Dislike"
              >
                <ThumbIcon />
                <span style={{ font: 'bold 9px Verdana', color: '#24425f' }}>Dislike</span>
                <span style={{ fontSize: 10, color: '#5a6b7b' }}>{fmtCount(game.dislikes)}</span>
              </button>
            </div>

            {/* rating */}
            <div style={{ marginTop: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: '#5a6b7b', marginBottom: 3 }}>
                <span>{game.rating !== null ? `${game.rating}% Approval` : 'No ratings yet'}</span>
                <span>{fmtCount(totalVotes)} votes</span>
              </div>
              <div className="rb-ratio">
                <div style={{ width: `${likePct}%` }} />
              </div>
            </div>
          </div>

          {/* creator card */}
          <div className="rb-box" style={{ marginTop: 12, padding: 10, display: 'flex', alignItems: 'center', gap: 10 }}>
            <Avatar user={game.creator} size={44} />
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <button
                  className="rb-link"
                  style={{ background: 'none', border: 'none', padding: 0, font: '12px Verdana' }}
                  onClick={() => router.push(`/users/${game.creator.id}`)}
                >
                  {game.creator.username}
                </button>
                {game.creator.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
                <OnlineDot online={game.creator.lastSeen ? Date.now() - new Date(game.creator.lastSeen).getTime() < 180000 : false} />
              </div>
              <div style={{ fontSize: 10, color: '#7b8896' }}>Creator · Joined {game.creator.createdAt ? fmtDate(game.creator.createdAt) : ''}</div>
            </div>
          </div>

          {/* owner tools (creators) / admin tools (admins can delete any game) */}
          {(game.isOwner || isAdmin) && (
            <div className="rb-box" style={{ marginTop: 12 }}>
              <div className="rb-panel-head">
                <span>{game.isOwner ? 'Owner Tools' : 'Admin Tools'}</span>
                {!game.isOwner && <span className="rb-admin-badge">ADMIN</span>}
              </div>
              <div style={{ padding: 10, display: 'grid', gap: 8 }}>
                {game.isOwner && (
                  <>
                    <div>
                      <div style={{ font: '10px Verdana', color: '#24425f', marginBottom: 4 }}>Replace game build:</div>
                      <input ref={updateFileRef} type="file" style={{ fontSize: 10, maxWidth: '100%' }} aria-label="New build file" />
                      <button className="rb-btn" style={{ marginTop: 5 }} disabled={updating} onClick={() => updateGame(true, false)}>
                        Upload New Build
                      </button>
                    </div>
                    <div>
                      <div style={{ font: '10px Verdana', color: '#24425f', marginBottom: 4 }}>Attach / replace source code:</div>
                      <input ref={updateSrcRef} type="file" style={{ fontSize: 10, maxWidth: '100%' }} aria-label="New source file" />
                      <button className="rb-btn" style={{ marginTop: 5 }} disabled={updating} onClick={() => updateGame(false, true)}>
                        Upload Source
                      </button>
                    </div>
                    <div>
                      <div style={{ font: '10px Verdana', color: '#24425f', marginBottom: 4 }}>Add trailer / screenshot to the gallery:</div>
                      <input ref={mediaInputRef} type="file" accept="video/*,image/*" style={{ fontSize: 10, maxWidth: '100%' }} aria-label="Add game media" />
                      <button className="rb-btn" style={{ marginTop: 5 }} disabled={updating} onClick={addMedia}>
                        Add to Gallery
                      </button>
                      <div style={{ fontSize: 9, color: '#7b8896', marginTop: 3 }}>Videos up to 100MB — like Steam media.</div>
                    </div>
                    <div style={{ fontSize: 9, color: '#7b8896' }}>Updating files refreshes the &quot;Updated&quot; date.</div>
                  </>
                )}
                {isAdmin && (
                  <button className="rb-btn" onClick={toggleGem} type="button" style={{ justifySelf: 'start', borderColor: '#d9c26a' }}>
                    {game.gem ? '💎 Unmark Hidden Gem' : '💎 Mark as Hidden Gem'}
                  </button>
                )}
                <button className="rb-btn rb-btn-red" onClick={deleteGame} style={{ justifySelf: 'start' }}>
                  {game.isOwner ? 'Delete Game' : 'Delete Game (Admin)'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* info strip (like the classic game page table) */}
      <div className="rb-box" style={{ marginTop: 12, overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', minWidth: 640 }}>
          <tbody>
            <tr>
              {[
                ['Downloads', fmtCount(game.downloads)],
                ['Views', fmtCount(game.views)],
                ['Played By', game.playtime ? String(game.playtime.players) : '—'],
                ['Hours Played', game.playtime ? (game.playtime.totalSeconds / 3600).toFixed(1) : '—'],
                ['Avg Session', game.playtime && game.playtime.avgSeconds > 0 ? fmtDuration(game.playtime.avgSeconds) : '—'],
                ['Rating', rs.avgRating !== null ? `${rs.avgRating.toFixed(1)}/5` : '—'],
                ['Positive', rs.positivePct !== null ? `${rs.positivePct}%` : '—'],
                ['Favorites', fmtCount(game.favorites)],
                ['Reviews', String(rs.reviewCount)],
                ['Created', fmtDate(game.createdAt)],
                ['Updated', timeAgo(game.updatedAt)],
                ['Engine', game.engine],
                ['Genre', game.genre],
              ].map(([k, v]) => (
                <td
                  key={k}
                  style={{
                    textAlign: 'center',
                    padding: '9px 8px',
                    borderLeft: '1px solid #e4eaf0',
                    verticalAlign: 'top',
                  }}
                >
                  <div style={{ fontSize: 10, color: '#7b8896', marginBottom: 3 }}>{k}</div>
                  <div style={{ font: 'bold 11px Verdana', color: '#24425f' }}>{v}</div>
                </td>
              ))}
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  )
}

function Tag({ children, small }: { children: React.ReactNode; small?: boolean }) {
  return (
    <span
      style={{
        background: 'linear-gradient(180deg,#eef3f8,#dbe4ec)',
        border: '1px solid #b4c2cf',
        borderRadius: 3,
        padding: small ? '1px 6px' : '3px 8px',
        fontSize: small ? 9 : 10,
        font: `bold ${small ? 9 : 10}px Verdana`,
        color: '#3d566e',
      }}
    >
      {children}
    </span>
  )
}

function GroupGlyph() {
  return (
    <svg width="13" height="11" viewBox="0 0 14 12" aria-hidden="true">
      <rect x="1" y="4" width="8" height="7" fill="#dfe9f2" stroke="#5a7b9a" strokeWidth="1" />
      <rect x="5" y="1" width="8" height="7" fill="#c7d9ea" stroke="#5a7b9a" strokeWidth="1" />
      <rect x="7" y="3" width="2" height="2" fill="#5a7b9a" />
      <rect x="10" y="3" width="2" height="2" fill="#5a7b9a" />
    </svg>
  )
}

function StarIcon({ filled, half = false, size = 16 }: { filled: boolean; half?: boolean; size?: number }) {
  const id = half ? 'halfstar' : undefined
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" aria-hidden="true">
      {half && (
        <defs>
          <linearGradient id={id}>
            <stop offset="50%" stopColor="#f2b01e" />
            <stop offset="50%" stopColor="#fff" />
          </linearGradient>
        </defs>
      )}
      <path
        d="M8 1l2.1 4.3 4.7.7-3.4 3.3.8 4.7L8 11.8l-4.2 2.2.8-4.7L1.2 6l4.7-.7z"
        fill={half ? `url(#${id})` : filled ? '#f2b01e' : '#fff'}
        stroke={filled || half ? '#b5830f' : '#7b8896'}
        strokeWidth="1"
      />
    </svg>
  )
}
