'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRetro, api, fmtDate, fmtCount, timeAgo, letterAvatar, flash, clearAuthToken, type RetroUser } from '@/lib/store'
import { Avatar, OnlineDot } from './Shell'
import { GameCard, GameSummary, SuggestedStrip, type SuggestedUser } from './HomeView'
import { VideoCard } from './VideosView'

/* lightweight video shape returned by /api/users/[id] */
interface ProfileVideo {
  id: string
  title: string
  thumbFileId: string | null
  views: number
  likes: number
  commentCount: number
  createdAt: string
}

/* Steam-style stats shape returned by /api/users/[id]/stats */
interface ProfileStats {
  totalSeconds: number
  weekSeconds: number
  gamesPlayed: number
  recentlyPlayed: { gameId: string; name: string; iconUrl: string | null; thumbnailUrl: string | null; genre: string; weekSeconds: number; totalSeconds: number }[]
  topPlayed: { gameId: string; name: string; iconUrl: string | null; totalSeconds: number; playCount: number; lastPlayedAt: string }[]
  badges: { id: string; name: string; desc: string; color: string; icon: string; xp: number; unlocked: boolean; unlockedAt: string | null; rarityPct: number }[]
  xp: number
  level: number
  xpIntoLevel: number
  xpForNextLevel: number
  progressPct: number
  memberSince: string
  favoriteGame: { id: string; name: string; iconUrl: string | null } | null
}

const fmtHours = (seconds: number) => {
  const h = seconds / 3600
  return h >= 10 ? `${Math.round(h)}h` : `${Math.round(h * 10) / 10}h`
}
const fmtHoursLong = (seconds: number) => {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  return h > 0 ? `${h}h ${m}m` : `${m}m`
}

/* tiny retro SVG icons for badges (no emoji — crisp at 16px) */
function BadgeIcon({ icon, color, size = 16 }: { icon: string; color: string; size?: number }) {
  const paths: Record<string, string> = {
    flag: 'M3 2v12M3 2h8l-2 3 2 3H3',
    play: 'M4 2l9 6-9 6z',
    compass: 'M12 8A5 5 0 111 8a5 5 0 0111 0zM8 5L6 9l4-2z',
    clock: 'M12 8A5 5 0 111 8a5 5 0 0111 0zM6.5 4.5V8l2.5 1.5',
    hammer: 'M2 13l5-5M7 8l4-4 3 1 1 3-4 4z',
    shirt: 'M5 2l3 2 3-2 3 3-2 2v7H4V7L2 5z',
    cart: 'M2 3h2l2 8h7l2-6H6M6 13a1 1 0 100 2 1 1 0 000-2zm7 0a1 1 0 100 2 1 1 0 000-2z',
    chest: 'M2 5h12v8H2zM2 8h12M7 8v2h2V8',
    friends: 'M5 7a2.5 2.5 0 110-5 2.5 2.5 0 010 5zm6 0a2 2 0 110-4 2 2 0 010 4zM1 13c0-2.5 2-4 4-4s4 1.5 4 4m1-4c2 0 4 1 4 4',
    chat: 'M2 3h12v8H7l-3 3v-3H2z',
    shield: 'M8 1l6 2v5c0 4-3 6-6 7-3-1-6-3-6-7V3z',
    star: 'M8 1l2 4.5 5 .5-3.7 3.3L12.5 14 8 11.5 3.5 14l1.2-4.7L1 6l5-.5z',
  }
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth="1.6" strokeLinejoin="round" strokeLinecap="round" aria-hidden>
      <path d={paths[icon] || paths.star} />
    </svg>
  )
}

/* ================= Profile (/users/[id]) ================= */

