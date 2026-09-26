'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, saveAuthToken, type RetroUser } from '@/lib/store'
import { requestStorageAccessIfNeeded } from '@/lib/session'
import { RetroFontText } from '@/components/retro/RetroFontText'

/* ------------------------------------------------------------------
   Auth pages — classic layout over the REAL RetroBlox world render.
   - SCENE: the roller-coaster key art (public/retro/auth-bg.jpg),
     full-bleed cover. No fake CSS hills, no filler copy, no jokes.
   - LEFT: just the RetroBlox sprite-letter logo (the owner's font
     sheet, cropped to /retro/font/A..Z.png) — chunky shadow + bob.
   - RIGHT: the classic white card with the blue frame — username /
     password, red Log In button, plain labels.
   - Every input is a real, visible control. All behavior preserved:
     sign in -> /api/auth/login (+ /api/me check); sign up -> username
     + password + confirm + birthday + gender + captcha
   - preview-iframe safe via requestStorageAccessIfNeeded()
------------------------------------------------------------------ */

/* ---------- responsive helper ---------- */

function useNarrow(px = 940): boolean {
  const [narrow, setNarrow] = useState(false)
  useEffect(() => {
    const mq = window.matchMedia(`(max-width: ${px}px)`)
    const calc = () => setNarrow(mq.matches)
    calc()
    mq.addEventListener?.('change', calc)
    return () => mq.removeEventListener?.('change', calc)
  }, [px])
  return narrow
}

/* ---------- error banner ---------- */

function AuthError({ msg }: { msg: string }) {
  if (!msg) return null
  return (
    <div
      role="alert"
      style={{
        position: 'fixed',
        top: 14,
        left: '50%',
        transform: 'translateX(-50%)',
        zIndex: 60,
        border: '2px solid #e2a79f',
        borderLeft: '6px solid #e2231a',
        borderRadius: 10,
        padding: '12px 20px',
        background: '#fdf3f2',
        color: '#7a2c22',
        fontSize: 14,
        boxShadow: '0 10px 26px rgba(0, 0, 0,.35)',
        maxWidth: 'min(92vw, 560px)',
        textAlign: 'center',
      }}
    >
      {msg}
    </div>
  )
}

/* ---------- the PvZ-grade outdoor stage ----------
   ONE centered column: wordmark, big caps headline, card. The key art
   keeps the soul; a warm cream veil ties it into the new palette. */

