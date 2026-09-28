'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useRetro, api, letterAvatar, clearAuthToken, timeAgo, type RetroUser } from '@/lib/store'
import { tixCompact } from '@/lib/tix'
import { eggLogoClick } from '@/lib/eggs'
import { RetroFontText } from '@/components/retro/RetroFontText'

/* Avatar with letter fallback (Google-style first letter when no photo) */
export function Avatar({
  user,
  size = 40,
  rounded = 6,
}: {
  user: { username: string; avatarUrl?: string | null }
  size?: number
  rounded?: number | string
}) {
  const [err, setErr] = useState(false)
  const src = !user.avatarUrl || err ? letterAvatar(user.username) : user.avatarUrl
  return (
    <img
      src={src}
      alt={`${user.username}'s avatar`}
      width={size}
      height={size}
      onError={() => setErr(true)}
      style={{
        width: size,
        height: size,
        borderRadius: rounded,
        border: '1px solid #8ba0b3',
        background: '#dde5ec',
        objectFit: 'cover',
        flexShrink: 0,
      }}
    />
  )
}

/* Small game icon with fallback */
export function GameIcon({ src, name, size = 90 }: { src?: string | null; name: string; size?: number }) {
  const [err, setErr] = useState(false)
  const fallback = `data:image/svg+xml;utf8,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="150" height="150"><rect width="150" height="150" fill="#7c8ea0"/><text x="75" y="90" text-anchor="middle" font-family="Verdana" font-size="70" fill="#fff">${name.replace(/[^A-Za-z0-9]/g, '').charAt(0).toUpperCase() || 'G'}</text></svg>`
  )}`
  return (
    <img
      src={err || !src ? fallback : src}
      alt={name}
      onError={() => setErr(true)}
      style={{
        width: size,
        height: size,
        objectFit: 'cover',
        border: '1px solid #8ba0b3',
        background: '#dde5ec',
        flexShrink: 0,
      }}
    />
  )
}

export function OnlineDot({ online }: { online: boolean }) {
  return <span className={online ? 'rb-online-dot' : 'rb-offline-dot'} title={online ? 'Online now' : 'Offline'} />
}

/* ---------------- Notifications bell ---------------- */

interface NotifRow {
  id: string
  type: string
  title: string
  body: string
  linkUrl: string | null
  createdAt: string
  read: boolean
  actor: { id: string; username: string; avatarUrl: string | null } | null
}

function NotifIcon({ type }: { type: string }) {
  const common = { width: 20, height: 20, viewBox: '0 0 20 20', 'aria-hidden': true } as const
  if (type === 'new_player') {
    // shiny new blockhead walked in
    return (
      <svg {...common}>
        <circle cx="8" cy="6" r="3" fill="#2c6e31" />
        <path d="M2 17c0-3.4 2.7-5.4 6-5.4s6 2 6 5.4z" fill="#2c6e31" />
        <path d="M14.5 5.5v5M12 8h5" stroke="#ffd34e" strokeWidth="2" strokeLinecap="round" />
      </svg>
    )
  }
  if (type === 'friend_accepted') {
    return (
      <svg {...common}>
        <circle cx="10" cy="10" r="8" fill="#4c9e34" />
        <path d="M6 10.2 9 13l5-5.6" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    )
  }
  // friend_request
  return (
    <svg {...common}>
      <circle cx="7.5" cy="6.5" r="2.8" fill="#b8860b" />
      <path d="M2 16.5c0-3 2.4-4.8 5.5-4.8s5.5 1.8 5.5 4.8z" fill="#b8860b" />
      <path d="M14.5 6.5v5M12 9h5" stroke="#0d69ac" strokeWidth="2" strokeLinecap="round" />
    </svg>
  )
}

function NotificationsBell() {
  const { unreadNotifications, setUnreadNotifications } = useRetro()
  const router = useRouter()
  const pathname = usePathname()
  // derived: only open for the pathname it was opened on — navigating
  // anywhere closes it automatically (same pattern as MobileDrawer)
  const [openPath, setOpenPath] = useState<string | null>(null)
  const open = openPath !== null && openPath === pathname
  const close = () => setOpenPath(null)
  const [rows, setRows] = useState<NotifRow[]>([])
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpenPath(null)
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open])

  async function toggle() {
    const next = !open
    setOpenPath(next ? pathname : null)
    if (!next) return
    try {
      const res = await api<{ notifications: NotifRow[] }>('/api/notifications')
      setRows(res.notifications)
      setLoaded(true)
      if ((res.notifications || []).some((n) => !n.read)) {
        // clear the badge, keep the fetched flags for the highlight
        await api('/api/notifications', { method: 'POST', body: JSON.stringify({ action: 'read-all' }) })
      }
      setUnreadNotifications(0)
    } catch {
      setLoaded(true)
    }
  }

  return (
    <span style={{ position: 'relative', display: 'inline-flex' }}>
      <button
        type="button"
        onClick={toggle}
        title="Notifications"
        aria-label={`Notifications${unreadNotifications ? ` (${unreadNotifications} unread)` : ''}`}
        aria-expanded={open}
        style={{ position: 'relative', display: 'inline-flex', padding: 6, background: 'none', border: 'none', cursor: 'pointer' }}
      >
        <BellIcon />
        {unreadNotifications > 0 && (
          <span className="rb-badge" style={{ position: 'absolute', top: -4, right: -7 }}>{unreadNotifications}</span>
        )}
      </button>

      {open && <div style={{ position: 'fixed', inset: 0, zIndex: 58 }} onClick={close} aria-hidden="true" />}

      {open && (
        <div
          className="rb-box"
          role="dialog"
          aria-label="Notifications"
          style={{
            position: 'absolute',
            top: 'calc(100% + 6px)',
            right: 0,
            width: 320,
            maxWidth: 'calc(100vw - 24px)',
            maxHeight: 400,
            overflowY: 'auto',
            zIndex: 59,
            boxShadow: '0 6px 18px rgba(9,32,52,.35)',
          }}
        >
          <div className="rb-panel-head" style={{ position: 'sticky', top: 0 }}>
            <span>Notifications</span>
            <Link
              className="rb-link"
              style={{ fontSize: 10 }}
              href="/people"
              onClick={close}
            >
              Find People &rarr;
            </Link>
          </div>
          {!loaded && <div style={{ padding: 18, textAlign: 'center', fontSize: 11, color: '#5a6b7b' }}>Loading...</div>}
          {loaded && rows.length === 0 && (
            <div style={{ padding: 18, textAlign: 'center', fontSize: 11, color: '#5a6b7b', lineHeight: 1.6 }}>
              Nothing yet! When someone joins RetroBlox or<br />sends you a friend request, it shows up here.
            </div>
          )}
          {loaded &&
            rows.map((n) => (
              <button
                key={n.id}
                type="button"
                onClick={() => {
                  close()
                  if (n.linkUrl) router.push(n.linkUrl)
                }}
                style={{
                  display: 'flex',
                  gap: 8,
                  width: '100%',
                  textAlign: 'left',
                  alignItems: 'flex-start',
                  padding: '8px 10px',
                  background: n.read ? 'transparent' : '#e1f2fb',
                  border: 'none',
                  borderBottom: '1px solid #eef2f6',
                  cursor: 'pointer',
                }}
              >
                <NotifIcon type={n.type} />
                <span style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ display: 'block', fontSize: 11, color: '#24425f', fontWeight: n.read ? 400 : 700 }}>{n.title}</span>
                  {n.body && <span style={{ display: 'block', fontSize: 10, color: '#5a6b7b', marginTop: 1 }}>{n.body}</span>}
                  <span style={{ display: 'block', fontSize: 9, color: '#8ba0b3', marginTop: 2 }}>{timeAgo(n.createdAt)}</span>
                </span>
              </button>
            ))}
        </div>
      )}
    </span>
  )
}

function BellIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 22 22" aria-hidden="true">
      <path
        d="M11 2.2a1.6 1.6 0 0 1 1.6 1.6v.5c2.9.7 4.9 3 4.9 6.2v3.2l1.6 2.4c.3.5 0 1.2-.7 1.2H3.6c-.7 0-1-.7-.7-1.2l1.6-2.4v-3.2c0-3.2 2-5.5 4.9-6.2v-.5A1.6 1.6 0 0 1 11 2.2z"
        fill="#e8eef4"
        stroke="#0d3054"
        strokeWidth="1.3"
      />
      <path d="M8.8 18.6a2.3 2.3 0 0 0 4.4 0z" fill="#e8eef4" stroke="#0d3054" strokeWidth="1.2" />
    </svg>
  )
}

/* ---------------- Header ---------------- */

const NAV = [
  { label: 'Home', href: '/' },
  { label: 'Games', href: '/games' },
  { label: 'Catalog', href: '/catalog' },
  { label: 'Avatar', href: '/avatar' },
  { label: 'Groups', href: '/groups' },
  { label: 'Music', href: '/music' },
  { label: 'RetroLabs', href: '/labs' },
  { label: 'Communities', href: '/community' },
  { label: 'Create', href: '/create' },
  { label: 'My Games', href: '/my' },
]

export function Header() {
  const { user, pendingRequests, unreadChats, unreadNotifications, setPendingRequests, setUnreadChats, setUnreadNotifications, setToast } = useRetro()
  const router = useRouter()
  const pathname = usePathname()
  const [q, setQ] = useState('')

  useEffect(() => {
    // refresh pending friend-request + chat badges + the Tix wallet chip occasionally
    const tick = async () => {
      try {
        const res = await api<{ pendingFriendRequests: number; unreadChats: number; unreadNotifications?: number; user: { rbxBalance?: number } | null }>('/api/me')
        setPendingRequests(res.pendingFriendRequests || 0)
        setUnreadChats(res.unreadChats || 0)
        setUnreadNotifications(res.unreadNotifications || 0)
        const u = useRetro.getState().user
        if (u && res.user) useRetro.getState().setUser({ ...u, rbxBalance: res.user.rbxBalance ?? 0 })
      } catch { /* ignore */ }
    }
    tick()
    const t = setInterval(tick, 30000)
    return () => clearInterval(t)
  }, [setPendingRequests, setUnreadChats, setUnreadNotifications])

  function search(e: React.FormEvent) {
    e.preventDefault()
    router.push(q.trim() ? `/games?q=${encodeURIComponent(q.trim())}` : '/games')
    setQ('')
  }

  return (
    <header className="rb-header">
      <div className="rb-header-inner">
        {/* Mobile: burger menu + slide-in drawer (all the pages the tab bar can't fit) */}
        <MobileDrawer />

        {/* Logo — the wordmark is the user's own cropped font sheet (branding only) */}
        <Link href="/" aria-label="RetroBlox home" onClick={eggLogoClick} style={{ display: 'flex', alignItems: 'center', gap: 8, textDecoration: 'none' }}>
          <span
            className="rb-logo-chip"
            style={{
              display: 'inline-flex',
              padding: 3,
              background: 'linear-gradient(180deg,#fff,#dbe4ec)',
              border: '1px solid #005f9c',
              borderRadius: 4,
              boxShadow: 'inset 1px 1px 0 #fff',
            }}
          >
            <img src="/retro/logo.png" alt="RetroBlox logo" width={34} height={34} style={{ display: 'block' }} />
          </span>
          <span className="rb-brand-desktop">
            <RetroFontText text="RetroBlox" size={21} style={{ filter: 'drop-shadow(0 2px 2px rgba(0,0,0,.45))' }} />
          </span>
        </Link>

        {/* Search — the blue bar now only carries logo + search + account,
            exactly like the old site, so the search finally has room to
            breathe (the nav links live in the white strip below). */}
        <form onSubmit={search} className="rb-header-search" style={{ display: 'flex', flex: 1, minWidth: 150, maxWidth: 560, marginLeft: 10 }}>
          <input
            className="rb-input"
            type="search"
            placeholder="Search games..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            style={{ flex: 1, minWidth: 0, borderRadius: '3px 0 0 3px', fontSize: 12.5, height: 30 }}
            aria-label="Search games"
          />
          <button className="rb-btn" type="submit" style={{ borderRadius: '0 3px 3px 0', borderLeft: 'none', height: 30 }}>
            Go
          </button>
        </form>

        {/* Right side — guests get Log In + Sign Up (logo LEFT, Sign Up RIGHT);
            members get the wallet chip, chat and profile actions */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginLeft: 'auto' }}>
          {user ? (
            <>
              <Link
                href="/store"
                title="Tix Store — top up your wallet"
                className="rb-header-chip rb-wallet-chip"
                style={{
                  display: 'flex', alignItems: 'center', gap: 5,
                  background: 'transparent',
                  border: 'none',
                  borderRadius: 3,
                  padding: '3px 8px',
                  color: '#fff',
                  textDecoration: 'none',
                  fontSize: 12,
                  textShadow: '0 1px 1px rgba(0,0,0,.3)',
                }}
              >
                {/* classic gold ticket — the 2016 bar showed your money flat on blue */}
                <svg
                  viewBox="0 0 24 24"
                  width="15"
                  height="15"
                  aria-hidden="true"
                  style={{ flexShrink: 0, filter: 'drop-shadow(0 1px 1px rgba(0,0,0,.45))' }}
                >
                  <path
                    d="M3 9V6a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v3a2.5 2.5 0 0 0 0 6v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-3a2.5 2.5 0 0 0 0-6z"
                    fill="#ffd34e"
                    stroke="#8a6d1a"
                    strokeWidth="1.2"
                  />
                  <path d="M15.5 6v2M15.5 10.5v2M15.5 15v2" stroke="#8a6d1a" strokeWidth="1.4" strokeDasharray="2.4 2.2" fill="none" />
                </svg>
                <span style={{ fontFamily: 'monospace' }}>{tixCompact(user.rbxBalance ?? 0)}</span>
                <span className="rb-wallet-buy" style={{ fontSize: 10, color: '#cfe8f8' }}>+ Buy</span>
              </Link>

              <NotificationsBell />

              <Link
                href="/chat"
                title="Chat with friends"
                aria-label="Chat"
                className="rb-header-chat"
                style={{ position: 'relative', display: 'inline-flex', padding: 6 }}
              >
                <ChatIcon />
                {unreadChats > 0 && (
                  <span className="rb-badge" style={{ position: 'absolute', top: -4, right: -7 }}>{unreadChats}</span>
                )}
              </Link>

              <Link
                href={`/users/${user.id}`}
                className="rb-header-chip"
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 6,
                  background: 'rgba(255,255,255,.12)',
                  border: '1px solid rgba(255,255,255,.35)',
                  borderRadius: 3,
                  padding: '3px 8px 3px 4px',
                  color: '#fff',
                  textDecoration: 'none',
                  fontSize: 11,
                }}
                title="My Profile"
              >
                <Avatar user={user as RetroUser} size={24} rounded={3} />
                <span
                  className="rb-chip-name"
                  style={{
                    maxWidth: 110,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {user.username}
                </span>
                {user.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
              </Link>
            </>
          ) : (
            <>
              <Link href="/login" className="rb-btn" style={{ textDecoration: 'none' }}>
                Log In
              </Link>
              <Link href="/signup" className="rb-btn rb-btn-blue" style={{ textDecoration: 'none' }}>
                Sign Up
              </Link>
            </>
          )}
        </div>
      </div>

      {/* The classic white nav strip — the old site's second header row.
          All the page links live here so the blue bar stays clean. */}
      <nav className="rb-navbar" aria-label="Site sections">
        <div className="rb-navbar-inner">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              className={`rb-navbar-item${pathname === n.href ? ' rb-navbar-active' : ''}`}
            >
              {n.label}
            </Link>
          ))}
        </div>
      </nav>
    </header>
  )
}

function ChatIcon() {
  return (
    <svg width="22" height="18" viewBox="0 0 22 18" aria-hidden="true">
      <rect x="1" y="1.5" width="16" height="11" rx="3" fill="#e8eef4" stroke="#0d3054" strokeWidth="1.3" />
      <path d="M5 12.5v4l4.5-4" fill="#e8eef4" stroke="#0d3054" strokeWidth="1.3" strokeLinejoin="round" />
      <circle cx="6" cy="7" r="1.2" fill="#2a6cad" />
      <circle cx="9.5" cy="7" r="1.2" fill="#2a6cad" />
      <circle cx="13" cy="7" r="1.2" fill="#2a6cad" />
      <circle cx="18.5" cy="13" r="2.6" fill="#cfe0ef" stroke="#0d3054" strokeWidth="1.2" />
    </svg>
  )
}

/* ---------------- Sidebar ---------------- */

function SiteStatsBox() {
  const [stats, setStats] = useState<{ games: number; users: number; downloads: number; groups: number; labs: number; community: number; videos: number } | null>(null)
  useEffect(() => {
    api<{ games: number; users: number; downloads: number; groups: number; labs: number; community: number; videos: number }>('/api/stats')
      .then(setStats)
      .catch(() => {})
  }, [])
  const row = (k: string, v: number | undefined) => (
    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, padding: '2px 0' }}>
      <span style={{ color: '#5a6b7b' }}>{k}</span>
      <span style={{ color: '#24425f' }}>{v === undefined ? '...' : v.toLocaleString('en-US')}</span>
    </div>
  )
  return (
    <div className="rb-box" style={{ overflow: 'hidden', marginBottom: 10 }}>
      <div className="rb-panel-head"><span>RetroBlox Stats</span></div>
      <div style={{ padding: 8 }}>
        {row('Games published', stats?.games)}
        {row('Videos uploaded', stats?.videos)}
        {row('Blockheads', stats?.users)}
        {row('Downloads', stats?.downloads)}
        {row('Groups', stats?.groups)}
        {row('Labs posts', stats?.labs)}
        {row('Community posts', stats?.community)}
      </div>
    </div>
  )
}

export function Sidebar() {
  const { user, pendingRequests, unreadChats, setUser, setPendingRequests, setUnreadChats, setToast } = useRetro()
  const router = useRouter()
  const pathname = usePathname()
  if (!user) return null

  async function logout() {
    try {
      await api('/api/auth/logout', { method: 'POST' })
    } catch { /* ignore */ }
    clearAuthToken()
    setUser(null)
    setPendingRequests(0)
    setUnreadChats(0)
    setToast(null)
    router.push('/login')
  }

  const item = (label: string, href: string, badge?: number) => {
    const active = pathname === href
    return (
      <Link
        key={href}
        href={href}
        className="rb-side-item"
        style={{
          background: active ? '#e1f2fb' : 'transparent',
          color: active ? '#00639e' : '#1c4e7c',
        }}
      >
        <span>{label}</span>
        {badge ? <span className="rb-badge">{badge}</span> : null}
      </Link>
    )
  }

  // little uppercase group headers that organize the sidebar
  const sec = (label: string) => <div className="rb-side-sec">{label}</div>

  return (
    <aside className="rb-sidebar" style={{ width: 200, flexShrink: 0 }}>
      {/* user card — this is the profile tab: profile, friends, chat and log out live here */}
      <div className="rb-box" style={{ marginBottom: 10, overflow: 'hidden' }}>
        <div style={{ padding: 10, display: 'flex', alignItems: 'center', gap: 8, background: 'linear-gradient(180deg,#eef4fa,#dbe6f0)' }}>
          <Avatar user={user} size={44} />
          <div>
            <Link href={`/users/${user.id}`} className="rb-link" style={{ fontSize: 12, display: 'block' }}>
              {user.username}
            </Link>
            {user.role === 'admin' && (
              <div style={{ marginTop: 2 }}>
                <span className="rb-admin-badge">ADMIN</span>
              </div>
            )}
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10, color: '#5a6b7b' }}>
              <OnlineDot online={user.online} /> {user.online ? 'Online' : 'Offline'}
            </span>
          </div>
        </div>
        {/* SIDEBAR = the organized hub. Grouped sections, most-used first.
            When the first real GAME arrives from the game AI, its "Play Now"
            tab goes at the TOP of the Play section below. */}
        {sec('Play')}
        {item('Discover', '/games')}
        {item('Favorites', '/favorites')}

        {sec('Create')}
        {item('My Games', '/my')}
        {item('Create a Game', '/create')}
        {item('RetroLabs', '/labs')}
        {item('Player System', '/sdk')}

        {sec('Avatar & Shop')}
        {item('Avatar Editor', '/avatar')}
        {item('Catalog', '/catalog')}
        {item('Tix Store', '/store')}

        {sec('Social')}
        {item('My Profile', `/users/${user.id}`)}
        {item('People', '/people')}
        {item('Friends', '/friends', pendingRequests || undefined)}
        {item('Chat', '/chat', unreadChats || undefined)}
        {item('Groups', '/groups')}
        {item('Communities', '/community')}
        {item('Videos', '/videos')}
        {item('Music', '/music')}

        {sec('Account')}
        {user.role === 'admin' && item('Admin Panel', '/admin')}
        {item('Settings', '/settings')}
        <div style={{ padding: '8px 10px', borderTop: '1px solid #e4eaf0' }}>
          <button className="rb-btn rb-btn-red" style={{ width: '100%', fontSize: 11 }} onClick={logout}>
            Log Out
          </button>
        </div>
      </div>

      <SiteStatsBox />
    </aside>
  )
}

/* ---------------- Mobile bottom tab bar ---------------- */

function TabHome() {
  return (
    <svg width="21" height="21" viewBox="0 0 22 22" aria-hidden="true">
      <path
        d="M11 2.6 1.8 10.8h2.7V19h5v-5.2h3V19h5v-8.2h2.7z"
        fill="currentColor"
      />
    </svg>
  )
}

function TabGames() {
  return (
    <svg width="21" height="21" viewBox="0 0 22 22" aria-hidden="true">
      <path
        fillRule="evenodd"
        d="M5.2 2.6 19.4 6.3 15.7 20.5 1.5 16.8Zm4.6 6.1-.9 3.4 3.4.9.9-3.4z"
        fill="currentColor"
        transform="rotate(-4 11 11)"
      />
    </svg>
  )
}

function TabChat() {
  return (
    <svg width="21" height="21" viewBox="0 0 22 22" aria-hidden="true">
      <path
        fillRule="evenodd"
        d="M2.5 3.5h17v11.5h-9.8L5 19.6v-4.6H2.5zm4 3.6v2.3h2.3V7.1zm4.3 0v2.3h2.3V7.1zm4.4 0v2.3h2.3V7.1z"
        fill="currentColor"
      />
    </svg>
  )
}

function TabProfile() {
  return (
    <svg width="21" height="21" viewBox="0 0 22 22" aria-hidden="true">
      <path
        d="M11 3.2a3.6 3.6 0 1 1 0 7.2 3.6 3.6 0 0 1 0-7.2zM3.2 19.2c0-3.7 3.5-6 7.8-6s7.8 2.3 7.8 6z"
        fill="currentColor"
      />
    </svg>
  )
}

function TabCommunity() {
  return (
    <svg width="21" height="21" viewBox="0 0 22 22" aria-hidden="true">
      <path
        d="M8.5 3.5h11a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5H18v3.4l-3.6-3.4H8.5A1.5 1.5 0 0 1 7 11V5a1.5 1.5 0 0 1 1.5-1.5z"
        fill="currentColor"
        opacity="0.95"
      />
      <path
        d="M4.2 7.5H3A1.5 1.5 0 0 0 1.5 9v6A1.5 1.5 0 0 0 3 16.5h1.2v3.2l3.4-3.2h4.6c.6 0 1.1-.3 1.4-.8v-1.2H8.2L4.2 10.7z"
        fill="currentColor"
        opacity="0.55"
      />
    </svg>
  )
}

function BurgerIcon() {
  return (
    <svg width="20" height="16" viewBox="0 0 20 16" aria-hidden="true">
      <rect x="1" y="1.5" width="18" height="2.6" rx="1" fill="currentColor" />
      <rect x="1" y="6.7" width="18" height="2.6" rx="1" fill="currentColor" />
      <rect x="1" y="11.9" width="18" height="2.6" rx="1" fill="currentColor" />
    </svg>
  )
}

function CreatePlus() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 4.5v15M4.5 12h15" stroke="currentColor" strokeWidth="3.4" strokeLinecap="round" />
    </svg>
  )
}

/* ---------------- Mobile drawer (burger menu) ---------------- */

function MobileDrawer() {
  const { user, pendingRequests, unreadChats, setUser, setPendingRequests, setUnreadChats, setToast } = useRetro()
  const pathname = usePathname()
  const router = useRouter()
  const [openPath, setOpenPath] = useState<string | null>(null)
  // derived: the drawer is only open for the pathname it was opened on —
  // navigating anywhere automatically closes it (no setState-in-effect needed)
  const open = openPath !== null && openPath === pathname
  const close = () => setOpenPath(null)

  // lock body scroll + close on Escape while open
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpenPath(null)
    }
    document.addEventListener('keydown', onKey)
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = prev
    }
  }, [open])

  if (!user) return null

  async function logout() {
    setOpenPath(null)
    try {
      await api('/api/auth/logout', { method: 'POST' })
    } catch { /* ignore */ }
    clearAuthToken()
    setUser(null)
    setPendingRequests(0)
    setUnreadChats(0)
    setToast(null)
    router.push('/login')
  }

  const link = (label: string, href: string, badge?: number) => {
    const active = pathname === href
    return (
      <Link
        key={href}
        href={href}
        onClick={close}
        className={`rb-drawer-item${active ? ' rb-drawer-active' : ''}`}
      >
        <span>{label}</span>
        {badge ? <span className="rb-badge">{badge}</span> : null}
      </Link>
    )
  }

  return (
    <>
      <button
        type="button"
        className="rb-mobile-burger"
        aria-label="Open menu"
        aria-expanded={open}
        onClick={() => setOpenPath(pathname)}
      >
        <BurgerIcon />
      </button>

      {/* rendered only while open so the backdrop animates in cleanly */}
      {open && <div className="rb-drawer-backdrop" onClick={close} />}

      <div className={`rb-drawer${open ? ' rb-drawer-open' : ''}`} aria-hidden={!open}>
        <div className="rb-drawer-head">
          <Avatar user={user as RetroUser} size={38} rounded={4} />
          <div style={{ minWidth: 0 }}>
            <div style={{ color: '#fff', fontSize: 12, textShadow: '1px 1px 0 rgba(0,0,0,.45)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 130 }}>
              {user.username}
            </div>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10, color: '#bcd8ef' }}>
              <OnlineDot online={user.online} /> {user.online ? 'Online' : 'Offline'}
              {user.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
            </span>
          </div>
          <button type="button" className="rb-drawer-x" aria-label="Close menu" onClick={close}>
            ✕
          </button>
        </div>

        <div className="rb-drawer-sec">Browse</div>
        {link('Games', '/games')}
        {link('People', '/people')}
        {link('Catalog', '/catalog')}
        {link('Groups', '/groups')}
        {link('RetroLabs', '/labs')}
        {link('Communities', '/community')}

        <div className="rb-drawer-sec">You</div>
        {link('My Games', '/my')}
        {link('Avatar Editor', '/avatar')}
        {link('Favorites', '/favorites')}
        {link('Friends', '/friends', pendingRequests || undefined)}
        {link('Tix Store', '/store')}
        {user.role === 'admin' && link('Tix Admin', '/admin')}
        {link('Analytics', '/analytics')}
        {link('Player System', '/sdk')}
        {link('Settings', '/settings')}

        <div className="rb-drawer-logout">
          <button className="rb-btn rb-btn-red" style={{ width: '100%', fontSize: 12 }} onClick={logout}>
            Log Out
          </button>
        </div>
      </div>
    </>
  )
}

function MobileTabs() {
  const { user, pendingRequests, unreadChats } = useRetro()
  const pathname = usePathname()
  if (!user) return null

  const profileHref = `/users/${user.id}`
  const tabs: { label: string; href: string; icon: React.ReactNode; badge?: number; active: boolean; create?: boolean }[] = [
    { label: 'Home', href: '/', icon: <TabHome />, active: pathname === '/' },
    { label: 'Games', href: '/games', icon: <TabGames />, active: pathname.startsWith('/games') || pathname.startsWith('/my') },
    { label: 'Create', href: '/create', icon: <CreatePlus />, active: pathname.startsWith('/create'), create: true },
    { label: 'Community', href: '/community', icon: <TabCommunity />, active: pathname.startsWith('/community') || pathname.startsWith('/labs') || pathname.startsWith('/subs') || pathname.startsWith('/videos') },
    { label: 'Chat', href: '/chat', icon: <TabChat />, badge: unreadChats || undefined, active: pathname.startsWith('/chat') },
    { label: 'Profile', href: profileHref, icon: <TabProfile />, badge: pendingRequests || undefined, active: pathname === profileHref || pathname.startsWith('/settings') || pathname.startsWith('/favorites') || pathname.startsWith('/friends') || pathname.startsWith('/users') || pathname.startsWith('/analytics') },
  ]

  return (
    <nav className="rb-mobile-tabs" aria-label="Mobile navigation">
      {tabs.map((t) =>
        t.create ? (
          <Link
            key={t.label}
            href={t.href}
            className={`rb-mobile-tab rb-mobile-tab-create${t.active ? ' rb-tab-active' : ''}`}
            aria-label={t.label}
            aria-current={t.active ? 'page' : undefined}
          >
            <span className="rb-create-fab">{t.icon}</span>
            <span className="rb-ctab-label">{t.label}</span>
          </Link>
        ) : (
          <Link
            key={t.label}
            href={t.href}
            className={`rb-mobile-tab${t.active ? ' rb-tab-active' : ''}`}
            aria-label={t.label}
            aria-current={t.active ? 'page' : undefined}
          >
            {t.icon}
            <span>{t.label}</span>
            {t.badge ? <span className="rb-badge">{t.badge}</span> : null}
          </Link>
        )
      )}
    </nav>
  )
}

/* ---------------- Page shell (gate + chrome) ---------------- */

/** Sets a per-page browser tab title (every page is its own URL). */
export function Title({ t }: { t: string }) {
  useEffect(() => {
    document.title = t === 'RetroBlox' ? t : `${t} - RetroBlox`
  }, [t])
  return null
}

export function BootScreen() {
  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#0b1c2c',
        color: '#ffd34e',
        fontSize: 16,
        fontFamily: 'Verdana, sans-serif',
        flexDirection: 'column',
        gap: 12,
      }}
    >
      <img src="/retro/logo.png" alt="RetroBlox" width={72} height={72} />
      Loading RetroBlox...
    </div>
  )
}

/**
 * Roots a guest may browse without an account — like the old Roblox, you
 * could wander games and the catalog before signing up. Everything else
 * (create, chat, wallet, settings...) bounces to /login.
 */
const PUBLIC_ROOTS = ['/', '/games', '/catalog', '/labs', '/community', '/groups', '/music', '/videos', '/users', '/sdk', '/people']
function isPublicPath(p: string) {
  return PUBLIC_ROOTS.some((r) => (r === '/' ? p === '/' : p === r || p.startsWith(r + '/')))
}

/**
 * Wraps every logged-in page: waits for boot, bounces guests to /login,
 * and renders the retro header + sidebar + footer chrome around children.
 */
export function Page({ children }: { children: React.ReactNode }) {
  const { booted, user } = useRetro()
  const router = useRouter()
  const pathname = usePathname()
  const pub = isPublicPath(pathname)

  useEffect(() => {
    if (booted && !user && !pub) {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`)
    }
  }, [booted, user, router, pathname, pub])

  if (!booted) return <BootScreen />
  if (!user && !pub) return null

  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <Header />
      <main
        className="rb-main"
        style={{
          flex: 1,
          width: '100%',
          maxWidth: 1280,
          margin: '0 auto',
          padding: '20px 22px',
          display: 'flex',
          flexWrap: 'wrap',
          gap: 16,
          alignItems: 'flex-start',
          boxSizing: 'border-box',
        }}
      >
        <Sidebar />
        <div style={{ flex: 1, minWidth: 0, paddingBottom: 12 }}>{children}</div>
      </main>
      <footer className="rb-footer">
        <div>
          <span className="rb-footer-brand" style={{ verticalAlign: '-2px', marginRight: 6 }}>
            <RetroFontText text="RetroBlox" size={13} />
          </span>
          A fan-made tribute to classic blocky gaming
        </div>
        <div>
          <Link href="/" className="rb-link">Home</Link> · <Link href="/games" className="rb-link">Games</Link> ·{' '}
          <Link href="/people" className="rb-link">People</Link> ·{' '}
          <Link href="/videos" className="rb-link">Videos</Link> · <Link href="/groups" className="rb-link">Groups</Link> ·{' '}
          <Link href="/labs" className="rb-link">RetroLabs</Link> · <Link href="/community" className="rb-link">Communities</Link> ·{' '}
          <Link href="/catalog" className="rb-link">Catalog</Link> ·{' '}
          <Link href="/store" className="rb-link">Tix Store</Link> ·{' '}
          <Link href="/avatar" className="rb-link">Avatar</Link> · <Link href="/sdk" className="rb-link">Player System</Link> ·{' '}
          <Link href="/create" className="rb-link">Create</Link> ·{' '}
          {new Date().getFullYear()} RetroBlox Corporation
        </div>
        <div style={{ fontSize: 10, color: '#8ba0b3' }}>Best viewed at 1024x768 with a 56k modem</div>
      </footer>
      {user && <MobileTabs />}
    </div>
  )
}
