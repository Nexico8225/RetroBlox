'use client'

import { Fragment, useEffect, useRef, useState } from 'react'

/* RetroBlox text effects — forum-style [tag]...[/tag] markup that STACKS.
   Wrap any selected text (profile bio, comments, posts) in one or more
   effects; the renderer composes them, e.g. [rainbow][wave]hi[/wave][/rainbow].
   The toolbar is an organized "FX Menu" popover: every effect button previews
   its own look right on its label (Rainbow is rendered rainbow), and a live
   preview at the bottom shows the result on your real text. */

export interface FxDef {
  tag: string
  label: string
  cls: string
  hint: string
  perLetter?: boolean
  group: 'fx' | 'color'
}

export const FX_LIST: FxDef[] = [
  { tag: 'rainbow', label: 'Rainbow', cls: 'fx-rainbow', hint: 'animated rainbow colors', group: 'fx' },
  { tag: 'wave', label: 'Wave', cls: 'fx-wave', hint: 'letters ride a wave', perLetter: true, group: 'fx' },
  { tag: 'wiggle', label: 'Wiggle', cls: 'fx-wiggle', hint: 'wiggly jitter', group: 'fx' },
  { tag: 'swirl', label: 'Whirly', cls: 'fx-swirl', hint: 'spinning wobble', group: 'fx' },
  { tag: 'bounce', label: 'Bounce', cls: 'fx-bounce', hint: 'letters bounce', perLetter: true, group: 'fx' },
  { tag: 'shake', label: 'Shake', cls: 'fx-shake', hint: 'angry shaking', group: 'fx' },
  { tag: 'glow', label: 'Glow', cls: 'fx-glow', hint: 'glowing pulse', group: 'fx' },
  { tag: 'neon', label: 'Neon', cls: 'fx-neon', hint: 'flickering neon tube', group: 'fx' },
  { tag: 'fire', label: 'Fire', cls: 'fx-fire', hint: 'burning gradient', group: 'fx' },
  { tag: 'ice', label: 'Ice', cls: 'fx-ice', hint: 'frozen shimmer', group: 'fx' },
  { tag: 'sparkle', label: 'Sparkle', cls: 'fx-sparkle', hint: 'twinkling stars', group: 'fx' },
  { tag: 'pulse', label: 'Pulse', cls: 'fx-pulse', hint: 'breathing size', group: 'fx' },
  { tag: 'flip', label: 'Flip', cls: 'fx-flip', hint: 'flips upside down', group: 'fx' },
  { tag: 'ghost', label: 'Ghost', cls: 'fx-ghost', hint: 'fades in and out', group: 'fx' },
  { tag: 'tilt', label: 'Tilt', cls: 'fx-tilt', hint: 'tips side to side', group: 'fx' },
  { tag: 'spin', label: 'Spin', cls: 'fx-spin', hint: 'letters twirl around', perLetter: true, group: 'fx' },
  { tag: 'flash', label: 'Flash', cls: 'fx-flash', hint: 'blinks on and off', group: 'fx' },
  { tag: 'shadow', label: '3D', cls: 'fx-shadow', hint: 'hard 3D block shadow', group: 'fx' },
  { tag: 'orbit', label: 'Orbit', cls: 'fx-orbit', hint: 'letters circle their spot', perLetter: true, group: 'fx' },
  { tag: 'big', label: 'Big', cls: 'fx-big', hint: 'jumbo size', group: 'fx' },
  { tag: 'red', label: 'Red', cls: 'fx-red', hint: 'red text', group: 'color' },
  { tag: 'blue', label: 'Blue', cls: 'fx-blue', hint: 'blue text', group: 'color' },
  { tag: 'green', label: 'Green', cls: 'fx-green', hint: 'green text', group: 'color' },
  { tag: 'gold', label: 'Gold', cls: 'fx-gold', hint: 'gold text', group: 'color' },
  { tag: 'pink', label: 'Pink', cls: 'fx-pink', hint: 'pink text', group: 'color' },
  { tag: 'purple', label: 'Purple', cls: 'fx-purple', hint: 'purple text', group: 'color' },
]

