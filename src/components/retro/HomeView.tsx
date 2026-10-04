'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, fmtCount, flash, type RetroUser } from '@/lib/store'
import { Avatar, OnlineDot } from './Shell'
import { VideoCard, type VideoSummary } from './VideosView'

export interface GameSummary {
  id: string
  name: string
  genre: string
  subgenre: string
  engine: string
  maturity: string
  iconUrl: string | null
  thumbnailUrl: string | null
  downloads: number
  gem?: boolean
  createdAt: string
  updatedAt: string
  creator: { id: string; username: string; avatarUrl: string | null }
  likes: number
  dislikes: number
  rating: number | null
  commentCount: number
  favoriteCount: number
  extra?: string
}

export interface SuggestedUser extends RetroUser {
  reason: string
  mutuals: number
}

/* ---------------- Game Card (grids) ---------------- */

export function GameCard({ game }: { game: GameSummary }) {
  const cover = game.thumbnailUrl || game.iconUrl
  return (
    <Link
      href={`/games/${game.id}`}
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
        e.currentTarget.style.borderColor = '#2f7bc0'
        e.currentTarget.style.transform = 'translateY(-2px)'
        e.currentTarget.style.boxShadow = '2px 3px 0 rgba(0,0,0,.16)'
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.borderColor = '#a8b6c2'
        e.currentTarget.style.transform = 'none'
        e.currentTarget.style.boxShadow = '1px 1px 0 rgba(0,0,0,.12)'
      }}
      aria-label={`Open ${game.name}`}
    >
      <div style={{ position: 'relative', width: '100%', aspectRatio: '16/9', overflow: 'hidden', background: '#dde5ec', border: '1px solid #c3cdd7' }}>
        <GameCover src={cover} name={game.name} />
        <span
          style={{
            position: 'absolute',
            left: 3,
            top: 3,
            background: 'rgba(13,48,84,.82)',
            color: '#fff',
            fontSize: 9,
            padding: '1px 5px',
            borderRadius: 2,
          }}
        >
          {game.engine}
        </span>
        {game.gem && (
          <span
            title="Hidden Gem — hand-picked by the admins"
            style={{
              position: 'absolute',
              right: 3,
              top: 3,
              background: 'linear-gradient(180deg,#fdf3d7,#f4d97a)',
              color: '#6b5310',
              fontSize: 9,
              padding: '1px 5px',
              borderRadius: 2,
              border: '1px solid #d9c26a',
            }}
          >
            💎 GEM
          </span>
        )}
      </div>
      <div
        style={{
          fontSize: 11,
          color: '#0d69ac',
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
        }}
      >
        {game.name}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 10, color: '#5a6b7b' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3 }}>
          <ThumbIcon up /> {game.rating != null ? `${game.rating}%` : 'New'}
        </span>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3 }}>
          <PersonIcon /> {fmtCount(game.downloads)}
        </span>
      </div>
    </Link>
  )
}

