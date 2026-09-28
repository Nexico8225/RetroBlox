'use client'

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, flash, fmtDate, timeAgo, type RetroUser } from '@/lib/store'
import { tixCompact } from '@/lib/tix'
import { Avatar, OnlineDot } from './Shell'

/* ------------------------------------------------------------------
   PEOPLE — the member directory. Everyone who joined RetroBlox, with
   join date, Tix balance, games published, online status — plus one
   click to send a friend request or open a chat (open DMs, so you can
   message anyone even before you're friends).
------------------------------------------------------------------ */

interface Person extends RetroUser {
  gamesCount: number
}

const SORTS = [
  { key: 'newest', label: 'Newest' },
  { key: 'online', label: 'Online' },
  { key: 'tix', label: 'Top Tix' },
  { key: 'name', label: 'A–Z' },
] as const

function TixIcon() {
  return (
    <svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true" style={{ flexShrink: 0 }}>
      <path
        d="M3 9V6a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v3a2.5 2.5 0 0 0 0 6v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-3a2.5 2.5 0 0 0 0-6z"
        fill="#ffd34e"
        stroke="#8a6d1a"
        strokeWidth="1.2"
      />
      <path d="M15.5 6v2M15.5 10.5v2M15.5 15v2" stroke="#8a6d1a" strokeWidth="1.4" strokeDasharray="2.4 2.2" fill="none" />
    </svg>
  )
}

