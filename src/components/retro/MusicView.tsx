'use client'

/* ================= Music Library (/music) =================
   The classic audio library: upload a track, everyone can listen.
   One shared <audio> per page — pressing play anywhere pauses the rest,
   exactly like the old Roblox library pages felt. */

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, flash } from '@/lib/store'

interface MusicTrackT {
  id: string
  title: string
  url: string
  fileName: string | null
  plays: number
  createdAt: string
  creator: { id: string; username: string; avatarUrl: string | null }
}

/* --- tiny SVG icons (no emoji — the site runs on icons) --- */
const PlayIcon = () => (
  <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true">
    <path d="M2.5 1.2 L10.8 6 L2.5 10.8 Z" fill="currentColor" />
  </svg>
)
const PauseIcon = () => (
  <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true">
    <rect x="2" y="1.5" width="3" height="9" fill="currentColor" />
    <rect x="7" y="1.5" width="3" height="9" fill="currentColor" />
  </svg>
)
const NoteIcon = () => (
  <svg width="26" height="26" viewBox="0 0 24 24" aria-hidden="true" style={{ opacity: 0.55 }}>
    <path d="M9 3v11.1a3.6 3.6 0 1 0 1.8 3.1V7.2l8-1.8v6.2a3.6 3.6 0 1 0 1.8 3.1V2L9 4.4Z" fill="currentColor" />
  </svg>
)
const TrashIcon = () => (
  <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden="true">
    <path d="M2 3h8M4.5 3V1.8h3V3M3 3l.6 7.4h4.8L9 3M5 4.8v3.9M7 4.8v3.9" stroke="currentColor" strokeWidth="1" fill="none" strokeLinecap="round" />
  </svg>
)

function timeAgo(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  return `${Math.floor(s / 86400)}d ago`
}