function GameCover({ src, name }: { src?: string | null; name: string }) {
  const [err, setErr] = useState(false)
  const fallback = `data:image/svg+xml;utf8,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="420" height="236"><rect width="420" height="236" fill="#5DA9E9"/><rect x="0" y="176" width="420" height="60" fill="#4E9A4E"/><rect x="60" y="96" width="70" height="80" fill="#A0522D"/><rect x="240" y="66" width="80" height="110" fill="#8D6E63"/><text x="210" y="130" text-anchor="middle" font-family="Verdana" font-size="26" fill="#fff">${name.slice(0, 16).replace(/[<>&]/g, '')}</text></svg>`
  )}`
  return (
    <img
      src={err || !src ? fallback : src}
      alt={name}
      onError={() => setErr(true)}
      style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
    />
  )
}

export function ThumbIcon({ up }: { up?: boolean }) {
  return up ? (
    <svg width="11" height="11" viewBox="0 0 16 16" aria-hidden="true">
      <path d="M2 7h3v8H2zM6 15h6.5a2 2 0 002-2v-.5l1-4A1.6 1.6 0 0014 6.5h-4l.7-3.2A1.5 1.5 0 009.3 1.5L6 6.5z" fill="#4c9e34" />
    </svg>
  ) : (
    <svg width="11" height="11" viewBox="0 0 16 16" style={{ transform: 'rotate(180deg)' }} aria-hidden="true">
      <path d="M2 7h3v8H2zM6 15h6.5a2 2 0 002-2v-.5l1-4A1.6 1.6 0 0014 6.5h-4l.7-3.2A1.5 1.5 0 009.3 1.5L6 6.5z" fill="#b04a42" />
    </svg>
  )
}

export function PersonIcon() {
  return (
    <svg width="10" height="11" viewBox="0 0 12 13" aria-hidden="true">
      <circle cx="6" cy="3.2" r="2.6" fill="#5a6b7b" />
      <path d="M1 12.5c0-3 2.2-4.8 5-4.8s5 1.8 5 4.8z" fill="#5a6b7b" />
    </svg>
  )
}

/* ---------------- Shared: people-you-may-know strip ---------------- */

export function SuggestedStrip({ users, title }: { users: SuggestedUser[]; title: string }) {
  const { setToast } = useRetro()
  const [sent, setSent] = useState<Record<string, boolean>>({})

  async function add(u: SuggestedUser) {
    try {
      const res = await api<{ autoAccepted?: boolean }>('/api/friends', {
        method: 'POST',
        body: JSON.stringify({ username: u.username }),
      })
      setSent((s) => ({ ...s, [u.id]: true }))
      flash(setToast, res.autoAccepted ? `You and ${u.username} are now friends!` : `Friend request sent to ${u.username}!`)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to send request')
    }
  }

  if (users.length === 0) return null

  return (
    <section className="rb-box" style={{ marginBottom: 12 }}>
      <div className="rb-panel-head">
        <span>{title}</span>
        <Link className="rb-link" style={{ fontSize: 11 }} href="/friends">
          See All &rarr;
        </Link>
      </div>
      <div style={{ padding: '10px 12px', display: 'flex', gap: 14, overflowX: 'auto' }}>
        {users.slice(0, 9).map((u) => (
          <div
            key={u.id}
            style={{
              width: 86,
              flexShrink: 0,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 4,
              textAlign: 'center',
            }}
          >
            <Link href={`/users/${u.id}`} style={{ position: 'relative', display: 'inline-block' }}>
              <Avatar user={u} size={54} rounded="50%" />
              <span style={{ position: 'absolute', right: 0, bottom: 1 }}>
                <OnlineDot online={u.online} />
              </span>
            </Link>
            <Link
              href={`/users/${u.id}`}
              className="rb-link"
              style={{ fontSize: 10, maxWidth: 86, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', display: 'block' }}
            >
              {u.username}
            </Link>
            <div style={{ fontSize: 9, color: '#7b8896', lineHeight: 1.25, minHeight: 22 }}>{u.reason}</div>
            {sent[u.id] ? (
              <span style={{ fontSize: 9, color: '#7b8896', border: '1px solid #c3cdd7', borderRadius: 3, padding: '2px 7px', background: '#f2f6fa' }}>
                Request Sent
              </span>
            ) : (
              <button className="rb-btn rb-btn-green" style={{ fontSize: 9, padding: '2px 8px' }} onClick={() => add(u)}>
                + Add
              </button>
            )}
          </div>
        ))}
      </div>
    </section>
  )
}

/* ---------------- Latest videos strip (YouTube-style) ---------------- */

function LatestVideosStrip() {
  const [videos, setVideos] = useState<VideoSummary[]>([])
  const [loaded, setLoaded] = useState(false)
  useEffect(() => {
    api<{ videos: VideoSummary[] }>('/api/videos?sort=new&limit=8')
      .then((r) => setVideos(r.videos))
      .catch(() => {})
      .finally(() => setLoaded(true))
  }, [])
  if (!loaded || videos.length === 0) return null
  return (
    <section className="rb-box" style={{ marginTop: 12 }}>
      <div className="rb-panel-head">
        <span>Fresh Videos</span>
        <Link className="rb-link" style={{ fontSize: 11 }} href="/videos">
          Watch &rarr;
        </Link>
      </div>
      <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: 10 }}>
        {videos.slice(0, 4).map((v) => (
          <VideoCard key={v.id} video={v} />
        ))}
      </div>
    </section>
  )
}

/* ---------------- Home ---------------- */

/* the old-school news ticker — one endless strip of fun, like the marquees
   every website had in 2006. Rendered twice for a seamless CSS loop. */
const TICKER =
  "★ WELCOME TO RETROBLOX ★ PLAY “BASEPLATE” WITH EVERYONE — IT'S LIVE RIGHT NOW ★ PUBLISH YOUR OWN GAMES ★ DRESS YOUR BLOCKHEAD ★ TRADE LIMITEDS WITH FRIENDS ★ POST VIDEOS OF YOUR WINS ★ YOU CAN SEE THE ROBLOX INSIDE RETROBLOX ★ "

export function HomeView() {
  const { user, pendingRequests } = useRetro()
  const [friends, setFriends] = useState<RetroUser[]>([])
  const [suggested, setSuggested] = useState<SuggestedUser[]>([])
  const [games, setGames] = useState<GameSummary[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [f, g, s] = await Promise.all([
        api<{ friends: RetroUser[] }>('/api/friends'),
        api<{ games: GameSummary[] }>('/api/games?sort=recent&limit=8'),
        api<{ suggested: SuggestedUser[] }>('/api/friends/suggested'),
      ])
      setFriends(f.friends)
      setGames(g.games)
      setSuggested(s.suggested || [])
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const shownFriends = friends.slice(0, 9)

  return (
    <div>
      {/* the hero — your wordmark, your name, and the three things people
          actually do here. Sky gradient + the scrolling news ticker keep it
          loud and proud like a 2006 fansite. */}
      <section
        className="rb-box rb-hero"
        style={{
          marginBottom: 10,
          padding: '14px 16px 0',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
          position: 'relative',
        }}
      >
        <div style={{ display: 'flex', gap: 14, alignItems: 'center', flexWrap: 'wrap' }}>
          <img
            src="/retro/logo-wordmark.png"
            alt="ReTROBLOX"
            style={{ height: 42, width: 'auto', maxWidth: '100%', filter: 'drop-shadow(0 3px 3px rgba(0,0,0,.35))' }}
          />
          <div style={{ flex: 1, minWidth: 190 }}>
            <div className="rb-page-title">{user ? `Hello, ${user.username}!` : 'Welcome to RetroBlox'}</div>
            <div style={{ fontSize: 12, color: 'var(--rb-text-dim)', marginTop: 3 }}>
              Publish a game, dress your blockhead, or hang out in the lounge.
            </div>
          </div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {/* one main color — the wordmark red leads, the rest stay neutral */}
            <Link className="rb-btn rb-btn-red" href="/create" style={{ textDecoration: 'none', fontSize: 11, padding: '6px 14px' }}>
              + Publish a Game
            </Link>
            <Link className="rb-btn" href="/community/new?video=1" style={{ textDecoration: 'none', fontSize: 11, padding: '6px 14px' }}>
              ▶ Post a Video
            </Link>
            <Link className="rb-btn" href="/community" style={{ textDecoration: 'none', fontSize: 11, padding: '6px 14px' }}>
              Community
            </Link>
          </div>
        </div>
        {/* retro marquee ticker — pure flavor, ignorable, but impossible to miss */}
        <div className="rb-marquee" aria-hidden="true">
          <div className="rb-marquee-track">
            <span>{TICKER}</span>
            <span>{TICKER}</span>
          </div>
        </div>
      </section>

      {/* Friends strip (members only — guests have no friends list yet) */}
      {user && (
      <section className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head">
          <span>Friends ({friends.length})</span>
          <Link className="rb-link" style={{ fontSize: 11 }} href="/friends">
            See All &rarr;
          </Link>
        </div>
        <div style={{ padding: '10px 12px', display: 'flex', gap: 10, overflowX: 'auto' }}>
          <Link
            href="/friends"
            className="rb-clickable"
            style={{
              width: 74,
              flexShrink: 0,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 5,
              textDecoration: 'none',
            }}
            aria-label="Add friends"
          >
            <span
              className="rb-plus-circle"
              style={{
                width: 58,
                height: 58,
                border: '2px dashed #8ba0b3',
                fontSize: 26,
                color: '#5a7b9a',
                background: '#eef4fa',
              }}
            >
              <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
                <path d="M10 3v14M3 10h14" stroke="#5a7b9a" strokeWidth="2.6" strokeLinecap="round" />
              </svg>
            </span>
            <span style={{ fontSize: 10, color: '#0d69ac' }}>
              Add Friends{pendingRequests ? ` (${pendingRequests})` : ''}
            </span>
          </Link>

          {loading &&
            Array.from({ length: 5 }).map((_, i) => (
              <div key={i} style={{ width: 74, flexShrink: 0, textAlign: 'center' }}>
                <div style={{ width: 58, height: 58, borderRadius: '50%', background: '#e2e9ef', margin: '0 auto' }} />
                <div style={{ height: 8, background: '#e2e9ef', marginTop: 6, borderRadius: 2 }} />
              </div>
            ))}

          {shownFriends.map((f) => (
            <Link
              key={f.id}
              href={`/users/${f.id}`}
              className="rb-clickable"
              style={{
                width: 74,
                flexShrink: 0,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 5,
                textDecoration: 'none',
              }}
              aria-label={`View ${f.username}'s profile`}
            >
              <span style={{ position: 'relative', display: 'inline-block' }}>
                <Avatar user={f} size={58} rounded="50%" />
                <span style={{ position: 'absolute', right: 0, bottom: 1 }}>
                  <OnlineDot online={f.online} />
                </span>
              </span>
              <span
                style={{
                  fontSize: 10,
                  color: '#0d69ac',
                  maxWidth: 74,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {f.username}
              </span>
            </Link>
          ))}

          {!loading && friends.length === 0 && (
            <div style={{ alignSelf: 'center', color: '#5a6b7b', fontSize: 11, padding: '0 8px' }}>
              No friends yet — add blockheads you know, or meet similar players below!
            </div>
          )}
        </div>
      </section>
      )}

      {/* Similar players */}
      {!loading && suggested.length > 0 && <SuggestedStrip users={suggested} title="People You May Know" />}

      {/* Games — the main event. Eight fresh cards, no endless scrolling. */}
      <section className="rb-box">
        <div className="rb-panel-head">
          <span>All Games</span>
          <Link className="rb-link" style={{ fontSize: 11 }} href="/games">
            Browse all games &rarr;
          </Link>
        </div>
        <div
          style={{
            padding: 12,
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(190px, 1fr))',
            gap: 10,
          }}
        >
          {loading
            ? Array.from({ length: 10 }).map((_, i) => (
                <div key={i} className="rb-box" style={{ height: 150, background: '#f0f4f8' }} />
              ))
            : games.map((g) => <GameCard key={g.id} game={g} />)}
        </div>
        {!loading && games.length === 0 && (
          <div style={{ padding: '26px 20px', textAlign: 'center', color: '#5a6b7b' }}>
            <div style={{ fontSize: 15, marginBottom: 6 }}>No games yet</div>
            <div style={{ fontSize: 11, marginBottom: 12 }}>
              {user
                ? 'RetroBlox just launched — be the very first to publish a game!'
                : 'RetroBlox just launched — no games have been published yet. Grab a username before someone else does!'}
            </div>
            {user ? (
              <Link className="rb-btn rb-btn-red" href="/create" style={{ display: 'inline-block', textDecoration: 'none', padding: '8px 18px' }}>
                Create the first game
              </Link>
            ) : (
              <Link className="rb-btn rb-btn-blue" href="/signup" style={{ display: 'inline-block', textDecoration: 'none', padding: '8px 18px' }}>
                Sign Up to publish
              </Link>
            )}
          </div>
        )}
      </section>

      {/* latest videos */}
      <LatestVideosStrip />
    </div>
  )
}