function AuthStage({
  onSubmit,
  title,
  children,
}: {
  onSubmit: (e: React.FormEvent) => void
  title: string
  children: React.ReactNode
}) {
  const narrow = useNarrow()
  return (
    <div
      style={{
        flex: 1,
        width: '100%',
        boxSizing: 'border-box',
        // the REAL RetroBlox world: the owner's roller-coaster render, full-bleed
        background: '#63b3ec url("/retro/auth-bg.jpg") center / cover no-repeat',
        position: 'relative',
        overflowX: 'hidden',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: narrow ? 18 : 22,
        padding: narrow ? '34px 14px 48px' : '30px 40px 52px',
      }}
    >
      {/* warm cream veil so the whole scene sits in the new palette */}
      <div
        aria-hidden="true"
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'linear-gradient(180deg, rgba(246,239,220,.18) 0%, rgba(246,239,220,.05) 45%, rgba(56,43,26,.38) 100%)',
          pointerEvents: 'none',
        }}
      />

      {/* ---------- the wordmark — big, tight, bobbing ---------- */}
      <div
        style={{
          position: 'relative',
          zIndex: 2,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 10,
        }}
      >
        <div style={{ position: 'relative', transform: 'rotate(-2deg)' }}>
          {/* white halo so the wordmark pops off the key art */}
          <div
            aria-hidden="true"
            style={{
              position: 'absolute',
              inset: '-30px -40px',
              background: 'radial-gradient(60% 70% at 45% 50%, rgba(255,255,255,.5), transparent 70%)',
              filter: 'blur(8px)',
            }}
          />
          <div
            className="rb-auth-bob"
            style={{
              position: 'relative',
              filter: 'drop-shadow(0 4px 0 #a8231c) drop-shadow(0 10px 16px rgba(23,42,63,.4))',
            }}
          >
            <RetroFontText text="RetroBlox" size={narrow ? 36 : 88} style={{ position: 'relative' }} />
          </div>
        </div>
        <div
          className="rb-display"
          style={{
            color: '#fff',
            fontSize: narrow ? 13 : 15,
            letterSpacing: 4,
            textShadow: '0 2px 0 rgba(58,43,26,.75), 0 4px 10px rgba(23,42,63,.45)',
          }}
        >
          PLAY · CREATE · SHARE
        </div>
      </div>

      {/* ---------- the big friendly headline ---------- */}
      <h1
        className="rb-heavy"
        style={{
          position: 'relative',
          zIndex: 2,
          margin: 0,
          textAlign: 'center',
          textTransform: 'uppercase',
          fontSize: narrow ? 21 : 27,
          lineHeight: 1.2,
          color: '#fff',
          textShadow:
            '0 2px 0 #191919, 0 -1px 0 #191919, 2px 0 0 #191919, -2px 0 0 #191919, 0 5px 14px rgba(23,42,63,.5)',
        }}
      >
        {title}
      </h1>

      {/* ---------- the classic card, centered ---------- */}
      <form
        onSubmit={onSubmit}
        style={{
          position: 'relative',
          zIndex: 2,
          flexShrink: 0,
          width: narrow ? '100%' : 420,
          maxWidth: 440,
          background: '#ffffff',
          border: '2px solid #b6c0cb',
          borderBottom: '5px solid #b6c0cb',
          borderRadius: 16,
          boxShadow: '0 18px 44px rgba(23,42,63,.35), 0 2px 0 rgba(255,255,255,.65) inset',
          overflow: 'hidden',
        }}
      >
        <div style={{ padding: narrow ? '22px 22px 26px' : '26px 28px 30px' }}>{children}</div>
      </form>
    </div>
  )
}

/* ---------- shared form controls (classic white card style) ---------- */

const LABEL: React.CSSProperties = {
  display: 'block',
  fontSize: 12,
  letterSpacing: 1.1,
  textTransform: 'uppercase',
  color: '#68737f',
  fontWeight: 700,
  marginBottom: 6,
}

const INPUT: React.CSSProperties = {
  width: '100%',
  boxSizing: 'border-box',
  background: '#ffffff',
  border: '1.5px solid #b6c0cb',
  borderRadius: 10,
  color: '#191919',
  fontSize: 16,
  padding: '12px 14px',
  outline: 'none',
  transition: 'border 120ms, box-shadow 120ms',
}

function inputFocus(e: React.FocusEvent<HTMLInputElement | HTMLSelectElement>) {
  e.currentTarget.style.borderColor = '#0070b6'
  e.currentTarget.style.boxShadow = '0 0 0 3px rgba(0, 113, 188,.18)'
}
function inputBlur(e: React.FocusEvent<HTMLInputElement | HTMLSelectElement>) {
  e.currentTarget.style.borderColor = '#b6c0cb'
  e.currentTarget.style.boxShadow = 'none'
}

/* the big red CTA — flat, chunky, one dark bottom edge. Press it and it
   squashes (the .rb-auth-cta class does the squash, see globals.css) */
const RED_BUTTON: React.CSSProperties = {
  width: '100%',
  border: '2px solid #b81b13',
  borderBottomWidth: 5,
  borderRadius: 12,
  color: '#fff',
  fontSize: 17,
  letterSpacing: 0.4,
  padding: '13px 0',
  background: '#e2231a',
  boxShadow: 'none',
  textShadow: '0 1px 1px rgba(0,0,0,.3)',
  cursor: 'pointer',
  transition: 'filter 120ms, transform 60ms',
}

function ghostButton(): React.CSSProperties {
  return {
    width: '100%',
    display: 'block',
    textAlign: 'center',
    borderRadius: 10,
    fontSize: 14.5,
    fontWeight: 700,
    padding: '11px 0',
    background: '#ebedee',
    border: '1.5px solid #9aa5b1',
    borderBottomWidth: 3,
    color: '#2b2b2b',
    textDecoration: 'none',
    transition: 'background 120ms',
  }
}