export function MusicView() {
  const { user, setToast } = useRetro()
  const [tracks, setTracks] = useState<MusicTrackT[] | null>(null)
  const [q, setQ] = useState('')
  const [title, setTitle] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  // the one shared player
  const [playingId, setPlayingId] = useState<string | null>(null)
  const [elapsed, setElapsed] = useState(0)
  const [duration, setDuration] = useState(0)
  const audioRef = useRef<HTMLAudioElement | null>(null)

  const load = useCallback(async (query = '') => {
    try {
      const res = await api<{ tracks: MusicTrackT[] }>(`/api/music${query ? `?q=${encodeURIComponent(query)}` : ''}`)
      setTracks(res.tracks || [])
    } catch {
      flash(setToast, 'Could not load the music library.')
    }
  }, [setToast])

  useEffect(() => { load() }, [load])

  function fmt(s: number): string {
    if (!Number.isFinite(s)) return '0:00'
    const m = Math.floor(s / 60)
    const r = Math.floor(s % 60)
    return `${m}:${String(r).padStart(2, '0')}`
  }

  function toggle(t: MusicTrackT) {
    const audio = audioRef.current
    if (!audio) return
    if (playingId === t.id) {
      audio.pause()
      setPlayingId(null)
      return
    }
    audio.src = t.url
    audio.play().then(() => {
      setPlayingId(t.id)
      // count the listen (fire and forget)
      api(`/api/music/${t.id}/play`, { method: 'POST' })
        .then(() => setTracks((list) => list && list.map((x) => (x.id === t.id ? { ...x, plays: x.plays + 1 } : x))))
        .catch(() => {})
    }).catch(() => {
      flash(setToast, 'The browser could not play that file.')
    })
  }

  async function upload() {
    setError('')
    if (!title.trim()) { setError('Give the track a title.'); return }
    if (!file) { setError('Pick an audio file (MP3 / OGG / WAV).'); return }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('title', title.trim())
      fd.append('audio', file)
      const res = await api<{ track: MusicTrackT }>('/api/music', { method: 'POST', body: fd })
      setTracks((list) => [res.track, ...(list || [])])
      setTitle('')
      setFile(null)
      flash(setToast, 'Track uploaded — the library can hear it now!')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Upload failed')
    } finally {
      setBusy(false)
    }
  }

  async function remove(t: MusicTrackT) {
    try {
      await api(`/api/music/${t.id}`, { method: 'DELETE' })
      setTracks((list) => (list ? list.filter((x) => x.id !== t.id) : list))
      if (playingId === t.id) {
        audioRef.current?.pause()
        setPlayingId(null)
      }
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Delete failed')
    }
  }

  return (
    <div>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Music Library</span></div>
        <div style={{ padding: 12, fontSize: 11, color: '#41586c' }}>
          The RetroBlox audio library — upload your tracks and everyone can listen.
          Audio streams straight from the platform, and any game can use these through the API.
        </div>
      </div>

      {/* the one shared player (hidden) */}
      <audio
        ref={audioRef}
        onTimeUpdate={(e) => setElapsed(e.currentTarget.currentTime)}
        onLoadedMetadata={(e) => setDuration(e.currentTarget.duration)}
        onEnded={() => setPlayingId(null)}
        style={{ display: 'none' }}
      />

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'flex-start' }}>
        {/* upload + search column */}
        <div style={{ width: 300, flexShrink: 0 }}>
          {user ? (
            <div className="rb-box" style={{ marginBottom: 12 }}>
              <div className="rb-panel-head"><span>Upload a track</span></div>
              <div style={{ padding: 12 }}>
                <label style={{ display: 'block', fontSize: 11, color: '#1c4e7c', marginBottom: 8 }}>
                  Title
                  <input
                    className="rb-input"
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    maxLength={80}
                    placeholder="Epic Coaster Theme"
                    style={{ width: '100%', fontSize: 11, marginTop: 2 }}
                  />
                </label>
                <label style={{ display: 'block', fontSize: 11, color: '#1c4e7c', marginBottom: 4 }}>
                  Audio file <span style={{ color: '#8ba0b3' }}>(MP3 / OGG / WAV, max 8MB)</span>
                </label>
                <input
                  type="file"
                  accept="audio/*,.mp3,.ogg,.wav,.m4a"
                  onChange={(e) => setFile(e.target.files?.[0] || null)}
                  style={{ fontSize: 10, width: '100%', marginBottom: 8 }}
                  aria-label="Audio file"
                />
                {error && (
                  <div role="alert" style={{ fontSize: 10, color: '#c81c14', background: '#fff2f1', border: '1px solid #e8b7b4', padding: '4px 8px', marginBottom: 8 }}>
                    {error}
                  </div>
                )}
                <button className="rb-btn rb-btn-green" style={{ width: '100%', fontSize: 11 }} disabled={busy} onClick={upload}>
                  {busy ? 'Uploading...' : '⬆ Upload track'}
                </button>
              </div>
            </div>
          ) : (
            <div className="rb-box" style={{ marginBottom: 12 }}>
              <div className="rb-panel-head"><span>Upload a track</span></div>
              <div style={{ padding: 12, fontSize: 11, color: '#41586c' }}>
                <Link href="/login" className="rb-link">Log in</Link> to upload your music — listening is open to everyone.
              </div>
            </div>
          )}

          <div className="rb-box">
            <div className="rb-panel-head"><span>Search</span></div>
            <div style={{ padding: 10 }}>
              <form
                onSubmit={(e) => { e.preventDefault(); load(q) }}
                style={{ display: 'flex', gap: 4 }}
              >
                <input
                  className="rb-input"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Track or creator..."
                  style={{ flex: 1, fontSize: 11 }}
                  aria-label="Search music"
                />
                <button className="rb-btn" type="submit" style={{ fontSize: 10 }}>Go</button>
              </form>
            </div>
          </div>
        </div>

        {/* track list */}
        <div className="rb-box" style={{ flex: 1, minWidth: 280 }}>
          <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between' }}>
            <span>Tracks</span>
            <span style={{ fontSize: 10, color: '#dcebf5' }}>{tracks ? `${tracks.length}` : ''}</span>
          </div>
          <div style={{ padding: 8 }}>
            {!tracks ? (
              <div style={{ padding: 30, textAlign: 'center', fontSize: 11, color: '#5a6b7b' }}>Loading the library...</div>
            ) : tracks.length === 0 ? (
              <div style={{ padding: 26, textAlign: 'center' }}>
                <div style={{ display: 'flex', justifyContent: 'center', color: '#7b8896' }}><NoteIcon /></div>
                <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 6 }}>
                  {q ? 'No tracks match that search.' : 'The library is empty — be the first to upload a track!'}
                </div>
              </div>
            ) : (
              tracks.map((t) => {
                const isPlaying = playingId === t.id
                const mine = user && (user.id === t.creator.id || user.role === 'admin')
                return (
                  <div
                    key={t.id}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 10,
                      padding: '7px 8px', borderBottom: '1px solid #edf2f6',
                      background: isPlaying ? '#e1f2fb' : 'transparent',
                    }}
                  >
                    <button
                      type="button"
                      className="rb-btn"
                      onClick={() => toggle(t)}
                      aria-label={isPlaying ? `Pause ${t.title}` : `Play ${t.title}`}
                      title={isPlaying ? 'Pause' : 'Play'}
                      style={{
                        width: 30, height: 30, minWidth: 30, padding: 0,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        background: isPlaying ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : undefined,
                        color: isPlaying ? '#fff' : '#1c4e7c',
                      }}
                    >
                      {isPlaying ? <PauseIcon /> : <PlayIcon />}
                    </button>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 12, color: '#1c2733', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        {t.title}
                      </div>
                      <div style={{ fontSize: 10, color: '#7b8896' }}>
                        by <Link href={`/users/${t.creator.id}`} className="rb-link">{t.creator.username}</Link>
                        {' · '}{t.plays} play{t.plays === 1 ? '' : 's'}
                        {' · '}{timeAgo(t.createdAt)}
                      </div>
                    </div>
                    {isPlaying && (
                      <span style={{ fontSize: 10, fontFamily: 'monospace', color: '#1c4e7c' }}>
                        {fmt(elapsed)} / {fmt(duration)}
                      </span>
                    )}
                    {mine && (
                      <button
                        type="button"
                        className="rb-btn"
                        onClick={() => remove(t)}
                        aria-label={`Delete ${t.title}`}
                        title="Delete track"
                        style={{ width: 26, height: 26, minWidth: 26, padding: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                      >
                        <TrashIcon />
                      </button>
                    )}
                  </div>
                )
              })
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