export function PeopleView() {
  const { user, setToast } = useRetro()
  const [q, setQ] = useState('')
  const [sort, setSort] = useState<(typeof SORTS)[number]['key']>('newest')
  const [people, setPeople] = useState<Person[]>([])
  const [loading, setLoading] = useState(true)
  const [sent, setSent] = useState<Record<string, boolean>>({})

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const res = api<{ people: Person[] }>(
        `/api/users?sort=${sort}&limit=200${q.trim() ? `&q=${encodeURIComponent(q.trim())}` : ''}`
      )
      const res2 = await res
      setPeople(res2.people)
    } catch {
      /* directory is best-effort */
    } finally {
      setLoading(false)
    }
  }, [q, sort])

  useEffect(() => {
    const t = setTimeout(load, q ? 250 : 0) // debounce typing
    return () => clearTimeout(t)
  }, [load, q])

  async function add(p: Person) {
    try {
      const res = await api<{ autoAccepted?: boolean }>('/api/friends', {
        method: 'POST',
        body: JSON.stringify({ username: p.username }),
      })
      setSent((s) => ({ ...s, [p.id]: true }))
      flash(setToast, res.autoAccepted ? `You and ${p.username} are now friends!` : `Friend request sent to ${p.username}!`)
    } catch (e) {
      // 409 "already friends / already sent" still means nothing left to do
      setSent((s) => ({ ...s, [p.id]: true }))
      flash(setToast, e instanceof Error ? e.message : 'Failed to send request')
    }
  }

  return (
    <div>
      {/* search + sort toolbar */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head">
          <span>People</span>
          <span style={{ fontSize: 10, color: '#5a6b7b' }}>{people.length} blockheads</span>
        </div>
        <div style={{ padding: 10, display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
          <input
            className="rb-input"
            placeholder="Search people by username..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            style={{ flex: 1, minWidth: 180 }}
            aria-label="Search people"
          />
          <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
            {SORTS.map((s) => (
              <button
                key={s.key}
                className={`rb-btn${sort === s.key ? ' rb-btn-green' : ''}`}
                style={{ fontSize: 10, padding: '4px 9px' }}
                onClick={() => setSort(s.key)}
                aria-pressed={sort === s.key}
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* directory grid */}
      {loading && (
        <div className="rb-box" style={{ padding: 24, textAlign: 'center', color: '#5a6b7b', fontSize: 11 }}>
          Loading people...
        </div>
      )}

      {!loading && people.length === 0 && (
        <div className="rb-box" style={{ padding: '30px 16px', textAlign: 'center', color: '#5a6b7b' }}>
          <div style={{ fontSize: 13, marginBottom: 6 }}>Nobody matches &quot;{q}&quot;</div>
          <div style={{ fontSize: 11 }}>Check the spelling — usernames are 3-20 characters.</div>
        </div>
      )}

      {!loading && people.length > 0 && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(215px, 1fr))', gap: 10 }}>
          {people.map((p) => (
            <div key={p.id} className="rb-box" style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Link href={`/users/${p.id}`} style={{ position: 'relative', display: 'inline-block' }} aria-label={`View ${p.username}'s profile`}>
                  <Avatar user={p} size={52} rounded="50%" />
                  <span style={{ position: 'absolute', right: -1, bottom: 1 }}>
                    <OnlineDot online={p.online} />
                  </span>
                </Link>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <Link className="rb-link" href={`/users/${p.id}`} style={{ fontSize: 13, display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {p.username}
                  </Link>
                  <div style={{ fontSize: 10, color: p.online ? '#2c6e31' : '#7b8896' }}>
                    {p.online ? '● Online now' : `Seen ${timeAgo(p.lastSeen)}`}
                  </div>
                  <div style={{ fontSize: 10, color: '#7b8896' }}>Joined {fmtDate(p.createdAt)}</div>
                </div>
              </div>

              {/* Tix + games details */}
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                <span
                  title={`${p.username} has ${tixCompact(p.rbxBalance ?? 0)} Tix`}
                  style={{
                    display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10,
                    background: '#fdf6e4', border: '1px solid #e0d3a6', borderRadius: 3,
                    padding: '2px 7px', color: '#6b5413', fontFamily: 'monospace',
                  }}
                >
                  <TixIcon /> T$ {tixCompact(p.rbxBalance ?? 0)}
                </span>
                <span
                  title={`${p.username} published ${p.gamesCount} game${p.gamesCount === 1 ? '' : 's'}`}
                  style={{
                    display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10,
                    background: '#eef4fa', border: '1px solid #c9dbe9', borderRadius: 3,
                    padding: '2px 7px', color: '#1c4e7c',
                  }}
                >
                  {p.gamesCount} Game{p.gamesCount === 1 ? '' : 's'}
                </span>
                {p.role === 'admin' && (
                  <span className="rb-admin-badge" style={{ alignSelf: 'center' }}>ADMIN</span>
                )}
              </div>

              {/* actions */}
              {user && user.id !== p.id ? (
                <div style={{ display: 'flex', gap: 6 }}>
                  {sent[p.id] ? (
                    <span
                      style={{
                        flex: 1, textAlign: 'center', fontSize: 10, color: '#7b8896',
                        border: '1px solid #c3cdd7', borderRadius: 3, padding: '4px 7px', background: '#f2f6fa',
                      }}
                    >
                      Request Sent
                    </span>
                  ) : (
                    <button className="rb-btn rb-btn-green" style={{ flex: 1, fontSize: 10 }} onClick={() => add(p)}>
                      + Add Friend
                    </button>
                  )}
                  <Link className="rb-btn" style={{ flex: 1, fontSize: 10, textAlign: 'center', textDecoration: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }} href={`/chat/${p.id}`}>
                    Message
                  </Link>
                </div>
              ) : user ? (
                <Link className="rb-btn" style={{ fontSize: 10, textAlign: 'center', textDecoration: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }} href="/settings">
                  This is you
                </Link>
              ) : (
                <div style={{ display: 'flex', gap: 6 }}>
                  <Link className="rb-btn rb-btn-green" style={{ flex: 1, fontSize: 10, textAlign: 'center', textDecoration: 'none' }} href="/signup">
                    Sign Up
                  </Link>
                  <Link className="rb-btn" style={{ flex: 1, fontSize: 10, textAlign: 'center', textDecoration: 'none' }} href="/login">
                    Log In
                  </Link>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
