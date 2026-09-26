'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useRetro, api, fmtDate, letterAvatar, flash, type RetroUser } from '@/lib/store'
import { OnlineDot } from './Shell'

/* Settings (/settings): upload a custom profile photo, edit bio, log out. */

export function SettingsView() {
  const { user, setUser, setToast, setPendingRequests } = useRetro()
  const router = useRouter()
  const [bio, setBio] = useState('')
  const [busy, setBusy] = useState(false)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  // settings live in tabs — Profile (photo + bio), Account, Security (data + session)
  const [tab, setTab] = useState<'profile' | 'account' | 'security'>('profile')

  useEffect(() => {
    if (user) setBio(user.bio || '')
  }, [user])

  async function uploadAvatar(file: File) {
    setBusy(true)
    const fd = new FormData()
    fd.append('avatar', file)
    try {
      const res = await api<{ user: RetroUser }>('/api/users/me', { method: 'PATCH', body: fd })
      setUser(res.user)
      setPreviewUrl(null)
      flash(setToast, 'Profile picture updated!')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Upload failed', 2400)
    } finally {
      setBusy(false)
    }
  }

  async function removeAvatar() {
    setBusy(true)
    try {
      const res = await api<{ user: RetroUser }>('/api/users/me', {
        method: 'PATCH',
        body: JSON.stringify({ avatarRemove: true }),
      })
      setUser(res.user)
      flash(setToast, 'Profile picture removed.')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed', 2400)
    } finally {
      setBusy(false)
    }
  }

  async function saveBio() {
    setBusy(true)
    try {
      const res = await api<{ user: RetroUser }>('/api/users/me', {
        method: 'PATCH',
        body: JSON.stringify({ bio }),
      })
      setUser(res.user)
      flash(setToast, 'Profile saved!')
    } catch (e) {
      flash(setToast, e instanceof Error ? e.message : 'Failed to save', 2400)
    } finally {
      setBusy(false)
    }
  }

  async function logout() {
    try {
      await api('/api/auth/logout', { method: 'POST' })
    } catch { /* ignore */ }
    setUser(null)
    setPendingRequests(0)
    setToast(null)
    router.push('/login')
  }

  if (!user) return null

  const shownAvatar = previewUrl || user.avatarUrl || letterAvatar(user.username)

  return (
    <div style={{ maxWidth: 640 }}>
      <div className="rb-box" style={{ marginBottom: 12 }}>
        <div className="rb-panel-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Settings</span>
          <span style={{ display: 'flex', gap: 3 }} role="tablist" aria-label="Settings sections">
            {([['profile', 'Profile'], ['account', 'Account'], ['security', 'Security']] as const).map(([t, label]) => (
              <button
                key={t}
                type="button"
                role="tab"
                aria-selected={tab === t}
                onClick={() => setTab(t)}
                className="rb-btn"
                style={{
                  fontSize: 10, padding: '1px 10px',
                  background: tab === t ? 'linear-gradient(180deg,#3d7dbd,#2a5f96)' : '#fff',
                  color: tab === t ? '#fff' : '#1c4e7c',
                }}
              >
                {label}
              </button>
            ))}
          </span>
        </div>

        {/* PROFILE tab — profile picture + about me */}
        {tab === 'profile' && (
        <div style={{ padding: 14, display: 'grid', gap: 14 }}>
          <div>
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>Profile Picture</div>
            <div style={{ display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
              <img
                src={shownAvatar}
                alt={`${user.username}'s avatar`}
                style={{ width: 96, height: 96, borderRadius: 6, border: '2px solid #8ba0b3', objectFit: 'cover', background: '#dde5ec' }}
              />
              <div style={{ flex: 1, minWidth: 200 }}>
                <div style={{ fontSize: 11, color: '#5a6b7b', marginBottom: 8, lineHeight: 1.5 }}>
                  Upload any photo to use as your custom profile image. It shows on your profile,
                  comments, friend lists and the header. PNG or JPG, up to 2MB.
                </div>
                <input
                  ref={fileRef}
                  type="file"
                  accept="image/*"
                  style={{ display: 'none' }}
                  onChange={(e) => {
                    const f = e.target.files?.[0]
                    if (!f) return
                    setPreviewUrl(URL.createObjectURL(f))
                    uploadAvatar(f)
                    e.target.value = ''
                  }}
                />
                <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                  <button className="rb-btn rb-btn-green" disabled={busy} onClick={() => fileRef.current?.click()}>
                    Upload Photo
                  </button>
                  {user.avatarUrl && (
                    <button className="rb-btn" disabled={busy} onClick={removeAvatar}>
                      Remove Photo
                    </button>
                  )}
                </div>
              </div>
            </div>
          </div>
          <div>
            <div style={{ fontSize: 11, color: '#1c4e7c', marginBottom: 6 }}>About Me</div>
            <textarea
              className="rb-textarea"
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              rows={3}
              maxLength={300}
              style={{ width: '100%' }}
              placeholder="Tell everyone about yourself..."
              aria-label="Bio"
            />
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 6 }}>
              <button className="rb-btn rb-btn-green" disabled={busy} onClick={saveBio}>Save Bio</button>
              <span style={{ fontSize: 10, color: '#7b8896' }}>{bio.length}/300</span>
            </div>
          </div>
        </div>
        )}

        {/* ACCOUNT tab — who you are on RetroBlox */}
        {tab === 'account' && (
        <div style={{ padding: 14, fontSize: 12, color: '#2c3e50', lineHeight: 1.9 }}>
          <div>
            Username: {user.username}
            {user.role === 'admin' && <> <span className="rb-admin-badge">ADMIN</span></>}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            Status: <OnlineDot online={user.online} /> {user.online ? 'Online' : 'Offline'}
          </div>
          <div>Member since: {fmtDate(user.createdAt)}</div>
          {user.gender && <div>Gender: {user.gender === 'female' ? 'Female' : 'Male'}</div>}
        </div>
        )}

        {/* SECURITY tab — data safety + session */}
        {tab === 'security' && (
        <div style={{ padding: 14, display: 'grid', gap: 14 }}>
          <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <span
              aria-hidden="true"
              style={{
                flexShrink: 0,
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                width: 34,
                height: 34,
                background: 'linear-gradient(180deg,#9fd07e,#5f9e3e)',
                border: '1px solid #3f6e28',
                borderRadius: 4,
                boxShadow: 'inset 1px 1px 0 rgba(255,255,255,.5)',
                fontSize: 18,
                color: '#fff',
                textShadow: '1px 1px 0 #3f6e28',
              }}
            >
              ✓
            </span>
            <div>
              <div style={{ marginBottom: 4 }}>Your stuff is saved — even when RetroBlox gets updated.</div>
              Your account, games, videos, posts, friends and messages live on the RetroBlox
              server (not in this browser), and the site keeps automatic backups every time it
              starts. Updates no longer remove anything you made — everything you publish stays
              right where you left it, on any device you log in from. Deleted UGC even stays
              restorable by an admin, so nothing is ever gone for good.
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', borderTop: '1px solid #dbe4ec', paddingTop: 12 }}>
            <span style={{ fontSize: 11, color: '#5a6b7b', flex: 1, minWidth: 180 }}>
              Done playing? Log out of RetroBlox on this device.
            </span>
            <button className="rb-btn rb-btn-red" onClick={logout}>Log Out</button>
          </div>
        </div>
        )}
      </div>
    </div>
  )
}