const FX_MAP: Record<string, FxDef> = Object.fromEntries(FX_LIST.map((f) => [f.tag, f]))

/* ---------- markup helpers ---------- */

export function wrapTag(value: string, selStart: number, selEnd: number, tag: string) {
  const a = value.slice(0, selStart)
  const sel = value.slice(selStart, selEnd)
  const b = value.slice(selEnd)
  const open = `[${tag}]`
  const close = `[/${tag}]`
  return {
    value: a + open + sel + close + b,
    selStart: selStart + open.length,
    selEnd: selStart + open.length + sel.length,
  }
}

export function stripFx(value: string) {
  const known = FX_LIST.map((f) => f.tag).join('|')
  return value.replace(new RegExp(`\\[(/?(?:${known}))\\]`, 'gi'), '')
}

/* ---------- parser ---------- */

type FxNode = string | { tag: string; kids: FxNode[] }

export function parseFx(src: string): FxNode[] {
  const root: FxNode[] = []
  const stack: { tag: string; kids: FxNode[] }[] = [{ tag: '', kids: root }]
  const re = /\[(\/?)([a-zA-Z]+)\]/g
  let last = 0
  let m: RegExpExecArray | null
  while ((m = re.exec(src))) {
    const before = src.slice(last, m.index)
    if (before) stack[stack.length - 1].kids.push(before)
    const closing = m[1] === '/'
    const tag = m[2].toLowerCase()
    if (!FX_MAP[tag]) {
      stack[stack.length - 1].kids.push(m[0])
    } else if (!closing) {
      const node: { tag: string; kids: FxNode[] } = { tag, kids: [] }
      stack[stack.length - 1].kids.push(node)
      stack.push(node)
    } else {
      for (let i = stack.length - 1; i > 0; i--) {
        if (stack[i].tag === tag) {
          stack.length = i
          break
        }
      }
    }
    last = re.lastIndex
  }
  if (last < src.length) stack[stack.length - 1].kids.push(src.slice(last))
  return root
}

/* ---------- renderer ---------- */

function renderContent(
  nodes: FxNode[],
  counter: { i: number },
  letterCls: string[],
  key: string,
): React.ReactNode {
  return nodes.map((n, idx) => {
    const k = `${key}.${idx}`
    if (typeof n === 'string') {
      if (!letterCls.length) return <Fragment key={k}>{n}</Fragment>
      return Array.from(n).map((ch, j) => (
        <span
          key={`${k}.${j}`}
          className={`fx-char ${letterCls.join(' ')}`}
          style={{ '--i': counter.i++ } as React.CSSProperties}
        >
          {ch}
        </span>
      ))
    }
    const fx = FX_MAP[n.tag]
    const inner = renderContent(n.kids, counter, fx.perLetter ? [...letterCls, fx.cls] : letterCls, k)
    if (fx.perLetter) return <Fragment key={k}>{inner}</Fragment>
    return (
      <span key={k} className={`fx ${fx.cls}`}>
        {inner}
      </span>
    )
  })
}

/* ---------- copy support: rendered FX copies back as [tag]…[/tag] markup ----------
   Old-school BBCode rule: the effect lives IN the text, so copying styled text
   and pasting it into any FX-enabled field (bio, comments, posts, chat, trades)
   re-renders the effects instead of losing them. */

function fxTagsOf(el: Element): string[] {
  const tags: string[] = []
  el.classList.forEach((c) => {
    if (c !== 'fx' && c !== 'fx-char' && c.startsWith('fx-')) {
      const tag = c.slice(3)
      if (FX_MAP[tag]) tags.push(tag)
    }
  })
  return tags
}