/* ------------------------------------------------------------------
   Captcha — hand-drawn retro wobbly code on a canvas (unchanged art,
   restyled frame for the dark card).
------------------------------------------------------------------ */

const CAPTCHA_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'

function randomCaptchaCode(): string {
  let out = ''
  for (let i = 0; i < 5; i++) {
    out += CAPTCHA_CHARS.charAt(Math.floor(Math.random() * CAPTCHA_CHARS.length))
  }
  return out
}

function drawCaptcha(canvas: HTMLCanvasElement | null, code: string) {
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  const W = canvas.width
  const H = canvas.height
  ctx.clearRect(0, 0, W, H)

  // paper-ish background
  ctx.fillStyle = '#f5f3ea'
  ctx.fillRect(0, 0, W, H)

  // noise dots
  for (let i = 0; i < 90; i++) {
    ctx.fillStyle = ['#b8b2a0', '#8fa3b8', '#c9a5a0', '#a5c0a0'][i % 4]
    ctx.globalAlpha = 0.5
    ctx.fillRect(Math.random() * W, Math.random() * H, 2, 2)
  }
  ctx.globalAlpha = 1

  // squiggly lines through the text
  for (let l = 0; l < 3; l++) {
    ctx.strokeStyle = ['#2f7bc0', '#c86a28', '#4c9e34'][l]
    ctx.globalAlpha = 0.45
    ctx.lineWidth = 1.2
    ctx.beginPath()
    ctx.moveTo(0, H * (0.3 + l * 0.2) + Math.random() * 8 - 4)
    for (let x = 0; x <= W; x += 12) {
      ctx.lineTo(x, H * (0.3 + l * 0.2) + Math.sin(x / 14 + l * 2) * 7 + Math.random() * 4 - 2)
    }
    ctx.stroke()
  }
  ctx.globalAlpha = 1

  // the wobbly characters
  const colors = ['#1b4f7e', '#8a2a1d', '#2c5e24', '#5a3d7e']
  for (let i = 0; i < code.length; i++) {
    ctx.save()
    const cx = 16 + i * ((W - 30) / code.length) + 6
    const cy = H / 2 + (Math.random() * 10 - 5)
    ctx.translate(cx, cy)
    ctx.rotate((Math.random() - 0.5) * 0.7)
    ctx.font = `${22 + Math.floor(Math.random() * 8)}px Georgia, 'Times New Roman', serif`
    ctx.fillStyle = colors[i % colors.length]
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(code.charAt(i), 0, 0)
    ctx.restore()
  }
}

function CaptchaRow({ code, onRefresh }: { code: string; onRefresh: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    drawCaptcha(canvasRef.current, code)
  }, [code])
  return (
    <div style={{ display: 'flex', alignItems: 'stretch', gap: 8 }}>
      <canvas
        ref={canvasRef}
        width={150}
        height={46}
        aria-label="Captcha image"
        title="Type these letters below"
        style={{
          width: 150,
          height: 46,
          display: 'block',
          border: '1.5px solid #b6c0cb',
          borderRadius: 8,
        }}
      />
      <button
        type="button"
        onClick={onRefresh}
        title="New code"
        aria-label="New captcha code"
        className="rb-clickable"
        style={{
          width: 40,
          border: '1.5px solid #9aa5b1',
          borderBottomWidth: 3,
          borderRadius: 8,
          background: '#ebedee',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: 0,
        }}
      >
        <svg viewBox="0 0 24 24" width="17" height="17">
          <path
            d="M4 12a8 8 0 1 1 2.5 5.8M4 12v5h5"
            stroke="#68737f"
            strokeWidth="2.4"
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
          />
        </svg>
      </button>
    </div>
  )
}

/* ---------- tiny footer note under the card ---------- */

function AuthFootnote({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        marginTop: 0,
        textAlign: 'center',
        fontSize: 11.5,
        color: '#ebedee',
        letterSpacing: 0.3,
        background: 'rgba(44,33,21,.55)',
        padding: '10px 18px 12px',
        textShadow: '0 1px 2px rgba(0,0,0,.5)',
      }}
    >
      {children}
    </div>
  )
}

/* =========================== SIGN IN =========================== */

