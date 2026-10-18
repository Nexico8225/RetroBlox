'use client'

/* ------------------------------------------------------------------
   WEBS — the tab where people upload WEBS: little pages, toys and
   games made out of code. Upload an .html file (or paste code, or
   start from a template), hit Publish, and it runs RIGHT on RetroBlox
   inside the same safe sandbox the Web Game engine uses.

   Everything here is a Game row with engine="Web" — the Webs tab is
   the front door for them, /play/[id] is the sandbox, and the
   RetroBlox.say / .score / .win / .lose helpers are available.
------------------------------------------------------------------ */
import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { useRetro, api, fmtCount, flash, GENRES } from '@/lib/store'
import { WEB_TEMPLATES, buildWebGameDoc } from '@/lib/webgame'
import type { GameSummary } from './HomeView'

const labelStyle: React.CSSProperties = {
  display: 'block', fontSize: 11, fontWeight: 600, color: '#24425f', margin: '8px 0 3px',
}

export function WebsView() {
  const { user, setToast } = useRetro()
  const [webs, setWebs] = useState<GameSummary[] | null>(null)
  const [showUpload, setShowUpload] = useState(false)

  // ---- upload form state
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [genre, setGenre] = useState('Puzzle')
  const [webCode, setWebCode] = useState('')
  const [template, setTemplate] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [published, setPublished] = useState<{ id: string; seqId?: number | null } | null>(null)
  const [testOpen, setTestOpen] = useState(false)
  const [testKey, setTestKey] = useState(0)

  const load = useCallback(async () => {
    try {
      const r = await api<{ games: GameSummary[] }>('/api/games?engine=Web&sort=recent&limit=60')
      setWebs(r.games)
    } catch {
      setWebs([])
    }
  }, [])

  useEffect(() => { load() }, [load])

  async function loadFile(f: File | null) {
    if (!f) return
    if (f.size > 200_000) {
      setToast('Web file too large (max 200KB of code)')
      return
    }
    const text = await f.text()
    setWebCode(text)
    if (!name.trim()) setName(f.name.replace(/\.(html?|txt)$/i, '').slice(0, 60))
    setTestOpen(false)
  }

  async function publish() {
    setError('')
    if (!user) return
    if (name.trim().length < 3) { setError('Give your web a name (3+ letters).'); return }
    if (webCode.trim().length < 10) { setError('Your web needs code — paste it, load an .html file, or press a starter.'); return }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('name', name.trim())
      fd.append('description', description.trim())
      fd.append('genre', genre)
      fd.append('engine', 'Web')
      fd.append('webCode', webCode)
      const r = await api<{ game: { id: string; seqId?: number | null } }>('/api/games', { method: 'POST', body: fd })
      setPublished(r.game)
      flash(setToast, 'Web published!')
      load()
      setShowUpload(false)
      setName(''); setDescription(''); setWebCode(''); setTemplate('')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not publish — try again.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      {/* intro strip */}
      <div className="rb-box" style={{ marginBottom: 12, padding: '10px 12px', display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
        <span style={{ fontSize: 22 }}>&lt;/&gt;</span>
        <div style={{ flex: 1, minWidth: 220 }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: '#24425f' }}>Webs — pages made of code</div>
          <div style={{ fontSize: 11, color: '#5a6b7b', lineHeight: 1.6 }}>
            Anyone can upload a WEB: a little page, toy or game written in HTML/JS.
            Load an .html file or start from a template — it runs right here on RetroBlox,
            inside a safe sandbox. Helpers: <code>RetroBlox.say / .score / .win / .lose</code>.
          </div>
        </div>
        {user ? (
          <button className="rb-btn rb-btn-green" style={{ fontSize: 12 }} onClick={() => { setShowUpload((v) => !v); setPublished(null) }}>
            {showUpload ? 'Close' : '+ Upload a Web'}
          </button>
        ) : (
          <Link href="/login" className="rb-btn" style={{ fontSize: 12, textDecoration: 'none' }}>Log in to upload</Link>
        )}
      </div>

      {/* upload / edit studio */}
      {user && showUpload && (
        <div className="rb-box" style={{ marginBottom: 12 }}>
          <div className="rb-panel-head"><span>Upload a Web</span></div>
          <div style={{ padding: '10px 12px' }}>
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
              <div style={{ flex: 1, minWidth: 220 }}>
                <label style={labelStyle} htmlFor="w-name">Name *</label>
                <input id="w-name" className="rb-input" style={{ width: '100%' }} value={name} maxLength={60}
                  onChange={(e) => setName(e.target.value)} placeholder="My First Web" />
                <label style={labelStyle} htmlFor="w-desc">Description</label>
                <textarea id="w-desc" className="rb-input" style={{ width: '100%', minHeight: 54 }} value={description} maxLength={800}
                  onChange={(e) => setDescription(e.target.value)} placeholder="What does your web do?" />
                <label style={labelStyle} htmlFor="w-genre">Genre</label>
                <select id="w-genre" className="rb-select" style={{ width: '100%' }} value={genre} onChange={(e) => setGenre(e.target.value)}>
                  {GENRES.filter((g) => g !== 'All Genres').map((g) => <option key={g} value={g}>{g}</option>)}
                </select>
              </div>
              <div style={{ flex: 1.4, minWidth: 260 }}>
                <label style={labelStyle} htmlFor="w-file">Upload an .html file</label>
                <input id="w-file" type="file" accept=".html,.htm,.txt" className="rb-input" style={{ width: '100%', fontSize: 10 }}
                  onChange={(e) => loadFile(e.target.files?.[0] || null)} />
                <div style={{ fontSize: 10, color: '#7b8896', marginTop: 3 }}>
                  The file's code lands in the editor below — tweak it and publish.
                </div>
              </div>
            </div>

            {/* code studio (dark) */}
            <div style={{ background: '#101820', border: '1px solid #24425f', borderRadius: 4, padding: 10, marginTop: 10 }}>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 8, alignItems: 'center' }}>
                <span style={{ fontSize: 10, color: '#7fd4ff', fontWeight: 700 }}>YOUR CODE</span>
                <span style={{ fontSize: 10, color: '#9db4c6' }}>starters:</span>
                {WEB_TEMPLATES.map((t) => (
                  <button key={t.id} type="button" title={t.blurb} className="rb-btn"
                    style={{ fontSize: 10, background: template === t.id ? '#0d69ac' : '#1c3a5c', color: '#fff', borderColor: '#24425f' }}
                    onClick={() => { setWebCode(t.code); setTemplate(t.id); setTestOpen(false) }}>
                    {t.label}
                  </button>
                ))}
              </div>
              <textarea
                aria-label="Web code editor"
                value={webCode}
                onChange={(e) => { setWebCode(e.target.value); setTemplate('') }}
                rows={14} spellCheck={false} maxLength={200000}
                placeholder="Paste your HTML/JS here, load an .html file, or press a starter template..."
                style={{
                  width: '100%', resize: 'vertical', background: '#0b1218', color: '#bfe3ff',
                  border: '1px solid #24425f', borderRadius: 3, padding: 10,
                  fontFamily: "'Courier New', monospace", fontSize: 12, lineHeight: 1.55,
                  outline: 'none', whiteSpace: 'pre', overflowX: 'auto',
                }}
              />
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                <button type="button" className="rb-btn rb-btn-green" style={{ fontSize: 11 }} onClick={() => { setTestOpen(true); setTestKey((n) => n + 1) }}>
                  &#9654; Test Play
                </button>
                {testOpen && (
                  <button type="button" className="rb-btn" style={{ fontSize: 10 }} onClick={() => setTestKey((n) => n + 1)}>
                    &#10227; Restart test
                  </button>
                )}
                <span style={{ fontSize: 10, color: '#9db4c6' }}>
                  {webCode.length ? `${(webCode.length / 1024).toFixed(1)}KB` : '0KB'} / 200KB
                </span>
              </div>
              {testOpen && (
                <div style={{ marginTop: 8, border: '1px solid #24425f', borderRadius: 3, overflow: 'hidden' }}>
                  <iframe
                    key={testKey}
                    title="Web test play"
                    srcDoc={buildWebGameDoc(webCode)}
                    sandbox="allow-scripts allow-pointer-lock allow-modals"
                    style={{ display: 'block', width: '100%', height: 340, border: '0', background: '#101820' }}
                  />
                </div>
              )}
            </div>

            {error && (
              <div style={{ marginTop: 8, fontSize: 11, color: '#a11', background: '#fdeaea', border: '1px solid #d99', borderRadius: 3, padding: '6px 10px' }}>
                {error}
              </div>
            )}
            <div style={{ marginTop: 10, display: 'flex', gap: 8, alignItems: 'center' }}>
              <button className="rb-btn rb-btn-red" style={{ fontSize: 12 }} disabled={busy} onClick={publish}>
                {busy ? 'Publishing...' : 'Publish Web'}
              </button>
              <span style={{ fontSize: 10, color: '#7b8896' }}>
                Your code runs in a sandbox — it can never touch RetroBlox accounts.
              </span>
            </div>
          </div>
        </div>
      )}

      {/* just-published banner */}
      {published && (
        <div className="rb-box" style={{ marginBottom: 12, padding: '10px 12px', background: '#eafaf0', borderColor: '#7dbb8f' }}>
          <span style={{ fontSize: 12, color: '#1c5e30', fontWeight: 700 }}>
            Published!{typeof published.seqId === 'number' ? ` Game ID: #${published.seqId}` : ''}
          </span>{' '}
          <Link className="rb-btn rb-btn-green" href={`/play/${published.id}`} style={{ fontSize: 11, textDecoration: 'none', marginLeft: 8 }}>
            Open your web
          </Link>
        </div>
      )}

      {/* the webs grid */}
      <div className="rb-box" style={{ marginBottom: 10, padding: '6px 10px', display: 'flex', alignItems: 'center' }}>
        <span style={{ fontSize: 12, fontWeight: 700, color: '#24425f' }}>All Webs</span>
        <span style={{ marginLeft: 'auto', fontSize: 10, color: '#7b8896' }}>
          {webs === null ? '...' : `${webs.length} web${webs.length === 1 ? '' : 's'}`}
        </span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: 10 }}>
        {webs === null
          ? Array.from({ length: 4 }).map((_, i) => <div key={i} className="rb-box" style={{ height: 150, background: '#f0f4f8' }} />)
          : webs.map((w) => <WebCard key={w.id} web={w} />)}
      </div>
      {webs !== null && webs.length === 0 && (
        <div className="rb-box" style={{ padding: 30, textAlign: 'center', color: '#5a6b7b' }}>
          <div style={{ fontSize: 14, marginBottom: 4 }}>No webs yet — the tab is brand new.</div>
          <div style={{ fontSize: 11, marginBottom: 12 }}>Be the first: press <strong>+ Upload a Web</strong> above!</div>
        </div>
      )}
    </div>
  )
}

