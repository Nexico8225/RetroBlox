'use client'

/* Players directory (/users) — the classic "People" finder.
   Search by name OR by player number ("1" finds player #1, "#3" finds #3),
   land on a profile, and send a trade request from there. No query shows
   the newest members so the page is never an empty wall. */

import { Page } from '@/components/retro/Shell'
import { Suspense, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { api, useRetro } from '@/lib/store'
import { Avatar } from '@/components/retro/Shell'
import { FxText } from '@/lib/textfx'

interface UserRow {
  id: string
  username: string
  playerNo: number
  avatarUrl: string | null
  bio: string
  createdAt: string
  lastSeen: string
}

function fmtSeen(iso: string) {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const mins = Math.floor((Date.now() - d.getTime()) / 60000)
  if (mins < 5) return 'online now'
  if (mins < 60) return `seen ${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `seen ${hrs}h ago`
  return `joined ${d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`
}

function PlayersDirectory() {
  const { user } = useRetro()
  const router = useRouter()
  const params = useSearchParams()
  const urlQ = params.get('q') || ''

  const [q, setQ] = useState(urlQ)
  const [users, setUsers] = useState<UserRow[]>([])
  const [busy, setBusy] = useState(true)
  const [err, setErr] = useState('')

  // keep the box in sync when the URL changes (header search, back button)
  useEffect(() => { setQ(urlQ) }, [urlQ])

  useEffect(() => {
    let dead = false
    setBusy(true)
    setErr('')
    api<{ users: UserRow[] }>(`/api/users?q=${encodeURIComponent(urlQ)}`)
      .then((res) => { if (!dead) setUsers(res.users || []) })
      .catch((e) => { if (!dead) setErr(e instanceof Error ? e.message : 'Could not load players.') })
      .finally(() => { if (!dead) setBusy(false) })
    return () => { dead = true }
  }, [urlQ])

  function submit(e: React.FormEvent) {
    e.preventDefault()
    router.push(q.trim() ? `/users?q=${encodeURIComponent(q.trim())}` : '/users')
  }

  return (
    <div style={{ display: 'grid', gap: 12 }}>
      <div className="rb-box" style={{ padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <h1 style={{ fontSize: 20, color: '#1c2733', margin: 0 }}>Players</h1>
        <span style={{ fontSize: 11, color: '#8ba0b3' }}>find anyone by name or player number — trade from their profile</span>
        <form onSubmit={submit} style={{ marginLeft: 'auto', display: 'flex', gap: 6, minWidth: 220 }}>
          <input
            className="rb-input"
            type="search"
            placeholder="Search players or #number…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            style={{ flex: 1, fontSize: 12.5, height: 30 }}
            aria-label="Search players"
          />
          <button className="rb-btn" type="submit" style={{ height: 30 }}>Search</button>
        </form>
      </div>

      {err && <div className="rb-box" style={{ padding: 12, color: '#a81a13', fontSize: 12 }}>{err}</div>}

      {busy ? (
        <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Looking up players…</div>
      ) : users.length === 0 ? (
        <div className="rb-box" style={{ padding: 30, textAlign: 'center', fontSize: 13, color: '#5a6b7b' }}>
          Nobody named that — check the spelling or try their player number.
        </div>
      ) : (
        <div style={{ display: 'grid', gap: 8, gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))' }}>
          {users.map((u) => (
            <Link
              key={u.id}
              href={`/users/${u.id}`}
              className="rb-box"
              style={{ padding: 12, textDecoration: 'none', display: 'flex', gap: 10, alignItems: 'center' }}
            >
              <Avatar user={{ username: u.username, avatarUrl: u.avatarUrl }} size={46} rounded={6} />
              <span style={{ minWidth: 0, display: 'grid', gap: 2 }}>
                <span style={{ fontSize: 13.5, fontWeight: 'bold', color: '#1c2733', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  <FxText text={u.username} />
                  {u.id === user?.id && <span style={{ fontSize: 10, color: '#2c8e31', fontWeight: 'normal' }}> (you)</span>}
                </span>
                <span style={{ fontSize: 10, fontFamily: 'monospace', color: '#9aa7b4' }} title="Every player gets a number in join order">
                  ID: #{u.playerNo || '?'}
                </span>
                <span style={{ fontSize: 10, color: '#8ba0b3', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {u.bio ? <FxText text={u.bio.slice(0, 60)} /> : fmtSeen(u.createdAt)}
                </span>
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}

export default function UsersPage() {
  return (
    <Page>
      <Suspense fallback={<div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Opening the player directory…</div>}>
        <PlayersDirectory />
      </Suspense>
    </Page>
  )
}
