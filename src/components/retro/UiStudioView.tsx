'use client'

/* ================= RetroBlox UI STUDIO (/ui-studio) =================
   Edit a game's UI ON THE WEB: add TEXT, ICONS, IMAGES and BUTTONS
   that open URLs — drag them anywhere on the stage, give them CLICK
   and HOVER effects (punch, bounce, scale-then-rotate, glow, fade),
   tune power + speed, or compose your own fx mix.

   WHO SEES WHAT:
   - The game OWNER publishes here -> every player of that game sees
     the UI (the desktop player fetches it when the game starts).
   - Anybody else's personal UI tweaks live in the desktop player's
     own F2 editor and stay on their device — private, like before. */

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRetro } from '@/lib/store'

const INK = '#1c3a52'
const DIM = '#5a6b7b'
const EDGE = '#b6c0cb'
const STAGE_W = 960
const STAGE_H = 540

const SWATCHES = ['f2f3f3', '1b2a34', 'c4281c', 'e8752a', 'f5cd30', '4b974b', '009999', '0d69ac', '6b327c', 'e8bac8', '7c5c46', '635f62']

type Fx = { click: string; hover: string; power: number; speed: number }
type Widget = {
  id: string; kind: string; x: number; y: number; w: number; h: number
  text: string; size: number; color: string; url?: string; fx?: Fx
}

const KINDS: { k: string; label: string; w: number; h: number }[] = [
  { k: 'label', label: 'Text', w: 200, h: 30 },
  { k: 'icon', label: 'Icon', w: 48, h: 48 },
  { k: 'image', label: 'Image', w: 180, h: 130 },
  { k: 'button', label: 'Button', w: 150, h: 42 },
  { k: 'panel', label: 'Panel', w: 240, h: 130 },
  { k: 'textbox', label: 'Text Box', w: 190, h: 36 },
  { k: 'healthbar', label: 'Health Bar', w: 200, h: 20 },
  { k: 'money', label: 'Money', w: 110, h: 30 },
]

function emptyFx(): Fx {
  return { click: 'none', hover: 'none', power: 1.4, speed: 2.0 }
}

/* the widget's fx as a tiny CSS style — the SAME names the Godot kit plays */
function fxStyle(fx: Fx | undefined): React.CSSProperties {
  if (!fx || fx.hover === 'none') return { transition: 'transform .15s ease, filter .15s ease, opacity .15s ease' }
  if (fx.hover === 'scalerot') return { transition: 'transform .15s cubic-bezier(.34,1.56,.64,1)' }
  if (fx.hover === 'glow') return { transition: 'filter .15s ease' }
  if (fx.hover === 'fade') return { transition: 'opacity .15s ease' }
  return {}
}

function fxHover(fx: Fx | undefined): string {
  if (!fx || fx.hover === 'none') return ''
  if (fx.hover === 'scalerot') return 'ui-studio-hover-scalerot'
  if (fx.hover === 'glow') return 'ui-studio-hover-glow'
  if (fx.hover === 'fade') return 'ui-studio-hover-fade'
  return ''
}