export function ProfileView({ id }: { id: string }) {
  const { user, setToast, setUser, setPendingRequests, setUnreadChats } = useRetro()
  const router = useRouter()
  const [profile, setProfile] = useState<{
    user: RetroUser & { birthday?: string | null; gender?: string | null }
    games: GameSummary[]
    favoriteGames: GameSummary[]
    videos: ProfileVideo[]
    friends: RetroUser[]
    followersCount: number
    followingCount: number
    gamesPlayed?: number
    totalPlaySeconds?: number
    isFollowing: boolean
    groups: { id: string; name: string; iconUrl: string | null; role: string }[]
    friendState: 'none' | 'friends' | 'request_sent' | 'request_received'
    friendshipId: string | null
    isMe: boolean
  } | null>(null)
  const [loading, setLoading] = useState(true)
  const [stats, setStats] = useState<ProfileStats | null>(null)
  const [bio, setBio] = useState('')
  // profile content lives in tabs — Creations (games + videos), Favorites, Groups
  const [contentTab, setContentTab] = useState<'creations' | 'favorites' | 'groups'>('creations')
  const avatarInputRef = useRef<HTMLInputElement>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [res, statsRes] = await Promise.all([
        api<NonNullable<typeof profile>>(`/api/users/${id}`),
        api<ProfileStats>(`/api/users/${id}/stats`).catch(() => null),
      ])
      setProfile(res)
      setStats(statsRes)
      setBio(res.user.bio || '')
    } catch {
      setProfile(null)
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => {
    load()
  }, [load])

  /* real per-page tab title once the profile loads */
  useEffect(() => {
    if (profile) document.title = `${profile.user.username} - RetroBlox`
  }, [profile])

  async function saveBio() {
    if (!profile) return
    try {
      await api('/api/users/me', { method: 'PATCH', body: JSON.stringify({ bio }) })
      flash(setToast, 'Profile saved!')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to save')
    }
  }

  async function uploadAvatar(file: File) {
    const fd = new FormData()
    fd.append('avatar', file)
    try {
      await api('/api/users/me', { method: 'PATCH', body: fd })
      flash(setToast, 'New profile picture uploaded!')
      if (user) {
        // refresh session user avatar everywhere
        const me = await api<{ user: RetroUser }>('/api/me')
        useRetro.getState().setUser(me.user)
      }
      await load()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Upload failed', 2400)
    }
  }

  async function friendAction(action: 'add' | 'accept' | 'decline' | 'remove' | 'cancel') {
    if (!profile) return
    try {
      if (action === 'add') {
        await api('/api/friends', { method: 'POST', body: JSON.stringify({ username: profile.user.username }) })
        flash(setToast, `Friend request sent to ${profile.user.username}!`, 2400)
      } else if (profile.friendshipId) {
        await api(`/api/friends/${profile.friendshipId}`, { method: 'POST', body: JSON.stringify({ action }) })
        flash(setToast, action === 'accept' ? 'You are now friends!' : 'Done!', 2400)
      }
      await load()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    }
  }

  async function toggleFollow() {
    if (!user) {
      router.push('/login')
      return
    }
    if (!profile) return
    try {
      const res = await api<{ following: boolean; followers: number }>('/api/follow', {
        method: 'POST',
        body: JSON.stringify({ userId: profile.user.id }),
      })
      setProfile({ ...profile, isFollowing: res.following, followersCount: res.followers })
      flash(setToast, res.following ? `You are now following ${profile.user.username}!` : 'Unfollowed.', 2200)
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    }
  }

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

  if (loading) {
    return <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#5a6b7b' }}>Loading profile...</div>
  }
  if (!profile) {
    return (
      <div className="rb-box" style={{ padding: 40, textAlign: 'center', color: '#a81a13' }}>
        User not found.
        <div style={{ marginTop: 12 }}>
          <button className="rb-btn" onClick={() => router.push('/')}>Back to Home</button>
        </div>
      </div>
    )
  }

  const p = profile.user
  const age = p.birthday ? Math.floor((Date.now() - new Date(p.birthday).getTime()) / (365.25 * 24 * 3600 * 1000)) : null

  const friendButton = () => {
    if (profile.isMe) return null
    switch (profile.friendState) {
      case 'friends':
        return (
          <div style={{ display: 'flex', gap: 6 }}>
            <button className="rb-btn" disabled>✓ Friends</button>
            <button className="rb-btn" onClick={() => friendAction('remove')}>Remove</button>
          </div>
        )
      case 'request_sent':
        return (
          <div style={{ display: 'flex', gap: 6 }}>
            <button className="rb-btn" disabled>Request Sent...</button>
            <button className="rb-btn" onClick={() => friendAction('cancel')}>Cancel</button>
          </div>
        )
      case 'request_received':
        return (
          <div style={{ display: 'flex', gap: 6 }}>
            <button className="rb-btn rb-btn-green" onClick={() => friendAction('accept')}>Accept Request</button>
            <button className="rb-btn" onClick={() => friendAction('decline')}>Decline</button>
          </div>
        )
      default:
        return <button className="rb-btn rb-btn-green" onClick={() => friendAction('add')}>+ Add as Friend</button>
    }
  }

  const followButton = () => {
    if (profile.isMe || !user) return null
    return (
      <button
        className={profile.isFollowing ? 'rb-btn' : 'rb-btn'}
        style={profile.isFollowing ? { borderColor: '#9aa6b1', color: '#5a6b7b' } : { background: 'linear-gradient(180deg,#8ec9ff,#3f7ad1)', borderColor: '#2b5cab', color: '#fff', textShadow: '1px 1px 0 rgba(0,0,0,.3)' }}
        onClick={toggleFollow}
      >
        {profile.isFollowing ? 'Following ✓' : '+ Follow'}
      </button>
    )
  }

  const messageButton = () => {
    if (profile.isMe || !user) return null
    if (profile.friendState === 'friends') {
      return (
        <Link className="rb-btn" href={`/chat/${profile.user.id}`} style={{ textDecoration: 'none' }}>
          Message
        </Link>
      )
    }
    return (
      <button className="rb-btn" disabled title="Become friends to chat privately">
        Message
      </button>
    )
  }

  return (
    <div>
      <div className="rb-box" style={{ overflow: 'hidden' }}>
        <div className="rb-panel-head"><span>{profile.isMe ? 'My Profile' : `${p.username}'s Profile`}</span></div>

        {/* banner */}
        <div
          style={{
            background: 'linear-gradient(180deg,#e9eef3,#cfd9e2)',
            padding: 14,
            display: 'flex',
            gap: 14,
            flexWrap: 'wrap',
            alignItems: 'center',
          }}
        >
          <div style={{ position: 'relative' }}>
            <img
              src={p.avatarUrl || letterAvatar(p.username)}
              alt={`${p.username} profile`}
              style={{
                width: 110,
                height: 110,
                border: '2px solid #8ba0b3',
                borderRadius: 6,
                boxShadow: '2px 2px 0 rgba(0,0,0,.18)',
                objectFit: 'cover',
                background: '#dde5ec',
              }}
            />
            <span style={{ position: 'absolute', right: 4, top: 4 }}>
              <OnlineDot online={p.online} />
            </span>
          </div>

          <div style={{ flex: 1, minWidth: 200 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 24, color: '#1c2733', margin: 0 }}>{p.username}</h1>
              {p.role === 'admin' && <span className="rb-admin-badge">ADMIN</span>}
              {stats && (
                <span
                  title={`Level ${stats.level} · ${stats.xp} XP (${stats.xpIntoLevel}/${stats.xpForNextLevel} to next)`}
                  style={{
                    background: 'linear-gradient(180deg,#67c1f5,#417a9b)',
                    color: '#fff',
                    font: 'bold 12px Verdana',
                    padding: '3px 9px',
                    borderRadius: 3,
                    border: '1px solid #2e5c7a',
                    boxShadow: '1px 1px 0 rgba(0,0,0,.2)',
                    textShadow: '0 1px 0 rgba(0,0,0,.25)',
                  }}
                >
                  LVL {stats.level}
                </span>
              )}
            </div>
            <div style={{ fontSize: 11, color: p.online ? '#2c6e31' : '#7b8896', marginTop: 4 }}>
              {p.online ? '● Online Now' : `Last Seen ${timeAgo(p.lastSeen)}`}
            </div>
            <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 6, lineHeight: 1.7 }}>
              Member Since: {fmtDate(p.createdAt)}
              {age !== null && <> · Age: {age}</>}
              {p.gender && <> · Gender: <span style={p.gender === 'female' ? { color: '#e0448c' } : { color: '#2f6fe0' }}>{p.gender === 'female' ? 'Female' : 'Male'}</span></>}
              <br />
              <span style={{ color: '#24425f' }}>{profile.friends.length}</span> Friends ·{' '}
              <Link className="rb-link" href={`/users/${p.id}/followers`} style={{ fontSize: 11 }}>
                <span style={{ color: '#24425f' }}>{profile.followersCount}</span> Followers
              </Link>{' '}
              ·{' '}
              <Link className="rb-link" href={`/users/${p.id}/following`} style={{ fontSize: 11 }}>
                <span style={{ color: '#24425f' }}>{profile.followingCount}</span> Following
              </Link>
              {' · '}
              Games Published: {profile.games.length} · Total Downloads:{' '}
              {fmtCount(profile.games.reduce((s, g) => s + g.downloads, 0))}
            </div>
            {/* every member has an ID — copyable, like the classic profile pages */}
            <div style={{ fontSize: 11, color: '#5a6b7b', marginTop: 4, display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
              <span>
                ID: <span style={{ fontFamily: 'monospace', color: '#24425f' }}>{p.id}</span>
              </span>
              <button
                type="button"
                className="rb-btn"
                style={{ fontSize: 9, padding: '2px 8px' }}
                title="Copy this member's ID"
                onClick={() => {
                  try {
                    navigator.clipboard.writeText(p.id)
                    flash(setToast, 'ID copied!', 1600)
                  } catch {
                    flash(setToast, p.id, 3000)
                  }
                }}
              >
                Copy ID
              </button>
            </div>
            <div style={{ marginTop: 10, display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
              {friendButton()}
              {followButton()}
              {messageButton()}
              {profile.isMe && (
                <>
                  <input
                    ref={avatarInputRef}
                    type="file"
                    accept="image/*"
                    style={{ display: 'none' }}
                    onChange={(e) => {
                      const f = e.target.files?.[0]
                      if (f) uploadAvatar(f)
                      e.target.value = ''
                    }}
                  />
                  <button className="rb-btn" onClick={() => avatarInputRef.current?.click()}>
                    Change Profile Picture
                  </button>
                  <Link className="rb-btn" href="/settings" style={{ textDecoration: 'none' }}>
                    Settings
                  </Link>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Steam-style profile stat chips */}
        <div style={{ padding: '10px 12px', borderTop: '1px solid #e4eaf0', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {[
            ['🎮 Games Played', profile.gamesPlayed ?? 0, 'games they have hit Play now on'],
            ['⏱ Playtime', stats ? fmtHours(stats.totalSeconds) : '—', 'time played in RetroBlox games'],
            ['📅 Last 2 Weeks', stats ? fmtHours(stats.weekSeconds) : '—', 'playtime in the last 2 weeks'],
            ['🛠 Games Created', profile.games.length, 'games published'],
            ['⭐ Favorites', profile.favoriteGames.length, 'games favorited'],
            ['👥 Followers', profile.followersCount, 'players following them'],
          ].map(([label, value, title]) => (
            <div
              key={String(label)}
              title={String(title)}
              style={{
                flex: '1 1 110px',
                textAlign: 'center',
                background: 'linear-gradient(180deg,#f6f9fc,#e9eff5)',
                border: '1px solid #b4c2cf',
                borderRadius: 4,
                padding: '8px 6px',
                boxShadow: '1px 1px 0 rgba(0,0,0,.08)',
              }}
            >
              <div style={{ font: 'bold 19px Verdana', color: '#24425f', lineHeight: 1.1 }}>{String(value)}</div>
              <div style={{ fontSize: 9, color: '#5a6b7b', marginTop: 2 }}>{String(label)}</div>
            </div>
          ))}
        </div>

        {/* bio */}
        <div style={{ padding: 12, borderTop: '1px solid #e4eaf0' }}>
          <div style={{ fontSize: 11, color: '#24425f', marginBottom: 5 }}>About</div>
          {profile.isMe ? (
            <div>
              <textarea className="rb-textarea" value={bio} onChange={(e) => setBio(e.target.value)} rows={3} maxLength={300} style={{ width: '100%' }} placeholder="Tell everyone about yourself..." aria-label="Bio" />
              <button className="rb-btn" style={{ marginTop: 6 }} onClick={saveBio}>Save Bio</button>
            </div>
          ) : (
            <div style={{ fontSize: 12, color: '#2c3e50', lineHeight: 1.6 }}>
              {p.bio || 'This blockhead has not written anything yet.'}
            </div>
          )}
        </div>

        {/* Steam-style XP progress toward the next level */}
        {stats && (
          <div style={{ padding: '10px 12px', borderTop: '1px solid #e4eaf0' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 5 }}>
              <span style={{ font: 'bold 11px Verdana', color: '#24425f' }}>Level {stats.level}</span>
              <span style={{ fontSize: 10, color: '#5a6b7b' }}>
                {stats.xp} XP · {stats.xpForNextLevel - stats.xpIntoLevel} XP to Level {stats.level + 1}
              </span>
            </div>
            <div style={{ height: 12, background: '#dfe7ee', border: '1px solid #a9b9c7', borderRadius: 3, overflow: 'hidden' }}>
              <div
                style={{
                  width: `${stats.progressPct}%`,
                  height: '100%',
                  background: 'repeating-linear-gradient(45deg,#67c1f5 0 8px,#4fa3d8 8px 16px)',
                  boxShadow: 'inset 0 -2px 0 rgba(0,0,0,.15)',
                }}
              />
            </div>
          </div>
        )}

        {/* Steam-style Recently Played — hours over the last 2 weeks */}
        {stats && stats.recentlyPlayed.length > 0 && (
          <div style={{ padding: '10px 12px', borderTop: '1px solid #e4eaf0' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span style={{ font: 'bold 11px Verdana', color: '#24425f' }}>Recently Played</span>
              <span style={{ fontSize: 10, color: '#5a6b7b' }}>Last 2 Weeks · {fmtHours(stats.weekSeconds)} total</span>
            </div>
            <div style={{ marginTop: 8, display: 'grid', gap: 6 }}>
              {stats.recentlyPlayed.map((g) => (
                <Link
                  key={g.gameId}
                  href={`/games/${g.gameId}`}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 10,
                    textDecoration: 'none',
                    background: 'linear-gradient(180deg,#f6f9fc,#e9eff5)',
                    border: '1px solid #b4c2cf',
                    borderRadius: 4,
                    padding: '6px 8px',
                  }}
                >
                  <img
                    src={g.iconUrl || g.thumbnailUrl || letterAvatar(g.name)}
                    alt=""
                    style={{ width: 34, height: 34, borderRadius: 3, border: '1px solid #8ba0b3', objectFit: 'cover', background: '#dde5ec' }}
                  />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 12, fontWeight: 'bold', color: '#1c2733', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{g.name}</div>
                    <div style={{ fontSize: 10, color: '#5a6b7b' }}>{g.genre}</div>
                    <div style={{ height: 6, background: '#dfe7ee', border: '1px solid #a9b9c7', borderRadius: 2, marginTop: 3, overflow: 'hidden' }}>
                      <div
                        style={{
                          width: `${Math.max(4, Math.round((g.weekSeconds / Math.max(1, stats.recentlyPlayed[0].weekSeconds)) * 100))}%`,
                          height: '100%',
                          background: '#67c1f5',
                        }}
                      />
                    </div>
                  </div>
                  <div style={{ textAlign: 'right', flexShrink: 0 }}>
                    <div style={{ font: 'bold 12px Verdana', color: '#24425f' }}>{fmtHours(g.weekSeconds)}</div>
                    <div style={{ fontSize: 9, color: '#7b8896' }}>last 2 weeks</div>
                    {g.totalSeconds > g.weekSeconds && (
                      <div style={{ fontSize: 9, color: '#7b8896' }}>{fmtHours(g.totalSeconds)} total</div>
                    )}
                  </div>
                </Link>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Steam-style badge showcase — every badge, unlocked or not */}
      {stats && (
        <div className="rb-box" style={{ marginTop: 12 }}>
          <div className="rb-panel-head">
            <span>Badges ({stats.badges.filter((b) => b.unlocked).length}/{stats.badges.length})</span>
            <span style={{ fontSize: 10, color: '#5a6b7b' }}>{stats.xp} XP earned</span>
          </div>
          <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: 8 }}>
            {stats.badges.map((b) => (
              <div
                key={b.id}
                title={b.unlocked ? `${b.name} — ${b.desc} (${b.xp} XP, unlocked ${b.unlockedAt ? fmtDate(b.unlockedAt) : ''})` : `${b.name} — ${b.desc} (${b.xp} XP, locked)`}
                style={{
                  display: 'flex',
                  gap: 8,
                  alignItems: 'center',
                  background: b.unlocked ? 'linear-gradient(180deg,#f6f9fc,#e9eff5)' : '#eef1f4',
                  border: `1px solid ${b.unlocked ? '#b4c2cf' : '#d5dde4'}`,
                  borderRadius: 4,
                  padding: '7px 8px',
                  opacity: b.unlocked ? 1 : 0.55,
                  filter: b.unlocked ? 'none' : 'grayscale(1)',
                }}
              >
                <div
                  style={{
                    width: 30,
                    height: 30,
                    borderRadius: 3,
                    border: `2px solid ${b.color}`,
                    background: b.unlocked ? `${b.color}22` : '#e8ecef',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                  }}
                >
                  <BadgeIcon icon={b.icon} color={b.unlocked ? b.color : '#9aa7b2'} size={17} />
                </div>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontSize: 11, fontWeight: 'bold', color: b.unlocked ? '#1c2733' : '#7b8896', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {b.name}
                  </div>
                  <div style={{ fontSize: 9, color: '#5a6b7b', lineHeight: 1.3 }}>
                    {b.unlocked ? <>Unlocked{b.rarityPct > 0 ? ` · ${b.rarityPct}% of players` : ''}</> : 'Locked'}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* mobile account menu — the sidebar is hidden on phones, so these live here */}
      {profile.isMe && (
        <div className="rb-box rb-mobile-only" style={{ marginTop: 12 }}>
          <div className="rb-panel-head"><span>My Account</span></div>
          <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(130px, 1fr))', gap: 8 }}>
            {[
              ['Friends', '/friends'],
              ['Chat', '/chat'],
              ['Favorites', '/favorites'],
              ['My Games', '/my'],
              ['Videos', '/videos'],
              ['Analytics', '/analytics'],
              ['Settings', '/settings'],
            ].map(([label, href]) => (
              <Link
                key={href}
                href={href}
                className="rb-btn"
                style={{ display: 'block', textAlign: 'center', textDecoration: 'none', padding: '8px 6px' }}
              >
                {label}
              </Link>
            ))}
          </div>
          <div style={{ padding: '0 10px 10px' }}>
            <button className="rb-btn rb-btn-red" style={{ width: '100%', fontSize: 11 }} onClick={logout}>
              Log Out
            </button>
          </div>
        </div>
      )}

      {/* friends — public: anyone can see how many friends they have and who */}
      <div className="rb-box" style={{ marginTop: 12 }}>
        <div className="rb-panel-head">
          <span>Friends ({profile.friends.length})</span>
          {profile.isMe && (
            <Link className="rb-link" style={{ fontSize: 11 }} href="/friends">
              Manage Friends &rarr;
            </Link>
          )}
        </div>
        <div style={{ padding: 10, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {profile.friends.length === 0 && (
            <div style={{ color: '#7b8896', fontSize: 11, padding: 4 }}>
              {profile.isMe ? 'No friends yet — send some requests!' : `${p.username} has no friends yet. Be their first!`}
            </div>
          )}
          {profile.friends.map((f) => (
            <Link
              key={f.id}
              href={`/users/${f.id}`}
              className="rb-clickable"
              style={{
                width: 78,
                flexShrink: 0,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 4,
                textAlign: 'center',
                textDecoration: 'none',
              }}
              aria-label={`View ${f.username}'s profile`}
            >
              <span style={{ position: 'relative', display: 'inline-block' }}>
                <Avatar user={f} size={50} rounded="50%" />
                <span style={{ position: 'absolute', right: 0, bottom: 1 }}>
                  <OnlineDot online={f.online} />
                </span>
              </span>
              <span
                className="rb-link"
                style={{ fontSize: 10, maxWidth: 78, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', display: 'block' }}
              >
                {f.username}
              </span>
            </Link>
          ))}
        </div>
      </div>

      {/* content tabs — Creations / Favorites / Groups (was four stacked boxes) */}
      <div className="rb-box" style={{ marginTop: 12 }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>{profile.isMe ? 'My Content' : `${p.username}'s Content`}</span>
          <span style={{ display: 'flex', gap: 3 }} role="tablist" aria-label="Profile sections">
            {([
              ['creations', `Creations (${profile.games.length + profile.videos.length})`],
              ['favorites', `Favorites (${profile.favoriteGames.length})`],
              ['groups', `Groups (${profile.groups.length})`],
            ] as const).map(([t, label]) => (
              <button
                key={t}
                type="button"
                role="tab"
                aria-selected={contentTab === t}
                onClick={() => setContentTab(t)}
                className="rb-btn"
                style={{
                  fontSize: 10, padding: '1px 10px',
                  background: contentTab === t ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : '#fff',
                  color: contentTab === t ? '#fff' : '#1c4e7c',
                }}
              >
                {label}
              </button>
            ))}
          </span>
        </div>

        {/* CREATIONS tab — their games + videos */}
        {contentTab === 'creations' && (
        <div style={{ padding: 12 }}>
          {profile.games.length === 0 && profile.videos.length === 0 && (
            <div style={{ color: '#7b8896', fontSize: 11, padding: 8 }}>
              Nothing published yet.
              {profile.isMe && (
                <>
                  <Link className="rb-btn" style={{ marginLeft: 8, textDecoration: 'none', display: 'inline-block' }} href="/create">Publish a game!</Link>
                  <Link className="rb-btn" style={{ marginLeft: 8, textDecoration: 'none', display: 'inline-block' }} href="/videos">Upload a video!</Link>
                </>
              )}
            </div>
          )}
          {profile.videos.length > 0 && (
            <div style={{ marginBottom: profile.games.length > 0 ? 14 : 0 }}>
              <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span>Videos ({profile.videos.length})</span>
                <Link className="rb-link" style={{ fontSize: 10 }} href={`/videos?sort=new`}>Browse Videos &rarr;</Link>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(190px, 1fr))', gap: 10 }}>
                {profile.videos.map((v) => (
                  <VideoCard
                    key={v.id}
                    video={{
                      id: v.id,
                      title: v.title,
                      description: '',
                      fileId: '',
                      fileName: null,
                      thumbFileId: v.thumbFileId,
                      views: v.views,
                      likes: v.likes,
                      dislikes: 0,
                      myVote: 0,
                      commentCount: v.commentCount,
                      createdAt: v.createdAt,
                      author: { id: p.id, username: p.username, avatarUrl: p.avatarUrl, online: p.online, role: p.role },
                    }}
                  />
                ))}
              </div>
            </div>
          )}
          {profile.games.length > 0 && (
            <div>
              <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>Games ({profile.games.length})</div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(170px, 1fr))', gap: 10 }}>
                {profile.games.map((g) => <GameCard key={g.id} game={g} />)}
              </div>
            </div>
          )}
        </div>
        )}

        {/* FAVORITES tab */}
        {contentTab === 'favorites' && (
        <div style={{ padding: 12 }}>
          {profile.favoriteGames.length === 0 ? (
            <div style={{ color: '#7b8896', fontSize: 11, padding: 8 }}>
              No favorite games yet — tap the star on any game page.
            </div>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(170px, 1fr))', gap: 10 }}>
              {profile.favoriteGames.map((g) => <GameCard key={g.id} game={g} />)}
            </div>
          )}
        </div>
        )}

        {/* GROUPS tab */}
        {contentTab === 'groups' && (
        <div style={{ padding: 12 }}>
          {profile.groups.length === 0 ? (
            <div style={{ color: '#7b8896', fontSize: 11, padding: 8 }}>
              Not in any groups yet — <Link href="/community" className="rb-link">browse communities</Link> to find one.
            </div>
          ) : (
            <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
              {profile.groups.map((g) => (
                <Link
                  key={g.id}
                  href={`/groups/${g.id}`}
                  className="rb-clickable"
                  style={{ display: 'flex', alignItems: 'center', gap: 8, border: '1px solid #c3cdd7', borderRadius: 4, padding: '6px 12px 6px 6px', background: '#fff', textDecoration: 'none' }}
                >
                  <span style={{ width: 30, height: 30, borderRadius: 4, border: '1px solid #8ba0b3', background: '#eef4fa', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: '#5a7b9a', overflow: 'hidden' }}>
                    {g.iconUrl ? <img src={g.iconUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : '?'}
                  </span>
                  <span>
                    <span className="rb-link" style={{ fontSize: 11, display: 'block' }}>{g.name}</span>
                    <span style={{ fontSize: 9, color: '#7b8896' }}>{g.role === 'owner' ? 'Group Owner' : 'Member'}</span>
                  </span>
                </Link>
              ))}
            </div>
          )}
        </div>
        )}
      </div>
    </div>
  )
}

/* ================= Followers / Following (/users/[id]/followers|following) ================= */

export function FollowListView({ id, type }: { id: string; type: 'followers' | 'following' }) {
  const { user, setToast } = useRetro()
  const router = useRouter()
  const [owner, setOwner] = useState<{ username: string } | null>(null)
  const [data, setData] = useState<{ list: RetroUser[]; key: string } | null>(null)
  const [followStates, setFollowStates] = useState<Record<string, boolean>>({})
  const [error, setError] = useState('')

  const key = `${id}|${type}`
  const loading = !data || data.key !== key
  const people = data?.key === key ? data.list : []

  useEffect(() => {
    let cancelled = false
    api<{ user: { username: string } }>(`/api/users/${id}`)
      .then((r) => !cancelled && setOwner(r.user))
      .catch(() => {})
    api<{ followers: RetroUser[]; following: RetroUser[]; isFollowing: boolean }>(`/api/follow?userId=${id}`)
      .then((r) => {
        if (cancelled) return
        const list = type === 'followers' ? r.followers : r.following
        setData({ list, key })
        setError('')
        // seed local follow states (am I following each person?)
        Promise.all(
          list.map((p) =>
            api<{ isFollowing: boolean }>(`/api/follow?userId=${p.id}`).then((f) => [p.id, f.isFollowing] as const).catch(() => [p.id, false] as const)
          )
        ).then((pairs) => {
          if (cancelled) return
          setFollowStates((s) => ({ ...s, ...Object.fromEntries(pairs) }))
        })
      })
      .catch((e) => {
        if (cancelled) return
        setData({ list: [], key })
        setError(e instanceof Error ? e.message : 'Failed to load')
      })
    return () => {
      cancelled = true
    }
  }, [id, type, key])

  useEffect(() => {
    document.title = type === 'followers' ? 'Followers - RetroBlox' : 'Following - RetroBlox'
  }, [type])

  async function toggle(targetId: string) {
    if (!user) {
      router.push('/login')
      return
    }
    try {
      const res = await api<{ following: boolean }>('/api/follow', {
        method: 'POST',
        body: JSON.stringify({ userId: targetId }),
      })
      setFollowStates((s) => ({ ...s, [targetId]: res.following }))
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed')
    }
  }

  const label = type === 'followers' ? 'Followers' : 'Following'

  return (
    <div className="rb-box">
      <div className="rb-panel-head">
        <span>
          {owner ? `${owner.username}'s ${label}` : label} {loading ? '' : `(${people.length})`}
        </span>
        <Link className="rb-link" style={{ fontSize: 11 }} href={`/users/${id}`}>
          &larr; Back to Profile
        </Link>
      </div>
      <div style={{ padding: 12, display: 'grid', gap: 8 }}>
        {error && <div style={{ color: '#a81a13', fontSize: 11 }}>{error}</div>}
        {loading && <div style={{ color: '#7b8896', fontSize: 11 }}>Loading {label.toLowerCase()}...</div>}
        {!loading && !error && people.length === 0 && (
          <div style={{ color: '#7b8896', fontSize: 11, padding: 8, textAlign: 'center' }}>
            {type === 'followers' ? 'Nobody follows this blockhead yet.' : 'This blockhead is not following anyone yet.'}
          </div>
        )}
        {people.map((p) => (
          <div key={p.id} className="rb-box" style={{ padding: 10, display: 'flex', alignItems: 'center', gap: 10 }}>
            <Link href={`/users/${p.id}`} className="rb-clickable" style={{ position: 'relative', display: 'inline-block', flexShrink: 0 }} aria-label={`View ${p.username}`}>
              <Avatar user={p} size={44} rounded="50%" />
              <span style={{ position: 'absolute', right: -2, bottom: 0 }}>
                <OnlineDot online={p.online} />
              </span>
            </Link>
            <div style={{ flex: 1, minWidth: 0 }}>
              <Link className="rb-link" style={{ fontSize: 12, display: 'block' }} href={`/users/${p.id}`}>
                {p.username}
              </Link>
              <div style={{ fontSize: 10, color: '#7b8896' }}>
                Joined {fmtDate(p.createdAt)} · {p.online ? 'Online now' : 'Offline'}
              </div>
            </div>
            {user && user.id !== p.id && (
              <button
                className="rb-btn"
                style={followStates[p.id] ? { borderColor: '#9aa6b1', color: '#5a6b7b' } : { background: 'linear-gradient(180deg,#8ec9ff,#3f7ad1)', borderColor: '#2b5cab', color: '#fff' }}
                onClick={() => toggle(p.id)}
              >
                {followStates[p.id] ? 'Following ✓' : '+ Follow'}
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}

/* ================= Friends (/friends) ================= */

export function FriendsView() {
  const { user, setToast, setPendingRequests } = useRetro()
  const router = useRouter()
  const [friends, setFriends] = useState<(RetroUser & { friendshipId: string })[]>([])
  const [incoming, setIncoming] = useState<{ id: string; user: RetroUser }[]>([])
  const [outgoing, setOutgoing] = useState<{ id: string; user: RetroUser }[]>([])
  const [suggested, setSuggested] = useState<SuggestedUser[]>([])
  const [similar, setSimilar] = useState<SuggestedUser[]>([])
  const [similarFor, setSimilarFor] = useState('')
  const [addName, setAddName] = useState('')
  const [msg, setMsg] = useState('')
  const [loading, setLoading] = useState(true)
  const [sessionError, setSessionError] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [res, s] = await Promise.all([
        api<{ friends: (RetroUser & { friendshipId: string })[]; incoming: { id: string; user: RetroUser }[]; outgoing: { id: string; user: RetroUser }[] }>('/api/friends'),
        api<{ suggested: SuggestedUser[] }>('/api/friends/suggested'),
      ])
      setFriends(res.friends)
      setIncoming(res.incoming)
      setOutgoing(res.outgoing)
      setPendingRequests(res.incoming.length)
      setSuggested(s.suggested || [])
      setSessionError(false)
    } catch (e) {
      // 401 = our session cookie died (e.g. stale tab). Say so instead of showing an empty list.
      if (e instanceof Error && /login required/i.test(e.message)) setSessionError(true)
    } finally {
      setLoading(false)
    }
  }, [setPendingRequests])

  useEffect(() => {
    if (user) load()
  }, [user, load])

  // "send a request to RetroBlox and RetroBloxian shows up" — the
  // closest name matches, closest first (the API sorts by similarity)
  async function loadSimilar(name: string, excludeId?: string) {
    try {
      const s = await api<{ similar: SuggestedUser[] }>(
        `/api/users/similar?name=${encodeURIComponent(name)}${excludeId ? `&exclude=${excludeId}` : ''}`
      )
      setSimilar(s.similar || [])
      setSimilarFor(name)
    } catch {
      setSimilar([])
    }
  }

  async function addFriend() {
    setMsg('')
    if (!addName.trim()) return
    const name = addName.trim()
    try {
      const res = await api<{ autoAccepted?: boolean; user?: RetroUser }>('/api/friends', {
        method: 'POST',
        body: JSON.stringify({ username: name }),
      })
      flash(setToast, res.autoAccepted ? `You and ${name} are now friends!` : `Friend request sent to ${name}!`, 2400)
      setAddName('')
      await load()
      // the request went through — surface players with similar names
      void loadSimilar(name, res.user?.id)
    } catch (e) {
      const m = e instanceof Error ? e.message : 'Failed'
      if (/no user named/i.test(m)) {
        // no exact match — show the closest real usernames instead
        setMsg(`No player named "${name}" — did you mean one of these?`)
        void loadSimilar(name)
      } else {
        setMsg(m)
      }
    }
  }

  async function act(friendshipId: string, action: 'accept' | 'decline' | 'remove' | 'cancel') {
    try {
      await api(`/api/friends/${friendshipId}`, { method: 'POST', body: JSON.stringify({ action }) })
      await load()
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2200)
    }
  }

  if (!user) return null

  return (
    <div>
      {sessionError && (
        <div className="rb-box" role="alert" style={{ marginBottom: 12, border: '2px solid #c81c14' }}>
          <div className="rb-panel-head"><span>Session expired</span></div>
          <div style={{ padding: 12, fontSize: 11, color: '#5a6b7b', lineHeight: 1.6 }}>
            You are not logged in on this device anymore, so friends cannot load. Log in again and everything comes back.
          </div>
          <div style={{ padding: '0 12px 12px' }}>
            <button className="rb-btn rb-btn-green" onClick={() => router.push('/login?next=%2Ffriends')}>Log In Again</button>
          </div>
        </div>
      )}

      {/* add friend */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>Add Friends</span></div>
        <div style={{ padding: 12, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <input
            className="rb-input"
            placeholder="Type a username to add..."
            value={addName}
            onChange={(e) => setAddName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && addFriend()}
            style={{ flex: 1, minWidth: 180 }}
            aria-label="Username to add"
          />
          <button className="rb-btn rb-btn-green" onClick={addFriend}>Send Friend Request</button>
        </div>
        {msg && <div style={{ padding: '0 12px 10px', color: '#a81a13', fontSize: 11 }}>{msg}</div>}
      </div>

      {/* similar-name players — closest match on top */}
      {similar.length > 0 && (
        <SuggestedStrip users={similar} title={`Players like "${similarFor}"`} />
      )}

      {/* incoming requests */}
      {incoming.length > 0 && (
        <div className="rb-box" style={{ marginBottom: 12 }}>
          <div className="rb-panel-head"><span>Friend Requests ({incoming.length})</span></div>
          <div style={{ padding: 10, display: 'grid', gap: 8 }}>
            {incoming.map((r) => (
              <div key={r.id} style={{ display: 'flex', alignItems: 'center', gap: 10, background: '#fdf6e4', border: '1px solid #e0d3a6', borderRadius: 4, padding: 8 }}>
                <Avatar user={r.user} size={40} />
                <div style={{ flex: 1 }}>
                  <Link className="rb-link" style={{ fontSize: 12 }} href={`/users/${r.user.id}`}>
                    {r.user.username}
                  </Link>
                  <div style={{ fontSize: 10, color: '#7b8896' }}>wants to be your friend</div>
                </div>
                <button className="rb-btn rb-btn-green" onClick={() => act(r.id, 'accept')}>Accept</button>
                <button className="rb-btn" onClick={() => act(r.id, 'decline')}>Decline</button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* outgoing */}
      {outgoing.length > 0 && (
        <div className="rb-box" style={{ marginBottom: 12 }}>
          <div className="rb-panel-head"><span>Sent Requests ({outgoing.length})</span></div>
          <div style={{ padding: 10, display: 'grid', gap: 8 }}>
            {outgoing.map((r) => (
              <div key={r.id} style={{ display: 'flex', alignItems: 'center', gap: 10, borderBottom: '1px solid #eef2f6', paddingBottom: 8 }}>
                <Avatar user={r.user} size={32} />
                <div style={{ flex: 1, fontSize: 11, color: '#24425f' }}>{r.user.username}</div>
                <span style={{ fontSize: 10, color: '#7b8896', fontStyle: 'italic' }}>pending...</span>
                <button className="rb-btn" onClick={() => act(r.id, 'cancel')}>Cancel</button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* friends grid */}
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head"><span>My Friends ({friends.length})</span></div>
        <div style={{ padding: 12, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 10 }}>
          {loading && <div style={{ color: '#7b8896', fontSize: 11 }}>Loading friends...</div>}
          {!loading && friends.length === 0 && (
            <div style={{ color: '#7b8896', fontSize: 11, padding: 6 }}>
              No friends yet. Send a request by username above, or add similar players below!
            </div>
          )}
          {friends.map((f) => (
            <div key={f.id} className="rb-box" style={{ padding: 10, display: 'flex', alignItems: 'center', gap: 10 }}>
              <Link href={`/users/${f.id}`} className="rb-clickable" style={{ position: 'relative', display: 'inline-block' }} aria-label={`View ${f.username}`}>
                <Avatar user={f} size={48} />
                <span style={{ position: 'absolute', right: -2, bottom: 0 }}>
                  <OnlineDot online={f.online} />
                </span>
              </Link>
              <div style={{ flex: 1, minWidth: 0 }}>
                <Link className="rb-link" style={{ fontSize: 12, display: 'block' }} href={`/users/${f.id}`}>
                  {f.username}
                </Link>
                <div style={{ fontSize: 10, color: f.online ? '#2c6e31' : '#7b8896' }}>
                  {f.online ? '● Online' : 'Offline'}
                </div>
              </div>
              <button className="rb-btn" style={{ fontSize: 9, padding: '3px 7px' }} onClick={() => act(f.friendshipId, 'remove')}>Remove</button>
            </div>
          ))}
        </div>
      </div>

      {/* similar people */}
      {!loading && suggested.length > 0 && (
        <SuggestedStrip users={suggested} title="People You May Know" />
      )}
    </div>
  )
}