function serializeFxNode(node: Node, range: Range): string {
  if (node.nodeType === Node.TEXT_NODE) {
    if (!range.intersectsNode(node)) return ''
    const text = node.textContent || ''
    let start = 0
    let end = text.length
    if (node === range.startContainer) start = range.startOffset
    if (node === range.endContainer) end = range.endOffset
    return text.slice(start, end)
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return ''
  const el = node as Element
  const inner = Array.from(el.childNodes)
    .map((child) => serializeFxNode(child, range))
    .join('')
  if (!inner) return ''
  const tags = fxTagsOf(el)
  if (!tags.length) return inner
  return tags.map((t) => `[${t}]`).join('') + inner + [...tags].reverse().map((t) => `[/${t}]`).join('')
}

export function FxText({ text, style }: { text?: string | null; style?: React.CSSProperties }) {
  if (!text) return null
  const hasFx = text !== stripFx(text)
  const onCopy = hasFx
    ? (e: React.ClipboardEvent<HTMLSpanElement>) => {
        const sel = window.getSelection()
        const root = e.currentTarget
        if (!sel || sel.isCollapsed || sel.rangeCount === 0) return
        const range = sel.getRangeAt(0)
        // only take over the copy when the whole selection lives inside this FX text —
        // otherwise let the browser copy normally
        if (!root.contains(range.startContainer) || !root.contains(range.endContainer)) return
        const markup = serializeFxNode(root, range)
        if (!markup) return
        e.preventDefault()
        e.clipboardData.setData('text/plain', markup)
      }
    : undefined
  return (
    <span style={style} onCopy={onCopy}>
      {renderContent(parseFx(text), { i: 0 }, [], 'fx')}
    </span>
  )
}

/* ---------- icons (pure SVG, no emoji) ---------- */

export function FxIcon({ tag, size = 13 }: { tag: string; size?: number }) {
  const p = { width: size, height: size, viewBox: '0 0 16 16', 'aria-hidden': true as const, style: { flexShrink: 0 } }
  switch (tag) {
    case 'rainbow':
      return (
        <svg {...p}>
          <path d="M2 13a6 6 0 0 1 12 0" fill="none" stroke="#e53935" strokeWidth="2" />
          <path d="M4.4 13a3.6 3.6 0 0 1 7.2 0" fill="none" stroke="#fdd835" strokeWidth="2" />
          <path d="M6.8 13a1.2 1.2 0 0 1 2.4 0" fill="none" stroke="#43a047" strokeWidth="2" />
        </svg>
      )
    case 'wave':
      return (
        <svg {...p}>
          <path d="M1 9c1.8-4 3.2-4 5 0s3.2 4 5 0 2.2-3 4-1" fill="none" stroke="#2f83c8" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      )
    case 'wiggle':
      return (
        <svg {...p}>
          <path d="M1 11l3-6 3 6 3-6 3 6 2-4" fill="none" stroke="#7b1fa2" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )
    case 'swirl':
      return (
        <svg {...p}>
          <path d="M8 8m0-1a1 1 0 0 1 1 1 2 2 0 0 1-2 2 3.2 3.2 0 0 1-3.2-3.2A4.4 4.4 0 0 1 8.2 2.4 5.6 5.6 0 0 1 13.8 8" fill="none" stroke="#e91e63" strokeWidth="1.7" strokeLinecap="round" />
        </svg>
      )
    case 'bounce':
      return (
        <svg {...p}>
          <path d="M1.5 13.5h13" stroke="#5a8f3c" strokeWidth="1.6" strokeLinecap="round" />
          <path d="M2 13c2-1.2 3-5 4-5s2 3.4 4 3.4 2.6-4.6 4-6.4" fill="none" stroke="#7ec44f" strokeWidth="1.7" strokeLinecap="round" />
        </svg>
      )
    case 'shake':
      return (
        <svg {...p}>
          <rect x="5" y="4.5" width="6" height="7" rx="1" fill="none" stroke="#d32f2f" strokeWidth="1.6" />
          <path d="M2.6 6v4M13.4 6v4" stroke="#d32f2f" strokeWidth="1.5" strokeLinecap="round" />
          <path d="M.8 7.2v1.6M15.2 7.2v1.6" stroke="#ef9a9a" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
      )
    case 'glow':
      return (
        <svg {...p}>
          <circle cx="8" cy="8" r="3" fill="#ffb300" />
          <g stroke="#ffb300" strokeWidth="1.5" strokeLinecap="round">
            <path d="M8 1.2v1.8M8 13v1.8M1.2 8H3M13 8h1.8M3.2 3.2l1.3 1.3M11.5 11.5l1.3 1.3M12.8 3.2l-1.3 1.3M4.5 11.5l-1.3 1.3" />
          </g>
        </svg>
      )
    case 'neon':
      return (
        <svg {...p}>
          <path d="M4.5 12V4l7 8V4" fill="none" stroke="#18e0d0" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M4.5 12V4l7 8V4" fill="none" stroke="#9dfaf1" strokeWidth="0.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )
    case 'fire':
      return (
        <svg {...p}>
          <path d="M8 1.5c.6 2.2 3.4 3.4 3.4 6.6A3.9 3.9 0 0 1 8 12a3.9 3.9 0 0 1-3.4-3.9C4.6 5.6 6 4.6 6.2 3c.9.7 1.4 1.5 1.5 2.4C8.5 4.2 8.3 2.8 8 1.5z" fill="#ff6d1f" />
          <path d="M8 13.6c-1.2 0-2-.8-2-1.9 0-1.2 1.1-1.8 2-3.2.9 1.4 2 2 2 3.2 0 1.1-.8 1.9-2 1.9z" fill="#ffd54d" />
        </svg>
      )
    case 'ice':
      return (
        <svg {...p}>
          <g stroke="#4fc3f7" strokeWidth="1.4" strokeLinecap="round">
            <path d="M8 1.5v13M2.4 4.75l11.2 6.5M13.6 4.75L2.4 11.25" />
          </g>
          <circle cx="8" cy="8" r="1.5" fill="#b3e5fc" stroke="#4fc3f7" strokeWidth="0.8" />
        </svg>
      )
    case 'sparkle':
      return (
        <svg {...p}>
          <path d="M8 1.5l1.1 4.1 4.1 1.1-4.1 1.1L8 12l-1.1-4.2-4.1-1.1 4.1-1.1z" fill="#ffd54d" stroke="#e6a817" strokeWidth="0.7" />
          <path d="M12.8 10.2l.55 2 2 .55-2 .55-.55 2-.55-2-2-.55 2-.55z" fill="#fff176" />
        </svg>
      )
    case 'pulse':
      return (
        <svg {...p}>
          <path d="M1.5 8h2.2l1.6-4 2.6 8 2.2-6 1.4 2h3" fill="none" stroke="#ab47bc" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )
    case 'flip':
      return (
        <svg {...p}>
          <path d="M5.5 3.5h5v9h-5z" fill="none" stroke="#4a6fa5" strokeWidth="1.6" />
          <path d="M13.5 3.5v9" stroke="#9db8d4" strokeWidth="1.4" strokeDasharray="2 1.6" strokeLinecap="round" />
          <path d="M2.5 3.5v9" stroke="#9db8d4" strokeWidth="1.4" strokeDasharray="2 1.6" strokeLinecap="round" />
        </svg>
      )
    case 'ghost':
      return (
        <svg {...p}>
          <path d="M3.5 13.5V7a4.5 4.5 0 0 1 9 0v6.5l-1.5-1.2-1.5 1.2-1.5-1.2-1.5 1.2-1.5-1.2z" fill="#e8eaf6" stroke="#7986cb" strokeWidth="1.2" />
          <circle cx="6.6" cy="7.4" r="0.9" fill="#5c6bc0" />
          <circle cx="9.8" cy="7.4" r="0.9" fill="#5c6bc0" />
        </svg>
      )
    case 'tilt':
      return (
        <svg {...p}>
          <path d="M4 12.5L8 3.5l4 9" fill="none" stroke="#ef6c00" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M2.5 14.5h11" stroke="#ffb74d" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
      )
    case 'spin':
      return (
        <svg {...p}>
          <text x="8" y="11.5" textAnchor="middle" fontSize="10" fontWeight="bold" fill="#0d69ac" transform="rotate(28 8 8)">S</text>
          <path d="M13.5 3.2a6.5 6.5 0 0 1 0 9.6" fill="none" stroke="#8fc5e8" strokeWidth="1.4" strokeLinecap="round" strokeDasharray="2.2 1.8" />
        </svg>
      )
    case 'flash':
      return (
        <svg {...p}>
          <path d="M9 1.5L4.5 9h3l-1.2 5.5L11 7H8z" fill="#fdd835" stroke="#e6a817" strokeWidth="0.8" strokeLinejoin="round" />
        </svg>
      )
    case 'shadow':
      return (
        <svg {...p}>
          <rect x="6.2" y="6.2" width="7" height="7" rx="1" fill="#2b3945" />
          <rect x="3.5" y="3.5" width="7" height="7" rx="1" fill="#7cbde0" stroke="#0d69ac" strokeWidth="1" />
        </svg>
      )
    case 'orbit':
      return (
        <svg {...p}>
          <circle cx="8" cy="8" r="2" fill="#0d69ac" />
          <ellipse cx="8" cy="8" rx="6" ry="2.6" fill="none" stroke="#8fc5e8" strokeWidth="1.3" transform="rotate(-24 8 8)" />
          <circle cx="13.4" cy="5.6" r="1.5" fill="#ef6c00" />
        </svg>
      )
    case 'big':
      return (
        <svg {...p}>
          <path d="M2 13L6 3l4 10M3.4 9.6h5.2" fill="none" stroke="#24425f" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M12 13V8m0 0l-2 2m2-2l2 2" stroke="#24425f" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
        </svg>
      )
    case 'red':
    case 'blue':
    case 'green':
    case 'gold':
    case 'pink':
    case 'purple': {
      const fills: Record<string, string> = {
        red: '#e53935', blue: '#1e88e5', green: '#43a047',
        gold: '#e6b422', pink: '#ec407a', purple: '#8e24aa',
      }
      return (
        <svg {...p}>
          <path d="M8 1.6S3.2 7 3.2 10.2a4.8 4.8 0 0 0 9.6 0C12.8 7 8 1.6 8 1.6z" fill={fills[tag]} stroke="rgba(0,0,0,.25)" strokeWidth="0.8" />
        </svg>
      )
    }
    default:
      return null
  }
}

/* ---------- editor toolbar ---------- */

export function FxToolbar({
  taRef,
  value,
  onChange,
  livePreview,
}: {
  /** the text input this toolbar edits (textarea OR single-line input) */
  taRef: React.RefObject<HTMLTextAreaElement | HTMLInputElement | null>
  value: string
  onChange: (v: string) => void
  /** render a BIG always-visible preview panel under the bar (composers) */
  livePreview?: boolean
}) {
  const [open, setOpen] = useState(false)
  const [pos, setPos] = useState<{ top: number; left: number; width: number; maxH: number } | null>(null)
  const wrapRef = useRef<HTMLDivElement>(null)

  // compute a fixed viewport position so no overflow:hidden ancestor can clip us
  const place = () => {
    const bar = wrapRef.current
    if (!bar) return
    const r = bar.getBoundingClientRect()
    const width = Math.min(430, window.innerWidth - 48)
    const left = Math.max(8, Math.min(r.left, window.innerWidth - width - 8))
    const maxH = window.innerHeight - r.bottom - 14
    setPos({ top: r.bottom + 5, left, width, maxH: Math.max(180, maxH) })
  }

  const toggle = () => {
    if (!open) place()
    setOpen((v) => !v)
  }

  useEffect(() => {
    if (!open) return
    const onDoc = (e: MouseEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false)
    }
    const onResize = () => place()
    document.addEventListener('mousedown', onDoc)
    document.addEventListener('keydown', onKey)
    window.addEventListener('resize', onResize)
    return () => {
      document.removeEventListener('mousedown', onDoc)
      document.removeEventListener('keydown', onKey)
      window.removeEventListener('resize', onResize)
    }
  }, [open])

  const apply = (tag: string) => {
    const ta = taRef.current
    let start: number = ta?.selectionStart ?? value.length
    let end: number = ta?.selectionEnd ?? value.length
    // nothing selected? wrap the WHOLE text so the effect is always visible —
    // "the selected text becomes the fx": selection wins, full text is the fallback
    if (end <= start) {
      start = 0
      end = value.length
    }
    const r = wrapTag(value, start, end, tag)
    onChange(r.value)
    requestAnimationFrame(() => {
      const el = taRef.current as (HTMLTextAreaElement | HTMLInputElement | null)
      if (el) {
        el.focus()
        try {
          el.setSelectionRange(r.selStart, r.selEnd)
        } catch {}
      }
    })
  }

  const previewText = value.trim()
    ? value
    : 'Select text above, tap an effect, and it shows up here.'

  const previewNode = (
    <div className="rb-fx-preview">
      <div className="rb-fx-preview-head">
        <span className="rb-fx-sec" style={{ margin: 0 }}>Live preview</span>
        {value.trim() !== stripFx(value) && (
          <button
            type="button"
            className="rb-fx-clear"
            title="Remove every effect, keep the text"
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => onChange(stripFx(value))}
          >
            Clear FX
          </button>
        )}
      </div>
      <div className="rb-fx-preview-body">
        <FxText text={previewText} />
      </div>
    </div>
  )

  return (
    <div className="rb-fxbar" ref={wrapRef}>
      <button
        type="button"
        className={`rb-fx-toggle${open ? ' rb-fx-toggle-open' : ''}`}
        onClick={toggle}
        onMouseDown={(e) => e.preventDefault()} // keep the textarea focus + selection alive
        aria-expanded={open}
        aria-haspopup="true"
        title="Open the text effects menu"
      >
        <FxIcon tag="glow" size={12} />
        FX Menu
        <span className="rb-fx-caret" aria-hidden="true">{open ? '▲' : '▼'}</span>
      </button>
      <span className="rb-fxbar-hint">Select text, then pick an effect — with nothing selected it styles the whole text. Stack as many as you like. Copy text that already has effects and the effects ride along.</span>

      {open && pos && (
        <div
          className="rb-fx-pop"
          role="menu"
          aria-label="Text effects"
          style={{ position: 'fixed', top: pos.top, left: pos.left, width: pos.width, maxWidth: 'calc(100vw - 24px)', maxHeight: pos.maxH, overflowY: 'auto', boxSizing: 'border-box' }}
        >
          <div className="rb-fx-sec">Animate</div>
          <div className="rb-fx-grid">
            {FX_LIST.filter((f) => f.group === 'fx').map((f) => (
              <button
                key={f.tag}
                type="button"
                className="rb-fxbtn"
                role="menuitem"
                title={`${f.hint} — wraps the selected text in [${f.tag}]…[/${f.tag}]`}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => apply(f.tag)}
              >
                <FxIcon tag={f.tag} />
                <span className="rb-fxbtn-label">
                  {/* the label wears its own effect — a live preview of the button */}
                  <FxText text={`[${f.tag}]${f.label}[/${f.tag}]`} />
                </span>
              </button>
            ))}
          </div>

          <div className="rb-fx-sec">Colors</div>
          <div className="rb-fx-grid">
            {FX_LIST.filter((f) => f.group === 'color').map((f) => (
              <button
                key={f.tag}
                type="button"
                className="rb-fxbtn"
                role="menuitem"
                title={`${f.hint} — wraps the selected text in [${f.tag}]…[/${f.tag}]`}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => apply(f.tag)}
              >
                <FxIcon tag={f.tag} />
                <span className="rb-fxbtn-label">
                  <FxText text={`[${f.tag}]${f.label}[/${f.tag}]`} />
                </span>
              </button>
            ))}
          </div>

          {previewNode}
        </div>
      )}

      {/* big always-visible preview: see the fx on your real text BEFORE publishing */}
      {livePreview && (
        <div className="rb-live-preview" style={{ width: '100%' }}>
          <div className="rb-live-preview-head">
            <FxIcon tag="glow" size={12} />
            Preview — exactly how it looks when published
            {value.trim() !== stripFx(value) && (
              <button
                type="button"
                className="rb-fx-clear"
                style={{ marginLeft: 'auto' }}
                onClick={() => onChange(stripFx(value))}
              >
                Clear FX
              </button>
            )}
          </div>
          <div className="rb-live-preview-body">
            <FxText text={value.trim() || 'Nothing yet — start typing and the preview follows.'} />
          </div>
        </div>
      )}
    </div>
  )
}