export function UiStudioView() {
  const { user, setToast } = useRetro()
  const [games, setGames] = useState<{ id: string; seqId: number | null; name: string; hasFile: boolean }[]>([])
  const [gameId, setGameId] = useState('')
  const [gameName, setGameName] = useState('')
  const [widgets, setWidgets] = useState<Widget[]>([])
  const [selId, setSelId] = useState('')
  const [loading, setLoading] = useState(false)
  const [dirty, setDirty] = useState(false)
  const dragRef = useRef<{ id: string; dx: number; dy: number } | null>(null)
  const stageRef = useRef<HTMLDivElement>(null)

  const sel: Widget | undefined = widgets.find((w) => w.id === selId)

  useEffect(() => {
    if (!user) return
    fetch(`/api/games?creatorId=${user.id}&limit=100`)
      .then((r) => r.json())
      .then((d) => setGames(d.games || []))
      .catch(() => {})
  }, [user])

  const loadConfig = useCallback(async (gid: string) => {
    setLoading(true)
    setSelId('')
    try {
      const r = await fetch(`/api/games/${gid}/ui-config`)
      const d = await r.json()
      const list: Widget[] = (d.uiConfig && Array.isArray(d.uiConfig.widgets)) ? d.uiConfig.widgets : []
      setWidgets(list)
      setDirty(false)
    } catch { setWidgets([]) }
    setLoading(false)
  }, [])

  function pickGame(g: { id: string; name: string }) {
    setGameId(g.id)
    setGameName(g.name)
    loadConfig(g.id)
  }

  function patch(next: Partial<Widget>) {
    if (!sel) return
    setWidgets((ws) => ws.map((w) => (w.id === sel.id ? { ...w, ...next } : w)))
    setDirty(true)
  }

  function patchFx(next: Partial<Fx>) {
    if (!sel) return
    const fx = { ...emptyFx(), ...(sel.fx || {}), ...next }
    patch({ fx })
  }

  function addWidget(kind: string) {
    const def = KINDS.find((k) => k.k === kind) || KINDS[0]
    const w: Widget = {
      id: `w_${Date.now()}_${Math.floor(Math.random() * 9999)}`,
      kind, x: 60 + (widgets.length % 6) * 30, y: 60 + (widgets.length % 6) * 26,
      w: def.w, h: def.h, text: '', size: 16, color: '0d69ac',
      fx: kind === 'button' ? { click: 'punch', hover: 'scalerot', power: 1.4, speed: 2.0 } : emptyFx(),
    }
    setWidgets((ws) => [...ws, w])
    setSelId(w.id)
    setDirty(true)
  }

  function removeWidget() {
    if (!sel) return
    setWidgets((ws) => ws.filter((w) => w.id !== sel.id))
    setSelId('')
    setDirty(true)
  }

  /* drag to move — the whole point */
  function onWidgetMouseDown(e: React.MouseEvent, w: Widget) {
    e.stopPropagation()
    setSelId(w.id)
    const stage = stageRef.current
    if (!stage) return
    const rect = stage.getBoundingClientRect()
    const scale = rect.width / STAGE_W
    dragRef.current = { id: w.id, dx: (e.clientX - rect.left) / scale - w.x, dy: (e.clientY - rect.top) / scale - w.y }
  }

  useEffect(() => {
    function move(e: MouseEvent) {
      const d = dragRef.current
      const stage = stageRef.current
      if (!d || !stage) return
      const rect = stage.getBoundingClientRect()
      const scale = rect.width / STAGE_W
      const x = Math.max(0, Math.min(STAGE_W - 20, Math.round((e.clientX - rect.left) / scale - d.dx)))
      const y = Math.max(0, Math.min(STAGE_H - 12, Math.round((e.clientY - rect.top) / scale - d.dy)))
      setWidgets((ws) => ws.map((w) => (w.id === d.id ? { ...w, x, y } : w)))
      setDirty(true)
    }
    function up() { dragRef.current = null }
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', up)
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up) }
  }, [])

  /* CLICK fx preview — a real keyframe punch on mousedown */
  function widgetMouseDownFx(e: React.MouseEvent, w: Widget) {
    const fx = w.fx
    if (!fx || fx.click === 'none') return
    const el = e.currentTarget as HTMLElement
    const p = Math.max(0.5, Math.min(3, fx.power))
    const sp = Math.max(0.5, Math.min(3, fx.speed))
    if (fx.click === 'punch') {
      el.animate([
        { transform: 'scale(1)' }, { transform: `scale(${1 + 0.22 * p})` },
        { transform: 'scale(0.94)' }, { transform: 'scale(1)' },
      ], { duration: 230 / sp, easing: 'ease-out' })
    } else if (fx.click === 'bounce') {
      el.animate([
        { transform: 'scale(1,1)' }, { transform: `scale(${1 + 0.18 * p},${1 - 0.11 * p})` },
        { transform: `scale(${1 - 0.09 * p},${1 + 0.14 * p})` }, { transform: 'scale(1,1)' },
      ], { duration: 270 / sp, easing: 'ease-in-out' })
    }
  }

  async function save() {
    if (!gameId) return
    setLoading(true)
    try {
      const body = new FormData()
      body.append('uiConfig', JSON.stringify({ widgets }))
      const r = await fetch(`/api/games/${gameId}`, { method: 'PATCH', body })
      const d = await r.json().catch(() => ({}))
      if (!r.ok) {
        setToast(d.error || 'Save failed')
      } else {
        setToast('PUBLISHED — every player of this game sees this UI!')
        setDirty(false)
      }
    } catch { setToast('Save failed') }
    setTimeout(() => setToast(null), 3200)
    setLoading(false)
  }

  async function clearUi() {
    if (!gameId) return
    setLoading(true)
    try {
      const body = new FormData()
      body.append('clearUiConfig', '1')
      await fetch(`/api/games/${gameId}`, { method: 'PATCH', body })
      setWidgets([])
      setDirty(false)
      setToast('Published UI cleared — the game is back to player-made UIs only')
    } catch { /* ignore */ }
    setTimeout(() => setToast(null), 2600)
    setLoading(false)
  }

  /* ------------------------------------------------------------ no login */
  if (!user) {
    return (
      <div className="rb-box" style={{ padding: 20, textAlign: 'center' }}>
        <div style={{ fontSize: 15, color: INK, fontWeight: 700 }}>UI Studio</div>
        <div style={{ fontSize: 11, color: DIM, marginTop: 6 }}>
          Log in to publish a UI for your game — the buttons, text, images and effects every player sees.
        </div>
        <Link className="rb-btn rb-btn-red" href="/login" style={{ textDecoration: 'none', display: 'inline-block', marginTop: 12 }}>Log In</Link>
      </div>
    )
  }

  /* ------------------------------------------------------- game picker */
  if (!gameId) {
    return (
      <div>
        <div className="rb-box" style={{ marginBottom: 12 }}>
          <div className="rb-panel-head"><span>UI Studio — pick YOUR game</span></div>
          <div style={{ padding: 12 }}>
            <div style={{ fontSize: 11, color: DIM, marginBottom: 10 }}>
              What you publish here, EVERY player of that game sees. Your own private tweaks still live in the desktop player&apos;s F2 editor.
            </div>
            {games.length === 0 ? (
              <div style={{ fontSize: 11, color: DIM }}>
                You have no games yet — <Link className="rb-link" href="/create">publish one</Link> (a Web game counts), then come back.
              </div>
            ) : (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 8 }}>
                {games.map((g) => (
                  <button key={g.id} className="rb-btn" onClick={() => pickGame(g)} style={{ textAlign: 'left', padding: '10px 12px' }}>
                    <div style={{ fontSize: 12, fontWeight: 700, color: INK }}>{g.name}</div>
                    <div style={{ fontSize: 10, color: DIM }}>Game #{g.seqId ?? '—'}</div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    )
  }

  /* ------------------------------------------------------- the editor */
  return (
    <div>
      <style>{`
        .ui-studio-hover-scalerot:hover { transform: scale(1.07) rotate(2.2deg); }
        .ui-studio-hover-glow:hover { filter: brightness(1.18) saturate(1.2); }
        .ui-studio-hover-fade:hover { opacity: 0.72; }
      `}</style>

      <div className="rb-box" style={{ marginBottom: 12, padding: '10px 14px', display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <button className="rb-btn" onClick={() => { setGameId(''); setWidgets([]) }} style={{ fontSize: 11 }}>&larr; Games</button>
        <div style={{ flex: 1, minWidth: 200 }}>
          <span style={{ fontSize: 13, fontWeight: 700, color: INK }}>{gameName}</span>
          <span style={{ fontSize: 10, color: DIM, marginLeft: 8 }}>
            published UI — everyone sees it {dirty ? '• UNSAVED CHANGES' : ''}
          </span>
        </div>
        <button className="rb-btn" onClick={clearUi} style={{ fontSize: 11 }}>Clear published UI</button>
        <button className="rb-btn rb-btn-green" onClick={save} disabled={loading} style={{ fontSize: 12, textDecoration: 'none' }}>
          {loading ? '...' : '⬆ Publish to EVERYONE'}
        </button>
      </div>

      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap' }}>
        {/* ---- shelf + stage ---- */}
        <div style={{ flex: '1 1 620px', minWidth: 320 }}>
          <div className="rb-box" style={{ marginBottom: 10, padding: '8px 10px', display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {KINDS.map((k) => (
              <button key={k.k} className="rb-btn" onClick={() => addWidget(k.k)} style={{ fontSize: 11, padding: '6px 10px' }}>
                + {k.label}
              </button>
            ))}
          </div>
          <div className="rb-box" style={{ padding: 10 }}>
            <div
              ref={stageRef}
              onMouseDown={() => setSelId('')}
              style={{
                position: 'relative', width: '100%', aspectRatio: `${STAGE_W} / ${STAGE_H}`,
                background: 'linear-gradient(180deg,#f4f7fa 0%,#e8eef4 100%)',
                border: `1px solid ${EDGE}`, overflow: 'hidden',
                backgroundImage: 'radial-gradient(#c9d4de 1px, transparent 1px)', backgroundSize: '24px 24px',
              }}
            >
              {loading ? <div style={{ fontSize: 11, color: DIM, padding: 10 }}>Loading…</div> : null}
              {widgets.map((w) => (
                <div
                  key={w.id}
                  onMouseDown={(e) => onWidgetMouseDown(e, w)}
                  onMouseDownCapture={(e) => widgetMouseDownFx(e, w)}
                  className={fxHover(w.fx)}
                  style={{
                    position: 'absolute', left: `${(w.x / STAGE_W) * 100}%`, top: `${(w.y / STAGE_H) * 100}%`,
                    width: `${(w.w / STAGE_W) * 100}%`, height: `${(w.h / STAGE_H) * 100}%`,
                    ...fxStyle(w.fx),
                    outline: selId === w.id ? '2px solid #e2231a' : '1px dashed rgba(13,105,172,.35)',
                    cursor: 'move', display: 'flex', alignItems: 'center', justifyContent: 'center',
                    background: w.kind === 'panel' ? `#${w.color}d1` : w.kind === 'image' && !w.url ? `#${w.color}59` : 'transparent',
                    borderRadius: w.kind === 'panel' || w.kind === 'image' ? 8 : 0,
                    overflow: 'hidden', fontSize: 11, fontFamily: 'Verdana, Arial, sans-serif',
                  }}
                >
                  {w.kind === 'image' && w.url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={w.url} alt={w.text || 'image'} style={{ width: '100%', height: '100%', objectFit: 'contain' }} draggable={false} />
                  ) : w.kind === 'healthbar' ? (
                    <div style={{ width: '100%', height: '100%', background: '#17181a', borderRadius: 4, overflow: 'hidden' }}>
                      <div style={{ width: '80%', height: '100%', background: `#${w.color}` }} />
                    </div>
                  ) : w.kind === 'textbox' ? (
                    <div style={{ width: '100%', height: '100%', background: '#17181a', color: '#fff', borderRadius: 4, display: 'flex', alignItems: 'center', paddingLeft: 8, fontSize: Math.max(10, w.size * 0.8), opacity: 0.9 }}>
                      {w.text || 'type here...'}
                    </div>
                  ) : (
                    <span style={{
                      color: w.kind === 'money' ? '#3fdc6a' : `#${w.color}`,
                      fontWeight: 700,
                      fontSize: w.kind === 'icon' ? Math.max(20, (w.h / STAGE_H) * 720 * 0.5) : w.size,
                      textShadow: '0 1px 2px rgba(0,0,0,.45)',
                      background: w.kind === 'button' ? `#${w.color}` : 'transparent',
                      padding: w.kind === 'button' ? '4px 12px' : 0,
                      borderRadius: w.kind === 'button' ? 5 : 0,
                    }}>
                      {w.text || (w.kind === 'button' ? 'PRESS ME' : w.kind === 'icon' ? '★' : w.kind === 'label' ? 'YOUR TEXT' : w.kind === 'money' ? '$ 0' : w.kind === 'image' ? 'image' : '')}
                    </span>
                  )}
                  {w.kind === 'button' && w.url ? (
                    <span style={{ position: 'absolute', right: 2, top: 2, fontSize: 8, background: '#1c3a52', color: '#fff', borderRadius: 3, padding: '1px 4px' }}>URL</span>
                  ) : null}
                </div>
              ))}
            </div>
            <div style={{ fontSize: 10, color: DIM, marginTop: 6 }}>
              Drag widgets to move them. Click one to edit its text, look and effects. The stage is {STAGE_W}×{STAGE_H} — the same space the game spawns widgets in.
            </div>
          </div>
        </div>

        {/* ---- props panel ---- */}
        <div className="rb-box" style={{ flex: '1 1 260px', minWidth: 260, padding: 12 }}>
          {!sel ? (
            <div style={{ fontSize: 11, color: DIM }}>
              Select a widget on the stage (or add one above).<br /><br />
              <b style={{ color: INK }}>FX:</b> Hover FX play when the cursor steps on the widget; Click FX fire on press. Mix power + speed to make the effect YOURS — your mix is your fx.
            </div>
          ) : (
            <div style={{ display: 'grid', gap: 10 }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: INK }}>{sel.kind.toUpperCase()} <span style={{ color: DIM, fontWeight: 400 }}>selected</span></div>
              <button className="rb-btn" onClick={removeWidget} style={{ fontSize: 11, color: '#a11' }}>✕ Remove widget</button>

              {['label', 'button', 'icon', 'money', 'textbox', 'image'].includes(sel.kind) ? (
                <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                  {sel.kind === 'icon' ? 'Glyph / emoji' : sel.kind === 'image' ? 'Caption (fallback)' : 'Text'}
                  <input value={sel.text} onChange={(e) => patch({ text: e.target.value })} maxLength={80}
                    style={{ border: `1px solid ${EDGE}`, padding: '6px 8px', fontSize: 12, borderRadius: 4 }} />
                </label>
              ) : null}

              {sel.kind === 'button' ? (
                <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                  Opens this URL when pressed
                  <input value={sel.url || ''} onChange={(e) => patch({ url: e.target.value })} placeholder="https://retro-blox.vercel.app/games"
                    style={{ border: `1px solid ${EDGE}`, padding: '6px 8px', fontSize: 12, borderRadius: 4 }} />
                </label>
              ) : null}

              {sel.kind === 'image' ? (
                <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                  Image URL (png / jpg)
                  <input value={sel.url || ''} onChange={(e) => patch({ url: e.target.value })} placeholder="https://…/logo.png"
                    style={{ border: `1px solid ${EDGE}`, padding: '6px 8px', fontSize: 12, borderRadius: 4 }} />
                </label>
              ) : null}

              {['label', 'button', 'icon', 'money', 'image', 'panel', 'healthbar', 'textbox'].includes(sel.kind) ? (
                <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                  Color
                  <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                    {SWATCHES.map((c) => (
                      <button key={c} onClick={() => patch({ color: c })}
                        style={{ width: 22, height: 22, background: `#${c}`, border: sel.color === c ? '2px solid #e2231a' : '1px solid #9aa7b3', cursor: 'pointer', borderRadius: 3 }} />
                    ))}
                  </div>
                </label>
              ) : null}

              {['label', 'button', 'icon', 'money', 'textbox'].includes(sel.kind) ? (
                <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                  Font size: {sel.size}
                  <input type="range" min={10} max={64} value={sel.size} onChange={(e) => patch({ size: Number(e.target.value) })} />
                </label>
              ) : null}

              <div style={{ borderTop: `1px solid ${EDGE}`, paddingTop: 8, fontSize: 11, color: INK, fontWeight: 700 }}>FX — make it YOURS</div>

              <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                Click FX
                <select value={sel.fx?.click || 'none'} onChange={(e) => patchFx({ click: e.target.value })}
                  style={{ border: `1px solid ${EDGE}`, padding: '6px 8px', fontSize: 12, borderRadius: 4 }}>
                  <option value="none">None</option>
                  <option value="punch">Punch (pop-in slam)</option>
                  <option value="bounce">Bounce (squash &amp; stretch)</option>
                </select>
              </label>

              <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                Hover FX
                <select value={sel.fx?.hover || 'none'} onChange={(e) => patchFx({ hover: e.target.value })}
                  style={{ border: `1px solid ${EDGE}`, padding: '6px 8px', fontSize: 12, borderRadius: 4 }}>
                  <option value="none">None</option>
                  <option value="scalerot">Smooth scale, then rotate a bit</option>
                  <option value="glow">Glow (brightens)</option>
                  <option value="fade">Fade (steps back)</option>
                </select>
              </label>

              <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                Power: {(sel.fx?.power ?? 1.4).toFixed(1)}
                <input type="range" min={0.5} max={3} step={0.1} value={sel.fx?.power ?? 1.4} onChange={(e) => patchFx({ power: Number(e.target.value) })} />
              </label>
              <label style={{ fontSize: 11, color: DIM, display: 'grid', gap: 4 }}>
                Speed: {(sel.fx?.speed ?? 2.0).toFixed(1)}×
                <input type="range" min={0.5} max={3} step={0.1} value={sel.fx?.speed ?? 2.0} onChange={(e) => patchFx({ speed: Number(e.target.value) })} />
              </label>

              <div style={{ fontSize: 10, color: DIM }}>
                Hover the widget on the stage to feel its Hover FX; press it to feel its Click FX.
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="rb-box" style={{ marginTop: 12, padding: 12 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: INK }}>How it reaches the players</div>
        <div style={{ fontSize: 11, color: DIM, marginTop: 4 }}>
          Publish → the desktop player fetches this game&apos;s UI when anyone starts it (game files downloaded from the page carry the game&apos;s ID) →
          your widgets spawn for EVERY player, under their own private F2 widgets. Text boxes fill with real typing, health bars fill with real health,
          link buttons open their URL, and every effect you picked plays in the game.
        </div>
      </div>
    </div>
  )
}