export function SignInView({ next }: { next?: string }) {
  const { setUser, setToast } = useRetro()
  const router = useRouter()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const goNext = () => {
    const target = next && next.startsWith('/') ? next : '/'
    router.push(target)
  }

  async function submit(e?: React.FormEvent) {
    e?.preventDefault()
    if (busy) return
    setError('')
    if (!username.trim() || !password) {
      setError('Write your username and password first!')
      return
    }
    setBusy(true)
    try {
      // if we are inside the preview iframe, ask for first-party storage
      // access NOW (user gesture) so the session cookie can actually stick
      await requestStorageAccessIfNeeded()
      const res = await api<{ user: RetroUser; token?: string }>('/api/auth/login', {
        method: 'POST',
        body: JSON.stringify({ username: username.trim(), password }),
      })
      saveAuthToken(res.token)
      setUser(res.user)
      setToast(null)
      // double-check the session really stuck before navigating
      try {
        const me = await api<{ user: RetroUser | null }>('/api/me')
        if (me.user) setUser(me.user)
      } catch {
        /* the Bearer token still authenticates every call — carry on */
      }
      goNext()
    } catch (err) {
      // the server's message is already specific ("No account named X",
      // "Wrong password", "database unreachable"). Only add the spelling
      // hint when it is actually about the account itself.
      const msg = err instanceof Error ? err.message : 'Login failed'
      const aboutTheAccount = /No account|Wrong password|Invalid/i.test(msg)
      setError(aboutTheAccount ? `${msg} Check your spelling, or create a new account below.` : msg)
      setBusy(false)
    }
  }

  return (
    <>
      <AuthError msg={error} />
      <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100dvh' }}>
      <AuthStage onSubmit={submit} title="Login and start having fun">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 15 }}>
          <div>
            <label style={LABEL} htmlFor="si-username">Username</label>
            <input
              id="si-username"
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
              autoFocus
              maxLength={20}
              placeholder="e.g. Nexico8225"
              style={INPUT}
              onFocus={inputFocus}
              onBlur={inputBlur}
            />
          </div>

          <div>
            <label style={LABEL} htmlFor="si-password">Password</label>
            <input
              id="si-password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              placeholder="••••••••"
              style={INPUT}
              onFocus={inputFocus}
              onBlur={inputBlur}
            />
          </div>

          <button
            type="submit"
            disabled={busy}
            className="rb-clickable rb-auth-cta"
            style={{ ...RED_BUTTON, opacity: busy ? 0.75 : 1 }}
            onMouseEnter={(e) => (e.currentTarget.style.filter = 'brightness(1.08)')}
            onMouseLeave={(e) => (e.currentTarget.style.filter = 'none')}
          >
            {busy ? 'Signing in...' : 'Log In'}
          </button>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '18px 0 12px' }}>
          <div style={{ flex: 1, height: 1.5, background: '#dde3ea' }} />
          <span style={{ fontSize: 11.5, letterSpacing: 1.5, color: '#68737f', textTransform: 'uppercase', fontWeight: 700 }}>New here?</span>
          <div style={{ flex: 1, height: 1.5, background: '#dde3ea' }} />
        </div>

        <Link href="/signup" style={ghostButton()}>
          Create a free account
        </Link>
      </AuthStage>
      <AuthFootnote>© RetroBlox</AuthFootnote>
      </div>
    </>
  )
}

/* =========================== SIGN UP =========================== */

const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

const CHEVRON_URL =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%236b5a3d' stroke-width='2' fill='none'/%3E%3C/svg%3E\")"

function selectStyle(): React.CSSProperties {
  return {
    ...INPUT,
    appearance: 'none',
    WebkitAppearance: 'none' as const,
    background: `#ffffff ${CHEVRON_URL} no-repeat right 10px center`,
    paddingRight: 28,
  }
}

