'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, fmtDate, fmtCount } from '@/lib/store'
import { GameIcon } from './Shell'
import { GameCard, type GameSummary } from './HomeView'

/* My Games (/my): shows ONLY the games you published.
   Empty state says "No games" — the Create tab is where games are made. */

export function MyGamesView() {
  const { user } = useRetro()
  const [games, setGames] = useState<GameSummary[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    if (!user) return
    setLoading(true)
    try {
      const res = await api<{ games: GameSummary[] }>(`/api/games?creatorId=${user.id}&limit=100`)
      setGames(res.games)
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [user])

  useEffect(() => {
    load()
  }, [load])

  const totalDl = games.reduce((s, g) => s + g.downloads, 0)

  return (
    <div>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head">
          <span>My Games ({games.length})</span>
          <Link className="rb-link" style={{ fontSize: 11 }} href="/create">
            + Create a Game
          </Link>
        </div>
        <div style={{ padding: '8px 12px', fontSize: 11, color: '#5a6b7b' }}>
          Games you published. Only you can see this page&apos;s list — everyone else finds them in Games.
          {games.length > 0 && ` Total downloads: ${fmtCount(totalDl)}.`}
        </div>
      </div>

      {loading ? (
        <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading your games...</div>
      ) : games.length === 0 ? (
        <div className="rb-box" style={{ padding: '44px 20px', textAlign: 'center' }}>
          <div style={{ fontSize: 20, color: '#24425f', marginBottom: 8 }}>No games</div>
          <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 16, lineHeight: 1.6 }}>
            You haven&apos;t made any games yet.<br />
            The Create tab is where you publish one — Unity, Godot, anything.
          </div>
          <Link className="rb-btn rb-btn-red" href="/create" style={{ display: 'inline-block', textDecoration: 'none', padding: '9px 20px', fontSize: 13 }}>
            Make your first game
          </Link>
        </div>
      ) : (
        <div style={{ display: 'grid', gap: 8 }}>
          {games.map((g) => (
            <Link
              key={g.id}
              href={`/games/${g.id}`}
              className="rb-clickable"
              style={{
                display: 'flex', gap: 10, alignItems: 'center', textAlign: 'left', textDecoration: 'none',
                background: '#fff', border: '1px solid #c3cdd7', borderRadius: 4, padding: 8,
              }}
              aria-label={`Open ${g.name}`}
            >
              <GameIcon src={g.iconUrl || g.thumbnailUrl} name={g.name} size={52} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12, color: '#0d69ac', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {g.name}
                </div>
                <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 2 }}>
                  {g.genre} · {g.engine} · {fmtCount(g.downloads)} downloads
                </div>
                <div style={{ fontSize: 9, color: '#7b8896', marginTop: 2 }}>
                  Created {fmtDate(g.createdAt)} · Updated {fmtDate(g.updatedAt)}
                </div>
              </div>
              <span className="rb-badge" style={{ alignSelf: 'center', background: g.downloads === 0 ? 'linear-gradient(180deg,#8fd464,#3f8425)' : undefined, borderColor: g.downloads === 0 ? '#2f6619' : undefined }}>
                {g.downloads === 0 ? 'NEW' : fmtCount(g.downloads)}
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}

/* ================= Favorites (/favorites) ================= */

export function FavoritesView() {
  const { user } = useRetro()
  const [games, setGames] = useState<GameSummary[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    if (!user) return
    setLoading(true)
    try {
      const res = await api<{ favoriteGames: GameSummary[] }>(`/api/users/${user.id}`)
      setGames(res.favoriteGames || [])
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [user])

  useEffect(() => {
    load()
  }, [load])

  useEffect(() => {
    document.title = 'Favorites - RetroBlox'
  }, [])

  return (
    <div>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head">
          <span>My Favorites ({games.length})</span>
          <Link className="rb-link" style={{ fontSize: 11 }} href="/games">
            Find more games &rarr;
          </Link>
        </div>
        <div style={{ padding: '8px 12px', fontSize: 11, color: '#5a6b7b' }}>
          Games you starred with the Favorite button. They also show on your profile.
        </div>
      </div>

      {loading ? (
        <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading favorites...</div>
      ) : games.length === 0 ? (
        <div className="rb-box" style={{ padding: '44px 20px', textAlign: 'center' }}>
          <div style={{ fontSize: 18, color: '#24425f', marginBottom: 8 }}>No favorites yet</div>
          <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 16, lineHeight: 1.6 }}>
            Open any game page and press the star to keep it here forever.
          </div>
          <Link className="rb-btn rb-btn-green" href="/games" style={{ display: 'inline-block', textDecoration: 'none', padding: '9px 20px', fontSize: 13 }}>
            Browse Games
          </Link>
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(190px, 1fr))', gap: 10 }}>
          {games.map((g) => (
            <GameCard key={g.id} game={g} />
          ))}
        </div>
      )}
    </div>
  )
}
