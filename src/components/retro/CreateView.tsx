'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { useRetro, api, GENRES, SUBGENRE_IDEAS, flash } from '@/lib/store'
import { WEB_TEMPLATES, buildWebGameDoc } from '@/lib/webgame'

/* Publish a game: build file (Unity/Godot/anything), optional source code,
   icon, thumbnail, description, genre + subgenre. New games start at 0 downloads.
   Optionally publish straight into one of your groups.
   ENGINE "Web": skip the build file — write the game IN the browser with
   the code studio (templates + test play) and players run it on the site. */

interface MyGroupT { id: string; name: string; role: string }

export function CreateView() {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const params = useSearchParams()
  const preselectGroup = params.get('group') || ''
  const [myGroups, setMyGroups] = useState<MyGroupT[]>([])
  const [groupId, setGroupId] = useState(preselectGroup)
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [genre, setGenre] = useState('Adventure')
  const [subgenre, setSubgenre] = useState('')
  const [engine, setEngine] = useState('Godot')
  const [maturity, setMaturity] = useState('Minimal')
  // Web studio: the game's code + which starter template is loaded + test play
  const [webCode, setWebCode] = useState('')
  const [webTemplate, setWebTemplate] = useState('blank')
  const [testOpen, setTestOpen] = useState(false)
  const [testKey, setTestKey] = useState(0)
  const [icon, setIcon] = useState<File | null>(null)
  const [thumb, setThumb] = useState<File | null>(null)
  const [gameFile, setGameFile] = useState<File | null>(null)
  const [sourceFile, setSourceFile] = useState<File | null>(null)
  const [mediaFiles, setMediaFiles] = useState<File[]>([])
  const [iconPreview, setIconPreview] = useState<string | null>(null)
  const [thumbPreview, setThumbPreview] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const iconRef = useRef<HTMLInputElement>(null)

  /* groups I belong to, for the "publish into group" select */
  useEffect(() => {
    if (!user) return
    api<{ groups: MyGroupT[] }>(`/api/users/${user.id}`)
      .then((res) => setMyGroups(res.groups || []))
      .catch(() => {})
  }, [user])

  function preview(file: File | null, setter: (v: string | null) => void) {
    if (!file) {
      setter(null)
      return
    }
    const reader = new FileReader()
    reader.onload = () => setter(reader.result as string)
    reader.readAsDataURL(file)
  }

  async function publish(e?: React.FormEvent) {
    e?.preventDefault()
    if (!user) {
      router.push('/login')
      return
    }
    setError('')
    if (name.trim().length < 3) {
      setError('Game name must be at least 3 characters.')
      return
    }
    if (engine === 'Web') {
      if (webCode.trim().length < 10) {
        setError('Your web game needs code! Load a template below the engine picker and start coding.')
        return
      }
    }
    if (engine !== 'Web' && !gameFile) {
      setError('Attach your game build file! (Unity export, Godot pack, .zip, .exe...)')
      return
    }
    setBusy(true)
    try {
      const fd = new FormData()
      fd.append('name', name.trim())
      fd.append('description', description.trim())
      fd.append('genre', genre)
      fd.append('subgenre', subgenre.trim())
      fd.append('engine', engine)
      fd.append('maturity', maturity)
      if (groupId) fd.append('groupId', groupId)
      if (icon) fd.append('icon', icon)
      if (thumb) fd.append('thumbnail', thumb)
      if (engine === 'Web') fd.append('webCode', webCode)
      else if (gameFile) fd.append('gameFile', gameFile)
      if (sourceFile) fd.append('sourceFile', sourceFile)
      for (const m of mediaFiles) fd.append('media', m)

      const res = await api<{ game: { id: string; name: string } }>('/api/games', { method: 'POST', body: fd })
      flash(setToast, 'Game published! It is now live with 0 downloads.')
      // land on the new game's very own URL
      router.push(`/games/${res.game.id}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Publish failed')
      setBusy(false)
    }
  }

  const labelStyle = { fontSize: 11, color: '#24425f', display: 'block', marginBottom: 4 }

  /* live preview of how the game card will look in the grids */
  const previewCard = (
    <aside style={{ width: 260, flexShrink: 0, display: 'grid', gap: 12, alignContent: 'start' }} className="rb-create-rail">
      <div className="rb-box" style={{ padding: 0, overflow: 'hidden' }}>
        <div className="rb-panel-head"><span>Live Preview</span></div>
        <div style={{ padding: 12 }}>
          <div style={{ border: '1px solid #d5dde5', borderRadius: 4, overflow: 'hidden', background: '#fff' }}>
            <div style={{ position: 'relative', aspectRatio: '16 / 9', background: 'linear-gradient(160deg,#12233a,#1c3a5c)' }}>
              {thumbPreview ? (
                <img src={thumbPreview} alt="Thumbnail preview" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#7fd4ff', fontFamily: "'Courier New', monospace", fontSize: 10 }}>
                  your thumbnail here
                </div>
              )}
              <span style={{ position: 'absolute', left: 6, bottom: 6, width: 44, height: 44, border: '2px solid #fff', borderRadius: 4, background: '#eef4fa', overflow: 'hidden', boxShadow: '0 1px 4px rgba(0,0,0,.4)' }}>
                {iconPreview ? (
                  <img src={iconPreview} alt="Icon preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                ) : (
                  <span style={{ display: 'flex', width: '100%', height: '100%', alignItems: 'center', justifyContent: 'center', fontSize: 16, color: '#8ba0b3' }}></span>
                )}
              </span>
            </div>
            <div style={{ padding: '8px 10px 10px' }}>
              <div style={{ fontSize: 12, color: '#1c2733' }}>{name.trim() || 'Untitled Game'}</div>
              <div style={{ fontSize: 10, color: '#7b8896', marginTop: 2 }}>by {user ? user.username : 'you'} · 0 downloads</div>
              <div style={{ display: 'flex', gap: 4, marginTop: 6, flexWrap: 'wrap' }}>
                <span style={{ fontSize: 9, padding: '1px 7px', borderRadius: 8, background: '#eef3f8', border: '1px solid #b4c2cf', color: '#3d566e' }}>{genre}</span>
                {subgenre.trim() && <span style={{ fontSize: 9, padding: '1px 7px', borderRadius: 8, background: '#fdf3d7', border: '1px solid #d9c26a', color: '#8a6d1a' }}>{subgenre.trim()}</span>}
                <span style={{ fontSize: 9, padding: '1px 7px', borderRadius: 8, background: '#f4f8fb', border: '1px solid #c3cdd7', color: '#5a6b7b' }}>{engine}</span>
              </div>
              <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 6, lineHeight: 1.5, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden', minHeight: 30 }}>
                {description.trim() || 'Your description will show up right here.'}
              </div>
            </div>
          </div>
          <div style={{ fontSize: 10, color: '#7b8896', marginTop: 8, lineHeight: 1.6 }}>
            This is how your game card appears in Home, Games and My Games the moment you publish.
          </div>
        </div>
      </div>
    </aside>
  )

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
    <form
      className="rb-box"
      style={{ flex: 1, minWidth: 280, maxWidth: 720, alignSelf: 'flex-start' }}
      onSubmit={publish}
      onKeyDown={(e) => {
        if (e.key === 'Enter' && (e.target as HTMLElement).tagName !== 'TEXTAREA') e.preventDefault()
      }}
    >
      <div className="rb-panel-head">
        <span>Publish a Game</span>
        <span style={{ fontSize: 10, color: '#5a6b7b' }}>Unity · Godot · Unreal · anything!</span>
      </div>
      <div style={{ padding: 12, display: 'grid', gap: 11 }}>
        {error && (
          <div role="alert" style={{ background: '#fdebe9', border: '1px solid #e1231a', color: '#a81a13', fontSize: 11, padding: '7px 10px', borderRadius: 3 }}>
            {error}
          </div>
        )}

        <div>
          <label style={labelStyle} htmlFor="g-name">Game Name *</label>
          <input id="g-name" className="rb-input" value={name} onChange={(e) => setName(e.target.value)} style={{ width: '100%' }} maxLength={60} placeholder="enter your game name" autoFocus />
        </div>

        <div>
          <label style={labelStyle} htmlFor="g-desc">Description</label>
          <textarea id="g-desc" className="rb-textarea" value={description} onChange={(e) => setDescription(e.target.value)} style={{ width: '100%' }} rows={4} maxLength={2000} placeholder="What do players do in your game? Why is it awesome?" />
        </div>

        <div>
          <label style={labelStyle} htmlFor="g-group">Publish To</label>
          <select id="g-group" className="rb-select" value={groupId} onChange={(e) => setGroupId(e.target.value)} style={{ width: '100%' }}>
            <option value="">My profile (personal game)</option>
            {myGroups.map((g) => (
              <option key={g.id} value={g.id}>Group: {g.name}</option>
            ))}
          </select>
          <div style={{ fontSize: 10, color: '#7b8896', marginTop: 4 }}>
            Publishing into a group shows the game on that group&apos;s page too.
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <div>
            <label style={labelStyle} htmlFor="g-genre">Genre *</label>
            <select id="g-genre" className="rb-select" value={genre} onChange={(e) => setGenre(e.target.value)} style={{ width: '100%' }}>
              {GENRES.filter((g) => g !== 'All Genres').map((g) => (
                <option key={g} value={g}>{g}</option>
              ))}
            </select>
          </div>
          <div>
            <label style={labelStyle} htmlFor="g-subgenre">Subgenre</label>
            <input id="g-subgenre" className="rb-input" value={subgenre} onChange={(e) => setSubgenre(e.target.value)} style={{ width: '100%' }} list="subgenre-ideas" placeholder="enter a subgenre" />
            <datalist id="subgenre-ideas">
              {SUBGENRE_IDEAS.map((s) => <option key={s} value={s} />)}
            </datalist>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <div>
            <label style={labelStyle} htmlFor="g-engine">Engine *</label>
            <select id="g-engine" className="rb-select" value={engine} onChange={(e) => { setEngine(e.target.value); setTestOpen(false) }} style={{ width: '100%' }}>
              <option>Unity</option>
              <option>Godot</option>
              <option>Unreal</option>
              <option>GameMaker</option>
              <option>RetroBlox Studio</option>
              <option value="Web">Web — code it right here!</option>
              <option>Other</option>
            </select>
            {engine === 'Unity' && (
              <div style={{ fontSize: 10, color: '#5a6b7b', marginTop: 4 }}>
                Made in Unity? Grab the <a href="/sdk" className="rb-link">RetroBlox Player System</a> — players sign in once and spawn wearing their own avatar.
              </div>
            )}
            {engine === 'Web' && (
              <div style={{ fontSize: 10, color: '#1c4e7c', marginTop: 4 }}>
                No build file needed — write JavaScript below and players play it right on RetroBlox, in their browser, with no download.
              </div>
            )}
          </div>
          <div>
            <label style={labelStyle} htmlFor="g-maturity">Maturity</label>
            <select id="g-maturity" className="rb-select" value={maturity} onChange={(e) => setMaturity(e.target.value)} style={{ width: '100%' }}>
              <option>Minimal</option>
              <option>Mild</option>
              <option>Moderate</option>
            </select>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <div>
            <label style={labelStyle}>Game Icon</label>
            <input type="file" accept="image/*" className="rb-input" style={{ width: '100%', fontSize: 10 }} onChange={(e) => { const f = e.target.files?.[0] || null; setIcon(f); preview(f, setIconPreview) }} />
            <div style={{ marginTop: 6 }}>{iconPreview && (
              <img src={iconPreview} alt="Icon preview" style={{ width: 64, height: 64, objectFit: 'cover', border: '1px solid #8ba0b3' }} />
            )}</div>
          </div>
          <div>
            <label style={labelStyle}>Thumbnail</label>
            <input type="file" accept="image/*" className="rb-input" style={{ width: '100%', fontSize: 10 }} onChange={(e) => { const f = e.target.files?.[0] || null; setThumb(f); preview(f, setThumbPreview) }} />
            <div style={{ marginTop: 6 }}>{thumbPreview && (
              <img src={thumbPreview} alt="Thumbnail preview" style={{ width: 112, height: 63, objectFit: 'cover', border: '1px solid #8ba0b3' }} />
            )}</div>
          </div>
        </div>

        {engine === 'Web' ? (
          <div style={{ background: '#101820', border: '1px solid #24425f', borderRadius: 4, padding: 10 }}>
            <label style={{ ...labelStyle, color: '#7fd4ff' }}>Web Game Studio — your code *</label>
            {/* starter templates */}
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 8 }}>
              <span style={{ fontSize: 10, color: '#9db4c6', alignSelf: 'center' }}>Starters:</span>
              {WEB_TEMPLATES.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => { setWebCode(t.code); setWebTemplate(t.id); setTestOpen(false) }}
                  title={t.blurb}
                  className="rb-btn"
                  style={{
                    fontSize: 10,
                    background: webTemplate === t.id ? '#0d69ac' : '#1c3a5c',
                    color: '#fff',
                    borderColor: '#24425f',
                  }}
                >
                  {t.label}
                </button>
              ))}
            </div>
            <textarea
              aria-label="Game code editor"
              value={webCode}
              onChange={(e) => setWebCode(e.target.value)}
              rows={16}
              spellCheck={false}
              maxLength={200000}
              placeholder="Write your game here, or press a starter template above..."
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
                {' '}&middot; helpers: RetroBlox.say / .score / .win / .lose
              </span>
            </div>
            {testOpen && (
              <div style={{ marginTop: 8, border: '1px solid #24425f', borderRadius: 3, overflow: 'hidden' }}>
                <iframe
                  key={testKey}
                  title="Web game test play"
                  srcDoc={buildWebGameDoc(webCode)}
                  sandbox="allow-scripts allow-pointer-lock allow-modals"
                  style={{ display: 'block', width: '100%', height: 360, border: '0', background: '#101820' }}
                />
              </div>
            )}
            <div style={{ fontSize: 10, color: '#9db4c6', marginTop: 8, lineHeight: 1.6 }}>
              Your JavaScript runs inside a safe sandbox on the play page — it cannot touch RetroBlox accounts.
              If your code has a bug, a red <strong>Code error</strong> banner shows the exact line. You can also paste a full
              HTML document (with your own &lt;canvas&gt; and &lt;style&gt;) instead of plain JS.
            </div>
          </div>
        ) : (
          <div style={{ background: '#f4f8fb', border: '1px dashed #9db2c4', borderRadius: 4, padding: 10 }}>
            <label style={labelStyle}>Game Build File * <span style={{ color: '#7b8896' }}>(max 60MB)</span></label>
            <input type="file" className="rb-input" style={{ width: '100%', fontSize: 10 }} onChange={(e) => setGameFile(e.target.files?.[0] || null)} />
            <div style={{ fontSize: 10, color: '#7b8896', marginTop: 4 }}>
              Unity build (.zip / .exe / .apk), Godot pack (.pck / .zip) — players download it and hit Play now.
            </div>
          </div>
        )}

        {engine !== 'Web' && (
          <div style={{ background: '#f6f6f4', border: '1px dashed #b8b2a4', borderRadius: 4, padding: 10 }}>
            <label style={labelStyle}>Source Code (optional) <span style={{ color: '#7b8896' }}>— like GitHub!</span></label>
            <input type="file" className="rb-input" style={{ width: '100%', fontSize: 10 }} onChange={(e) => setSourceFile(e.target.files?.[0] || null)} />
            <div style={{ fontSize: 10, color: '#7b8896', marginTop: 4 }}>
              Share your project source (.zip) so others can remix your game.
            </div>
          </div>
        )}

        <div style={{ background: '#fdf6ee', border: '1px dashed #d9c26a', borderRadius: 4, padding: 10 }}>
          <label style={labelStyle}>Trailer &amp; Screenshots (optional) <span style={{ color: '#7b8896' }}>— Steam-style media gallery!</span></label>
          <input
            type="file"
            multiple
            accept="video/*,image/*"
            className="rb-input"
            style={{ width: '100%', fontSize: 10 }}
            onChange={(e) => {
              const picked = Array.from(e.target.files || [])
              setMediaFiles((m) => [...m, ...picked].slice(0, 8))
              e.target.value = ''
            }}
          />
          {mediaFiles.length > 0 && (
            <div style={{ marginTop: 6, display: 'grid', gap: 4 }}>
              {mediaFiles.map((m, i) => (
                <div key={`${m.name}-${i}`} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 10, color: '#24425f', background: '#fff', border: '1px solid #e4eaf0', borderRadius: 3, padding: '4px 8px' }}>
                  <span>{m.type.startsWith('video/') ? 'VIDEO' : 'IMAGE'}</span>
                  <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{m.name}</span>
                  <span style={{ color: '#7b8896' }}>{Math.ceil(m.size / (1024 * 1024))}MB</span>
                  <button type="button" className="rb-link" style={{ background: 'none', border: 'none', padding: 0, fontSize: 10, color: '#a03a34' }} onClick={() => setMediaFiles((arr) => arr.filter((_, j) => j !== i))}>
                    remove
                  </button>
                </div>
              ))}
            </div>
          )}
          <div style={{ fontSize: 10, color: '#7b8896', marginTop: 4 }}>
            Up to 8 items — videos 100MB each, images 8MB. Players flip through them like Steam (videos play right on the page).
          </div>
        </div>

        <button className="rb-btn rb-btn-red" type="submit" disabled={busy} style={{ fontSize: 14, padding: '10px 0' }}>
          {busy ? 'Publishing...' : 'Publish Game'}
        </button>
        <div style={{ fontSize: 10, color: '#7b8896', textAlign: 'center' }}>
          New games start with 0 downloads — share the link with friends!
        </div>
      </div>
    </form>
    {previewCard}
    </div>
  )
}