/* ---------------- Games browse (/games) ---------------- */

const GENRE_LIST = [
  'All Genres', 'Adventure', 'Building', 'Fighting', 'FPS', 'Horror',
  'Obby', 'Puzzle', 'RPG', 'Racing', 'Sci-Fi', 'Simulation', 'Sports',
  'Town & City', 'Tycoon', 'Western',
]

export function GamesView({ q, genre, sort }: { q: string; genre: string; sort: string }) {
  const router = useRouter()
  const [data, setData] = useState<{ games: GameSummary[]; key: string } | null>(null)

  const key = `${genre}|${sort}|${q}`
  const loading = !data || data.key !== key
  const games = data?.games ?? []

  useEffect(() => {
    let cancelled = false
    const params = new URLSearchParams({ sort, limit: '60' })
    if (genre !== 'All Genres') params.set('genre', genre)
    if (q) params.set('q', q)
    api<{ games: GameSummary[] }>(`/api/games?${params}`)
      .then((r) => {
        if (!cancelled) setData({ games: r.games, key })
      })
      .catch(() => {
        if (!cancelled) setData({ games: [], key })
      })
    return () => {
      cancelled = true
    }
  }, [genre, sort, q, key])

  function pushParams(next: { genre?: string; sort?: string }) {
    const p = new URLSearchParams()
    const g = next.genre ?? genre
    const s = next.sort ?? sort
    if (q) p.set('q', q)
    if (g && g !== 'All Genres') p.set('genre', g)
    if (s && s !== 'popular') p.set('sort', s)
    router.push(`/games${p.toString() ? `?${p}` : ''}`)
  }

  const title = q
    ? `Search Results for "${q}"`
    : sort === 'gems'
      ? '💎 Hidden Gems'
      : sort === 'recommended'
        ? 'Recommended For You'
        : sort === 'trending'
          ? 'Trending Now'
          : sort === 'updated'
            ? 'Recently Updated Games'
            : sort === 'recent'
              ? 'Recently Uploaded Games'
              : 'All Games'

  return (
    <div>
      {/* one compact header: title + sort in a single card (the old blurb box
          went away — nobody read it, and it pushed the games below the fold) */}
      <div className="rb-box" style={{ marginBottom: 10, overflow: 'hidden' }}>
        <div className="rb-panel-head">
          <span>{title}</span>
          <span style={{ fontSize: 10, color: '#5a6b7b' }}>
            {loading ? '...' : `${games.length} game${games.length === 1 ? '' : 's'}`}
          </span>
        </div>
        <div style={{ padding: '6px 10px', display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 11, color: '#24425f' }}>Sort by:</span>
          <select
            className="rb-select"
            value={sort}
            onChange={(e) => pushParams({ sort: e.target.value })}
            style={{ fontSize: 11, padding: '3px 6px' }}
            aria-label="Sort games"
          >
            <option value="recommended">Recommended For You</option>
            <option value="trending">Trending Now</option>
            <option value="popular">Popular</option>
            <option value="topRated">Top Rated</option>
            <option value="downloads">Downloads (highest number)</option>
            <option value="recent">Recently Uploaded</option>
            <option value="updated">Recently Updated</option>
            <option value="gems">💎 Hidden Gems</option>
          </select>
          {q && (
            <span style={{ fontSize: 10, color: '#7b8896' }}>
              matched against titles, descriptions and creators
            </span>
          )}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
        {/* genre filter — one of the two filters that matter, kept */}
        <div className="rb-box" style={{ width: 170, flexShrink: 0, overflow: 'hidden' }}>
          <div className="rb-panel-head"><span>Genres</span></div>
          <div style={{ padding: '4px 0' }}>
            {GENRE_LIST.map((g) => (
              <button
                key={g}
                onClick={() => pushParams({ genre: g })}
                style={{
                  display: 'block',
                  width: '100%',
                  textAlign: 'left',
                  padding: '4px 12px',
                  background: genre === g ? '#e3edf7' : 'transparent',
                  border: 'none',
                  borderBottom: '1px solid #eef2f6',
                  color: genre === g ? '#0a4f82' : '#1c4e7c',
                  fontSize: 11,
                }}
              >
                {g}
              </button>
            ))}
          </div>
        </div>

        {/* grid */}
        <div style={{ flex: 1, minWidth: 280 }}>
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(170px, 1fr))',
              gap: 10,
            }}
          >
            {loading
              ? Array.from({ length: 8 }).map((_, i) => (
                  <div key={i} className="rb-box" style={{ height: 140, background: '#f0f4f8' }} />
                ))
              : games.map((g) => <GameCard key={g.id} game={g} />)}
          </div>

          {!loading && games.length === 0 && (
            <div className="rb-box" style={{ padding: 30, textAlign: 'center', color: '#5a6b7b' }}>
              <div style={{ fontSize: 14, marginBottom: 4 }}>
                {q ? `No games match "${q}".` : 'No games found here yet.'}
              </div>
              <div style={{ fontSize: 11, marginBottom: 12 }}>
                RetroBlox is brand new — publish the first one!
              </div>
              <Link className="rb-btn rb-btn-red" href="/create" style={{ display: 'inline-block', textDecoration: 'none' }}>
                Publish a Game
              </Link>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