export function SignUpView({ next }: { next?: string }) {
  const { setUser } = useRetro()
  const router = useRouter()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [month, setMonth] = useState('')
  const [day, setDay] = useState('')
  const [year, setYear] = useState('')
  const [gender, setGender] = useState<'male' | 'female' | ''>('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [captchaCode, setCaptchaCode] = useState(() => randomCaptchaCode())
  const [captchaInput, setCaptchaInput] = useState('')

  const refreshCaptcha = useCallback(() => {
    setCaptchaCode(randomCaptchaCode())
    setCaptchaInput('')
  }, [])

  async function submit(e?: React.FormEvent) {
    e?.preventDefault()
    if (busy) return
    setError('')
    if (!username.trim() || !password) {
      setError('Write your username and password first!')
      return
    }
    if (password.length < 3) {
      setError('Password must be at least 3 characters.')
      return
    }
    if (password !== confirm) {
      setError('Passwords do not match!')
      return
    }
    if (!month || !day || !year) {
      setError('Please set your full birthday!')
      return
    }
    if (captchaInput.trim().toUpperCase() !== captchaCode) {
      setError('The captcha code does not match — try the new one!')
      refreshCaptcha()
      return
    }
    const birthday = `${year}-${month}-${day.padStart(2, '0')}`
    setBusy(true)
    try {
      // preview-iframe safe: ask for storage access inside the user gesture
      await requestStorageAccessIfNeeded()
      const fd = new FormData()
      fd.append('username', username.trim())
      fd.append('password', password)
      fd.append('gender', gender || '')
      fd.append('birthday', birthday)
      // no profile picture here — you never need a pfp to use RetroBlox;
      // a letter avatar stands in until you add one from your profile

      const res = await api<{ user: RetroUser; token?: string }>('/api/auth/signup', { method: 'POST', body: fd })
      saveAuthToken(res.token)
      setUser(res.user)
      // confirm the fresh session actually sticks before we celebrate
      try {
        const me = await api<{ user: RetroUser | null }>('/api/me')
        if (me.user) setUser(me.user)
      } catch {
        /* Bearer token still authenticates every call */
      }
      router.push(next && next.startsWith('/') ? next : '/')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign up failed')
      setBusy(false)
    }
  }

  const days = month === '2' ? 29 : month === '4' || month === '6' || month === '9' || month === '11' ? 30 : 31

  return (
    <>
      <AuthError msg={error} />
      <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100dvh' }}>
      <AuthStage onSubmit={submit} title="Sign up and start having fun">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 13 }}>
          <div>
            <label style={LABEL} htmlFor="su-username">Username</label>
            <input
              id="su-username"
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
              autoFocus
              maxLength={20}
              placeholder="3-20 letters, numbers, _"
              style={INPUT}
              onFocus={inputFocus}
              onBlur={inputBlur}
            />
          </div>

          <div style={{ display: 'flex', gap: 10 }}>
            <div style={{ flex: 1 }}>
              <label style={LABEL} htmlFor="su-password">Password</label>
              <input
                id="su-password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="new-password"
                placeholder="Pick any password"
                style={INPUT}
                onFocus={inputFocus}
                onBlur={inputBlur}
              />
            </div>
            <div style={{ flex: 1 }}>
              <label style={LABEL} htmlFor="su-confirm">Confirm</label>
              <input
                id="su-confirm"
                type="password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                autoComplete="new-password"
                placeholder="Again"
                style={INPUT}
                onFocus={inputFocus}
                onBlur={inputBlur}
              />
            </div>
          </div>

          <div>
            <label style={LABEL} htmlFor="su-month">Birthday</label>
            <div style={{ display: 'flex', gap: 8 }}>
              <select
                id="su-month"
                value={month}
                onChange={(e) => setMonth(e.target.value)}
                aria-label="Birth month"
                style={{ ...selectStyle(), flex: 1.6 }}
                onFocus={inputFocus}
                onBlur={inputBlur}
              >
                <option value="">Month</option>
                {MONTHS.map((m, i) => (
                  <option key={m} value={String(i + 1).padStart(2, '0')}>{m}</option>
                ))}
              </select>
              <select
                value={day}
                onChange={(e) => setDay(e.target.value)}
                aria-label="Birth day"
                style={{ ...selectStyle(), flex: 1 }}
                onFocus={inputFocus}
                onBlur={inputBlur}
              >
                <option value="">Day</option>
                {Array.from({ length: days }, (_, i) => (
                  <option key={i + 1} value={String(i + 1)}>{String(i + 1)}</option>
                ))}
              </select>
              <select
                value={year}
                onChange={(e) => setYear(e.target.value)}
                aria-label="Birth year"
                style={{ ...selectStyle(), flex: 1.2 }}
                onFocus={inputFocus}
                onBlur={inputBlur}
              >
                <option value="">Year</option>
                {Array.from({ length: 100 }, (_, i) => {
                  const y = 2012 - i
                  return <option key={y} value={String(y)}>{String(y)}</option>
                })}
              </select>
            </div>
          </div>

          <div>
            <span style={LABEL}>Gender <span style={{ textTransform: 'none', letterSpacing: 0 }}>(optional)</span></span>
            <div style={{ display: 'flex', gap: 8 }}>
              <button
                type="button"
                onClick={() => setGender(gender === 'female' ? '' : 'female')}
                aria-pressed={gender === 'female'}
                aria-label="Female"
                className="rb-clickable"
                style={{
                  flex: 1,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 7,
                  padding: '9px 0',
                  borderRadius: 8,
                  fontSize: 12.5,
                  fontWeight: 600,
                  color: gender === 'female' ? '#8c2b5e' : '#68737f',
                  background: gender === 'female' ? '#ffb1d4' : '#ebedee',
                  border: gender === 'female' ? '2px solid #d5649f' : '1.5px solid #b6c0cb',
                  boxShadow: gender === 'female' ? '0 0 0 3px rgba(255,111,168,.22)' : 'none',
                  transition: 'background 140ms, border 140ms, box-shadow 140ms',
                }}
              >
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <circle cx="12" cy="7" r="4" />
                  <path d="M12 11v9M8 20h8M9.5 14.5h5" />
                </svg>
                Female
              </button>
              <button
                type="button"
                onClick={() => setGender(gender === 'male' ? '' : 'male')}
                aria-pressed={gender === 'male'}
                aria-label="Male"
                className="rb-clickable"
                style={{
                  flex: 1,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 7,
                  padding: '9px 0',
                  borderRadius: 8,
                  fontSize: 12.5,
                  fontWeight: 600,
                  color: gender === 'male' ? '#1c4e9e' : '#68737f',
                  background: gender === 'male' ? '#a9c8f5' : '#ebedee',
                  border: gender === 'male' ? '2px solid #4a72c0' : '1.5px solid #b6c0cb',
                  boxShadow: gender === 'male' ? '0 0 0 3px rgba(74,114,192,.22)' : 'none',
                  transition: 'background 140ms, border 140ms, box-shadow 140ms',
                }}
              >
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <circle cx="10" cy="14" r="5" />
                  <path d="M14 10l6-6M15 4h5v5" />
                </svg>
                Male
              </button>
            </div>
          </div>

          <div>
            <span style={LABEL}>Captcha — prove you are human</span>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <CaptchaRow code={captchaCode} onRefresh={refreshCaptcha} />
              <input
                type="text"
                value={captchaInput}
                onChange={(e) => setCaptchaInput(e.target.value)}
                aria-label="Captcha code"
                maxLength={6}
                autoComplete="off"
                spellCheck={false}
                placeholder="Type the code"
                style={INPUT}
                onFocus={inputFocus}
                onBlur={inputBlur}
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={busy}
            className="rb-clickable rb-auth-cta"
            style={{ ...RED_BUTTON, opacity: busy ? 0.75 : 1, marginTop: 2 }}
            onMouseEnter={(e) => (e.currentTarget.style.filter = 'brightness(1.08)')}
            onMouseLeave={(e) => (e.currentTarget.style.filter = 'none')}
          >
            {busy ? 'Creating your account...' : 'Sign Up'}
          </button>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '16px 0 12px' }}>
          <div style={{ flex: 1, height: 1.5, background: '#dde3ea' }} />
          <span style={{ fontSize: 11.5, letterSpacing: 1.5, color: '#68737f', textTransform: 'uppercase', fontWeight: 700 }}>Already have an account?</span>
          <div style={{ flex: 1, height: 1.5, background: '#dde3ea' }} />
        </div>

        <Link href="/login" style={ghostButton()}>
          Log in instead
        </Link>
      </AuthStage>
      <AuthFootnote>© RetroBlox</AuthFootnote>
      </div>
    </>
  )
}