/* A web card — opens the sandbox directly, with a details link under it. */
function WebCard({ web }: { web: GameSummary }) {
  const cover = web.thumbnailUrl || web.iconUrl
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
      <Link
        href={`/play/${web.id}`}
        className="rb-clickable"
        style={{
          textAlign: 'left', background: '#fff', border: '1px solid #a8b6c2', borderRadius: 3,
          padding: 5, boxShadow: '1px 1px 0 rgba(0,0,0,.12)', textDecoration: 'none',
          display: 'flex', flexDirection: 'column', gap: 5, transition: 'transform 90ms, border-color 90ms',
        }}
        aria-label={`Open the web ${web.name}`}
      >
        <div style={{ position: 'relative', height: 86, background: '#101820', border: '1px solid #8ba0b3', overflow: 'hidden' }}>
          {cover ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={cover} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          ) : (
            <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#7fd4ff', fontFamily: "'Courier New', monospace", fontSize: 20 }}>
              &lt;/&gt;
            </div>
          )}
          <span style={{ position: 'absolute', right: 3, bottom: 3, fontSize: 9, background: 'rgba(13,105,172,.92)', color: '#fff', borderRadius: 3, padding: '1px 5px' }}>
            WEB
          </span>
        </div>
        <div style={{ fontSize: 11, fontWeight: 700, color: '#1c4e7c', lineHeight: 1.25, minHeight: 26 }}>
          {web.name}
        </div>
        <div style={{ fontSize: 10, color: '#7b8896' }}>
          by {web.creator.username} · {fmtCount(web.downloads)} plays
        </div>
        <span className="rb-btn rb-btn-green" style={{ fontSize: 10, textAlign: 'center', display: 'block' }}>
          Open
        </span>
      </Link>
      <Link href={`/games/${web.id}`} style={{ fontSize: 9, color: '#7b8896', textAlign: 'right', textDecoration: 'none' }}>
        details ›
      </Link>
    </div>
  )
}
