'use client'

/* WebGamePlayer — runs a Web game (engine="Web") inside a SANDBOXED iframe.
   The iframe has NO allow-same-origin: the game gets an opaque origin, so
   its code can never read RetroBlox cookies, tokens or the parent DOM.
   While you play, a playtime heartbeat fires every 60s for logged-in
   members (same pipeline the downloaded games use). */

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { api, useRetro } from '@/lib/store'
import { buildWebGameDoc } from '@/lib/webgame'
import { FxText } from '@/lib/textfx'

interface WebGameT {
  id: string
  name: string
  description: string
  engine: string
  webCode: string | null
  isOwner: boolean
  creator: { id: string; username: string }
}

export function WebGamePlayer({ id }: { id: string }) {
  const { user } = useRetro()
  const [game, setGame] = useState<WebGameT | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [runId, setRunId] = useState(0) // bump = restart the game
  const [fs, setFs] = useState(false)
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState('')
  const [saving, setSaving] = useState(false)
  const frameWrapRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    let alive = true
    setLoading(true)
    api<{ game: WebGameT }>(`/api/games/${id}`)
      .then((res) => {
        if (!alive) return
        setGame(res.game)
      })
      .catch((e) => alive && setError(e instanceof Error ? e.message : 'Could not load that game.'))
      .finally(() => alive && setLoading(false))
    return () => { alive = false }
  }, [id])

  /* playtime heartbeat — every 60s while the tab is open, the same
     "beat within 5 min = same session" contract the server expects */
  useEffect(() => {
    if (!user || !game) return
    const beat = () => {
      api('/api/playtime', { method: 'POST', body: JSON.stringify({ gameId: game.id, clientSeconds: 60 }) }).catch(() => {})
    }
    const t = setInterval(beat, 60_000)
    return () => clearInterval(t)
  }, [user, game])

  const goFullscreen = useCallback(() => {
    const el = frameWrapRef.current
    if (!el) return
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {})
    } else if (el.requestFullscreen) {
      el.requestFullscreen().catch(() => {})
    }
  }, [])

  useEffect(() => {
    const onFs = () => setFs(!!document.fullscreenElement)
    document.addEventListener('fullscreenchange', onFs)
    return () => document.removeEventListener('fullscreenchange', onFs)
  }, [])

  if (loading) {
    return <div className="rb-box" style={{ padding: 60, textAlign: 'center', color: '#5a6b7b', fontSize: 12 }}>Loading game...</div>
  }

  if (error || !game) {
    return (
      <div className="rb-box" style={{ padding: '40px 20px', textAlign: 'center' }}>
        <div style={{ fontSize: 16, color: '#24425f', marginBottom: 8 }}>Game not found</div>
        <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 14 }}>{error || 'This game does not exist (or was deleted).'}</div>
        <Link className="rb-btn rb-btn-green" href="/games" style={{ display: 'inline-block', textDecoration: 'none', fontSize: 12 }}>Browse Games</Link>
      </div>
    )
  }

  if (game.engine !== 'Web' || !game.webCode) {
    return (
      <div className="rb-box" style={{ padding: '40px 20px', textAlign: 'center' }}>
        <div style={{ fontSize: 16, color: '#24425f', marginBottom: 8 }}>Not a web game</div>
        <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 14, lineHeight: 1.6 }}>
          {game.name} runs from a download build — grab it from the game page.
        </div>
        <Link className="rb-btn rb-btn-green" href={`/games/${game.id}`} style={{ display: 'inline-block', textDecoration: 'none', fontSize: 12 }}>Back to the game page</Link>
      </div>
    )
  }

  const doc = buildWebGameDoc(game.webCode)

  /* creator-only: patch the code live, restart the frame with the new version */
  async function saveCode() {
    if (!game) return
    setSaving(true)
    try {
      const fd = new FormData()
      fd.append('webCode', draft)
      fd.append('engine', 'Web')
      await api(`/api/games/${game.id}`, { method: 'PATCH', body: fd })
      setGame({ ...game, webCode: draft })
      setEditing(false)
      setRunId((n) => n + 1)
    } catch {
      /* the api layer already surfaced the error toast-less — reopen */
    } finally {
      setSaving(false)
    }
  }

  return (
    <div style={{ display: 'grid', gap: 8 }}>
      {/* player bar */}
      <div className="rb-box" style={{ padding: '7px 10px', display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <Link className="rb-link" href={`/games/${game.id}`} style={{ fontSize: 11, whiteSpace: 'nowrap' }}>&larr; Game page</Link>
        <div style={{ fontSize: 13, color: '#0d69ac', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          <FxText text={game.name} />
        </div>
        <span className="rb-badge" style={{ fontSize: 9 }}>WEB &middot; by {game.creator.username}</span>
        <div style={{ flex: 1 }} />
        {game.isOwner && (
          <button
            type="button"
            className="rb-btn"
            style={{ fontSize: 10 }}
            onClick={() => { setDraft(game.webCode || ''); setEditing((v) => !v) }}
          >
            {editing ? '&#10005; Close editor' : '&#9998; Edit code'}
          </button>
        )}
        <button type="button" className="rb-btn" style={{ fontSize: 10 }} onClick={() => setRunId((n) => n + 1)}>
          &#10227; Restart
        </button>
        <button type="button" className="rb-btn" style={{ fontSize: 10 }} onClick={goFullscreen}>
          {fs ? '&#x26F6; Exit fullscreen' : '&#x26F6; Fullscreen'}
        </button>
      </div>

      {/* creator-only live code editor — patch + instant restart */}
      {editing && (
        <div style={{ background: '#101820', border: '1px solid #24425f', borderRadius: 4, padding: 8 }}>
          <textarea
            aria-label="Edit game code"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            rows={12}
            spellCheck={false}
            style={{
              width: '100%', resize: 'vertical', background: '#0b1218', color: '#bfe3ff',
              border: '1px solid #24425f', borderRadius: 3, padding: 8,
              fontFamily: "'Courier New', monospace", fontSize: 12, lineHeight: 1.55, outline: 'none',
            }}
          />
          <div style={{ display: 'flex', gap: 8, marginTop: 6, alignItems: 'center' }}>
            <button type="button" className="rb-btn rb-btn-green" style={{ fontSize: 10 }} disabled={saving || draft.trim().length < 10} onClick={saveCode}>
              {saving ? 'Saving...' : 'Save + restart game'}
            </button>
            <span style={{ fontSize: 10, color: '#9db4c6' }}>Saves live for every player.</span>
          </div>
        </div>
      )}

      {/* the sandboxed game itself — NO allow-same-origin: opaque origin,
          no cookies, no parent DOM, no top navigation. Keyboard focus goes
          to the frame so arrow keys / space reach the game right away. */}
      <div ref={frameWrapRef} style={{ background: '#000', border: '1px solid #24425f', borderRadius: 4, overflow: 'hidden' }}>
        <iframe
          key={runId}
          title={`${game.name} — playable web game`}
          srcDoc={doc}
          sandbox="allow-scripts allow-pointer-lock allow-modals"
          allowFullScreen
          onLoad={(e) => { try { (e.target as HTMLIFrameElement).focus() } catch { /* cross-origin is fine */ } }}
          style={{
            display: 'block',
            width: '100%',
            height: fs ? '100vh' : 'min(78vh, 720px)',
            border: '0',
            background: '#101820',
          }}
        />
      </div>

      <div style={{ fontSize: 10, color: '#7b8896', lineHeight: 1.6 }}>
        Playing in your browser — no download. Games run in a safe sandbox: they cannot see your RetroBlox account.
        {game.description ? (
          <>
            <br />
            <span style={{ color: '#3d566e' }}>{game.description.slice(0, 300)}</span>
          </>
        ) : null}
      </div>
    </div>
  )
}
