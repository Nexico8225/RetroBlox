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
        border: '1px solid #ff6259',
        borderRadius: 8,
        padding: '10px 18px',
        background: 'linear-gradient(180deg,#3a1512,#2a0f0d)',
        color: '#ffd9d6',
        fontSize: 12,
        boxShadow: '0 8px 24px rgba(0,0,0,.5)',
        maxWidth: 'min(92vw, 520px)',
        textAlign: 'center',
      }}
    >
      {msg}
    </div>
  )
}

/* ---------- the classic outdoor stage ---------- */

function AuthStage({
  onSubmit,
  children,
}: {
  onSubmit: (e: React.FormEvent) => void
  children: React.ReactNode
}) {
  const narrow = useNarrow()
  return (
    <div
      style={{
        // flex:1 inside a full-height column wrapper — the form ALWAYS has
        // room: short screens scroll naturally instead of clipping, and on
        // tall screens the scene fills the viewport exactly (no phantom
        // scrollbar from the footnote strip)
        flex: 1,
        width: '100%',
        boxSizing: 'border-box',
        // the REAL RetroBlox world: the owner's roller-coaster render, full-bleed
        background: '#63b3ec url("/retro/auth-bg.jpg") center / cover no-repeat',
        position: 'relative',
        overflowX: 'hidden',
        display: 'flex',
        flexDirection: narrow ? 'column' : 'row',
        alignItems: 'center',
        justifyContent: 'center',
        gap: narrow ? 26 : 64,
        padding: narrow ? '40px 18px 56px' : '32px 48px 56px',
      }}
    >
      {/* ---------- LEFT: just the wordmark ---------- */}
      <div
        style={{
          position: 'relative',
          flex: narrow ? '0 0 auto' : '1 1 520px',
          width: narrow ? '100%' : undefined,
          maxWidth: 620,
          textAlign: narrow ? 'center' : 'left',
          zIndex: 2,
          display: 'flex',
          flexDirection: 'column',
          alignItems: narrow ? 'center' : 'flex-start',
        }}
      >
        <div style={{ position: 'relative', transform: 'rotate(-2deg)' }}>
          {/* white halo so the wordmark pops off the key art */}
          <div
            aria-hidden="true"
            style={{
              position: 'absolute',
              inset: '-30px -40px',
              background: 'radial-gradient(60% 70% at 45% 50%, rgba(255,255,255,.55), transparent 70%)',
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
            <RetroFontText text="RetroBlox" size={narrow ? 32 : 68} style={{ position: 'relative' }} />
          </div>
        </div>
      </div>

      {/* ---------- RIGHT: the classic white card ---------- */}
      <form
        onSubmit={onSubmit}
        style={{
          position: 'relative',
          zIndex: 2,
          flexShrink: 0,
          width: narrow ? '100%' : 400,
          maxWidth: 440,
          background: 'linear-gradient(180deg,#ffffff 0%,#f2f7fb 100%)',
          border: '3px solid #1e78c8',
          borderRadius: 12,
          boxShadow: '0 24px 54px rgba(16,52,86,.4), inset 0 0 0 2px rgba(255,255,255,.9)',
          overflow: 'hidden',
        }}
      >
        <div style={{ padding: narrow ? '22px 22px 26px' : '26px 30px 30px' }}>{children}</div>
      </form>
    </div>
  )
}

/* ---------- shared form controls (classic white card style) ---------- */

const LABEL: React.CSSProperties = {
  display: 'block',
  fontSize: 11,
  letterSpacing: 1.1,
  textTransform: 'uppercase',
  color: '#43505c',
  fontWeight: 700,
  marginBottom: 5,
}

const INPUT: React.CSSProperties = {
  width: '100%',
  boxSizing: 'border-box',
  background: '#ffffff',
  border: '1.5px solid #b9c6d0',
  borderRadius: 8,
  color: '#1c2733',
  fontSize: 14,
  padding: '10px 12px',
  outline: 'none',
  transition: 'border 120ms, box-shadow 120ms',
}

function inputFocus(e: React.FocusEvent<HTMLInputElement | HTMLSelectElement>) {
  e.currentTarget.style.borderColor = '#1e78c8'
  e.currentTarget.style.boxShadow = '0 0 0 3px rgba(30,120,200,.16)'
}
function inputBlur(e: React.FocusEvent<HTMLInputElement | HTMLSelectElement>) {
  e.currentTarget.style.borderColor = '#b9c6d0'
  e.currentTarget.style.boxShadow = 'none'
}

const RED_BUTTON: React.CSSProperties = {
  width: '100%',
  border: 'none',
  borderRadius: 8,
  color: '#fff',
  fontSize: 14.5,
  letterSpacing: 0.4,
  padding: '11px 0',
  background: 'linear-gradient(180deg,#f0392f 0%,#d21f16 55%,#b81b13 100%)',
  boxShadow: '0 5px 14px rgba(226,35,26,.35), inset 0 1px 0 rgba(255,255,255,.22)',
  textShadow: '0 1px 1px rgba(0,0,0,.3)',
  cursor: 'pointer',
  transition: 'filter 120ms, transform 80ms',
}

function ghostButton(): React.CSSProperties {
  return {
    width: '100%',
    display: 'block',
    textAlign: 'center',
    borderRadius: 8,
    fontSize: 13,
    fontWeight: 700,
    padding: '10px 0',
    background: '#eaf4fc',
    border: '1.5px solid #9cc6e8',
    color: '#1668a8',
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
          border: '1.5px solid #b9c6d0',
          borderRadius: 6,
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
          border: '1.5px solid #b9c6d0',
          borderRadius: 6,
          background: '#f2f6f9',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: 0,
        }}
      >
        <svg viewBox="0 0 24 24" width="17" height="17">
          <path
            d="M4 12a8 8 0 1 1 2.5 5.8M4 12v5h5"
            stroke="#5f7183"
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
        fontSize: 10.5,
        color: 'rgba(255,255,255,.92)',
        letterSpacing: 0.3,
        background: 'rgba(10,24,12,.55)',
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
      setError(
        err instanceof Error
          ? `${err.message} Check your spelling, or create a new account below.`
          : 'Login failed'
      )
      setBusy(false)
    }
  }

  return (
    <>
      <AuthError msg={error} />
      <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100dvh' }}>
      <AuthStage onSubmit={submit}>
        <h1 style={{ margin: '0 0 20px', fontSize: 19, color: '#1c3a52', letterSpacing: 0.2, fontWeight: 800 }}>
          Login and start having fun
        </h1>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
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
            className="rb-clickable"
            style={{ ...RED_BUTTON, opacity: busy ? 0.75 : 1 }}
            onMouseEnter={(e) => (e.currentTarget.style.filter = 'brightness(1.08)')}
            onMouseLeave={(e) => (e.currentTarget.style.filter = 'none')}
          >
            {busy ? 'Signing in...' : 'Log In'}
          </button>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '18px 0 12px' }}>
          <div style={{ flex: 1, height: 1, background: '#d7e1ea' }} />
          <span style={{ fontSize: 10.5, letterSpacing: 1.5, color: '#5f7183', textTransform: 'uppercase', fontWeight: 700 }}>New here?</span>
          <div style={{ flex: 1, height: 1, background: '#d7e1ea' }} />
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
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%235f7183' stroke-width='2' fill='none'/%3E%3C/svg%3E\")"

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
      <AuthStage onSubmit={submit}>
        <h1 style={{ margin: '0 0 18px', fontSize: 19, color: '#1c3a52', letterSpacing: 0.2, fontWeight: 800 }}>
          Sign up and start having fun
        </h1>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
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
                  color: gender === 'female' ? '#fff' : '#43505c',
                  background: gender === 'female' ? 'linear-gradient(180deg,#ff5fa8,#e0357f)' : '#f2f6f9',
                  border: gender === 'female' ? '1px solid #ff7fbb' : '1.5px solid #c3cfda',
                  boxShadow: gender === 'female' ? '0 0 0 3px rgba(255,79,168,.18)' : 'none',
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
                  color: gender === 'male' ? '#fff' : '#43505c',
                  background: gender === 'male' ? 'linear-gradient(180deg,#4f8ff0,#2f6fd0)' : '#f2f6f9',
                  border: gender === 'male' ? '1px solid #7fadf5' : '1.5px solid #c3cfda',
                  boxShadow: gender === 'male' ? '0 0 0 3px rgba(47,111,224,.2)' : 'none',
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
            className="rb-clickable"
            style={{ ...RED_BUTTON, opacity: busy ? 0.75 : 1, marginTop: 2 }}
            onMouseEnter={(e) => (e.currentTarget.style.filter = 'brightness(1.08)')}
            onMouseLeave={(e) => (e.currentTarget.style.filter = 'none')}
          >
            {busy ? 'Creating your account...' : 'Sign Up'}
          </button>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '16px 0 12px' }}>
          <div style={{ flex: 1, height: 1, background: '#d7e1ea' }} />
          <span style={{ fontSize: 10.5, letterSpacing: 1.5, color: '#5f7183', textTransform: 'uppercase', fontWeight: 700 }}>Already have an account?</span>
          <div style={{ flex: 1, height: 1, background: '#d7e1ea' }} />
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
