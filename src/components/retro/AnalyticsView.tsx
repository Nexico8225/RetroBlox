'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, fmtCount, fmtDate } from '@/lib/store'

/* Analytics (/analytics) — the developer dashboard.
   Views/downloads are tracked live on the site; charts are hand-rolled
   retro bar charts, like an old spreadsheet having a good day. */

interface SeriesPoint { day: string; label: string; views: number; downloads: number }

interface AnalyticsGame {
  id: string
  name: string
  iconUrl: string | null
  genre: string
  views: number
  downloads: number
  likes: number
  dislikes: number
  rating: number | null
  favorites: number
  comments: number
  series: SeriesPoint[]
  createdAt: string
}

interface Totals {
  games: number
  views: number
  downloads: number
  likes: number
  dislikes: number
  favorites: number
  comments: number
}

function RetroBarChart({ series }: { series: SeriesPoint[] }) {
  const max = Math.max(1, ...series.map((s) => Math.max(s.views, s.downloads)))
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 3, height: 90, padding: '6px 6px 0', borderLeft: '1px solid #c3cdd7', borderBottom: '1px solid #c3cdd7', background: 'repeating-linear-gradient(180deg, transparent 0 21px, #eef2f6 21px 22px)' }}>
        {series.map((s) => (
          <div key={s.day} style={{ flex: 1, display: 'flex', alignItems: 'flex-end', justifyContent: 'center', gap: 1, height: '100%' }} title={`${s.label}: ${s.views} views · ${s.downloads} downloads`}>
            <div
              style={{
                width: '38%', maxWidth: 10, height: `${(s.views / max) * 100}%`, minHeight: s.views > 0 ? 2 : 0,
                background: 'linear-gradient(180deg,#9ec9ec,#5a92c8)', border: '1px solid #4a7ba8', borderBottom: 'none',
              }}
            />
            <div
              style={{
                width: '38%', maxWidth: 10, height: `${(s.downloads / max) * 100}%`, minHeight: s.downloads > 0 ? 2 : 0,
                background: 'linear-gradient(180deg,#a8dd8f,#5d9c44)', border: '1px solid #4a7d36', borderBottom: 'none',
              }}
            />
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 3, padding: '2px 6px 0' }}>
        {series.map((s) => (
          <div key={s.day} style={{ flex: 1, textAlign: 'center', fontSize: 7, color: '#7b8896', whiteSpace: 'nowrap', overflow: 'hidden' }}>
            {s.label}
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 14, marginTop: 6, fontSize: 9, color: '#5a6b7b' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
          <span style={{ width: 8, height: 8, background: '#5a92c8', border: '1px solid #4a7ba8', display: 'inline-block' }} /> Views
        </span>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
          <span style={{ width: 8, height: 8, background: '#5d9c44', border: '1px solid #4a7d36', display: 'inline-block' }} /> Downloads
        </span>
        <span style={{ marginLeft: 'auto', color: '#a8b6c2' }}>last 14 days</span>
      </div>
    </div>
  )
}

export function AnalyticsView() {
  const { user } = useRetro()
  const [games, setGames] = useState<AnalyticsGame[]>([])
  const [totals, setTotals] = useState<Totals | null>(null)
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const res = await api<{ games: AnalyticsGame[]; totals: Totals }>('/api/analytics')
      setGames(res.games)
      setTotals(res.totals)
      if (res.games.length > 0) setExpanded(res.games[0].id)
    } catch { /* ignore */ } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  if (loading) {
    return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Crunching the numbers...</div>
  }

  if (!totals || games.length === 0) {
    return (
      <div className="rb-box" style={{ padding: '44px 20px', textAlign: 'center', color: '#5a6b7b' }}>
        <div style={{ fontSize: 15, marginBottom: 6 }}>Nothing to analyze yet</div>
        <div style={{ fontSize: 11, marginBottom: 14, lineHeight: 1.6 }}>
          Publish a game and this dashboard fills up with views, downloads,<br />ratings and 14-day trend charts.
        </div>
        <Link className="rb-btn rb-btn-red" href="/create" style={{ display: 'inline-block', textDecoration: 'none', padding: '9px 20px' }}>
          Publish your first game
        </Link>
      </div>
    )
  }

  const cards: { label: string; value: number; sub?: string }[] = [
    { label: 'Games', value: totals.games },
    { label: 'Page Views', value: totals.views },
    { label: 'Downloads', value: totals.downloads },
    { label: 'Likes', value: totals.likes },
    { label: 'Favorites', value: totals.favorites },
    { label: 'Comments', value: totals.comments },
  ]

  return (
    <div>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head">
          <span>Developer Analytics</span>
          <span style={{ fontSize: 10, color: '#5a6b7b' }}>{user?.username}&apos;s games</span>
        </div>
        <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(110px, 1fr))', gap: 8 }}>
          {cards.map((c) => (
            <div key={c.label} style={{ border: '1px solid #c3cdd7', borderRadius: 4, background: 'linear-gradient(180deg,#fff,#eef3f8)', padding: '8px 6px', textAlign: 'center' }}>
              <div style={{ fontSize: 9, color: '#7b8896', letterSpacing: '0.4px', textTransform: 'uppercase' }}>{c.label}</div>
              <div style={{ fontSize: 19, color: '#0d69ac', marginTop: 2 }}>{fmtCount(c.value)}</div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: 'grid', gap: 10 }}>
        {games.map((g) => {
          const open = expanded === g.id
          return (
            <div key={g.id} className="rb-box" style={{ overflow: 'hidden' }}>
              <div
                className="rb-clickable"
                onClick={() => setExpanded(open ? null : g.id)}
                style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 10, flexWrap: 'wrap' }}
                role="button"
                aria-expanded={open}
              >
                <span style={{ width: 40, height: 40, borderRadius: 4, border: '1px solid #8ba0b3', background: '#dde5ec', overflow: 'hidden', flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#5a7b9a', fontSize: 15 }}>
                  {g.iconUrl ? <img src={g.iconUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : '▦'}
                </span>
                <span style={{ flex: 1, minWidth: 140 }}>
                  <Link href={`/games/${g.id}`} className="rb-link" style={{ fontSize: 12, display: 'inline-block' }} onClick={(e) => e.stopPropagation()}>
                    {g.name}
                  </Link>
                  <span style={{ display: 'block', fontSize: 9, color: '#7b8896' }}>
                    {g.genre} · launched {fmtDate(g.createdAt)}
                  </span>
                </span>
                <span style={{ display: 'flex', gap: 14, fontSize: 11, color: '#24425f', flexWrap: 'wrap' }}>
                  <span title="Page views">👁 {fmtCount(g.views)}</span>
                  <span title="Downloads">⬇ {fmtCount(g.downloads)}</span>
                  <span title="Likes">👍 {fmtCount(g.likes)}</span>
                  <span title="Rating">{g.rating !== null ? `${g.rating}%` : 'New'}</span>
                  <span title="Comments">💬 {fmtCount(g.comments)}</span>
                </span>
                <span style={{ fontSize: 10, color: '#5a7b9a' }}>{open ? '▲ hide chart' : '▼ show chart'}</span>
              </div>
              {open && (
                <div style={{ borderTop: '1px solid #e4eaf0', padding: 10 }}>
                  <RetroBarChart series={g.series} />
                  <div style={{ marginTop: 8, fontSize: 10, color: '#7b8896' }}>
                    Views are counted once per visitor per session. Downloads count every Download and Re-Download click.
                  </div>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
